# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
#
#
# This component is dedicated to LCG DPM (Disk Pool Manager) and
# LFC (Logical File Catalog) configuration management. It hs been designed
# to be very flexible and need no major change to handle changes in
# configuration file format, by using parsing rules to update the contents
# of configuration files. When provided, this component uses .templ files
# (templates) to produce the actual configuration files, maintaining the
# ability to manually edit these files for lines not managed by this component.
# .templ files can be used as documentation about what should be produced by
# this component.
#
# Configuration files are modified only if their contents need to be changed,
# not at every run of the component. In case of changes, the services depending
# on the modified files are restared.
#
# Adding support for a new configuration variable should be pretty easy.
# Basically, if this is role specific variable, you just need to define it in
# a template and use add a parsing rule that use it in the %xxx_config_rules
# for the configuration file. If this is a global variable, you also need to
# load it from the configuration file as this is done for other configuration
# variables (at the beginning of Configure()). Look at the comments before
# %xxx_roles definitions to know about the parsing rules format.
#
# An effort has been made to document the code. Be sure to understand it before
# modifying.
#
# In case of problems, use --debug option of ncm-ncd. This will produce a lot
# of debugging information. 3 debugging levels are available (1, 2, 3).
#
#######################################################################

package NCM::Component::dpmlfc;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element;

use File::Path;
use File::Copy;
use File::Compare;
use File::Basename;
use File::stat;

use LC::File qw(file_contents);
use LC::Check;
use LC::Process;

use Encode qw(encode_utf8);

local(*DTA);

use Net::Domain qw(hostname hostfqdn hostdomain);


# Define paths for convenience. 
my $base = "/software/components/dpmlfc";
my $dm_install_dir_default = "/opt/lcg";
my $xroot_options_base = $base."/options/dpm/xroot";

my $dpm_def_host;

# Entry DEFAULT is used for any role that has not an explicit entry
my %config_template_ext = ('DEFAULT', '.templ',
                           'xroot', '.example',
                          );

my $config_bck_ext = ".old";    # Replaced version extension
#my $config_prod_ext = ".new";    # For testing purpose only
my $config_prod_ext = "";    # For testing purpose only


# Constants use to format lines in configuration files
my $line_format_param = 1;
my $line_format_envvar = 2;
my $line_format_trust = 3;
my $line_format_def = $line_format_param;


# dpm and lfc MUST be the first element in their respective @xxx_roles array to 
# correctly apply defaults
# Role names used here must be the same as key in other hashes.
my @dpm_roles = (
     "dpm",
     "dpns",
     "gsiftp",
     "rfio",
     "srmv1",
     "srmv2",
     "srmv22",
     "xroot",
    );
my @lfc_roles = (
     "lfc",
     "lfc-dli"
    );


# Following hash define the maximum supported servers for each type of servers
# Can be updated if redundancy is added for certain server types
my %dpm_comp_max_servers = (
          "dpm" => 1,
          "dpns" => 1,
          "gsiftp" => 999,
          "rfio" => 999,
          "srmv1" => 1,
          "srmv2" => 1,
          "srmv22" => 1,
          "xroot" => 999,
         );

my %lfc_comp_max_servers = (
          "lfc" => 1,
          "lfc-dli" => 1,
         );


# Following hashes define parsing rules to build a configuration (from a template
# or a new one). Hash key is the line keyword in configuration file and 
# hash value is the parsing rule for the keyword value. Parsing rule format is :
#       [role_condition->]option_name:option_role[,option_role,...];line_fmt
# 'role_condition' is a role that must be present on the local machine for the
# rule to be applied.
# 'option_name' is the name of an option that will be retrieved from the configuration
# 'option_role' is the role the option is attached to (for example 'host:dpns'
# means 'host' option of 'dpns' role. 'GLOBAL' is a special value for 'option_role'
# indicating that the option is global option and not a role specific option.
# 'line_fmt' indicate the line format for the parameter : 3 formats are 
# supported :
#  - envvar : a sh shell environment variable definition (export VAR=val)
#  - param : a sh shell variable definition (VAR=val)
#  - trust : a 'keyword value' line, as used by /etc/shift.conf
# Line format has an impact on hosts list if there is one. For trust format,
# each host in the local domain is inserted with its FQDN and local host is removed. 
#
# If there are several servers for a role the option value from all the servers# is used for 'host' option, and only the server corresponding to current host
# for other options.
my $dpm_config_file = "/etc/sysconfig/dpm";
my %dpm_config_rules = (
      "DPNS_HOST" => "host:dpns;$line_format_envvar",
      "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;$line_format_param",
      "DPMDAEMONLOGFILE" => "logfile:dpm;$line_format_param",
      "DPMUSER" => "user:GLOBAL;$line_format_param",
      "DPMGROUP" => "group:GLOBAL;$line_format_param",
      "DPM_PORT" => "port:dpm;$line_format_envvar",
      "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
      "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
      "LD_ASSUME_KERNEL" =>"assumekernel:dpm;$line_format_envvar",
           );

my $dpns_config_file = "/etc/sysconfig/dpnsdaemon";
my %dpns_config_rules = (
       "DPNSDAEMONLOGFILE" => "logfile:dpns;$line_format_param",
       "DPMUSER" => "user:GLOBAL;$line_format_param",
       "DPMGROUP" => "group:GLOBAL;$line_format_param",
       "DPNS_PORT" => "port:dpns;$line_format_envvar",
       "NSCONFIGFILE" => "dbconfigfile:GLOBAL;$line_format_param",
       "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
       "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
       "LD_ASSUME_KERNEL" =>"assumekernel:dpns;$line_format_envvar",
      );

my $gsiftp_config_file = "/etc/sysconfig/dpm-gsiftp";
my %gsiftp_config_rules = (
         "DPM_HOST" => "host:dpm;$line_format_envvar",
         "DPNS_HOST" => "host:dpns;$line_format_param",
         "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
         "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
        );

my $rfio_config_file = "/etc/sysconfig/rfiod";
my %rfio_config_rules = (
       "DPNS_HOST" => "host:dpns;$line_format_envvar",
       "RFIOLOGFILE" => "logfile:rfio;$line_format_param",
       "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
       "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
       );

my $srmv1_config_file = "/etc/sysconfig/srmv1";
my %srmv1_config_rules = (
        "DPM_HOST" => "host:dpm;$line_format_envvar",
        "DPNS_HOST" => "host:dpns;$line_format_envvar",
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;$line_format_param",
        "SRMV1CONFIGFILE" => "configfile:srmv1;$line_format_param",
        "SRMV1DAEMONLOGFILE" => "logfile:srmv1;$line_format_param",
        "DPMUSER" => "user:GLOBAL;$line_format_param",
        "DPMGROUP" => "group:GLOBAL;$line_format_param",
        "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
        "SRMV1_PORT" => "port:srmv1;$line_format_envvar",
        "LD_ASSUME_KERNEL" =>"assumekernel:srmv1;$line_format_envvar",
       );

my $srmv2_config_file = "/etc/sysconfig/srmv2";
my %srmv2_config_rules = (
        "DPM_HOST" => "host:dpm;$line_format_envvar",
        "DPNS_HOST" => "host:dpns;$line_format_envvar",
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;$line_format_param",
        "SRMV2DAEMONLOGFILE" => "logfile:srmv2;$line_format_param",
        "DPMUSER" => "user:GLOBAL;$line_format_param",
        "DPMGROUP" => "group:GLOBAL;$line_format_param",
        "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
        "SRMV2_PORT" => "port:srmv2;$line_format_envvar",
        "LD_ASSUME_KERNEL" =>"assumekernel:srmv2;$line_format_envvar",
       );

my $srmv22_config_file = "/etc/sysconfig/srmv2.2";
my %srmv22_config_rules = (
        "DPM_HOST" => "host:dpm;$line_format_envvar",
        "DPNS_HOST" => "host:dpns;$line_format_envvar",
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;$line_format_param",
        "SRMV22DAEMONLOGFILE" => "logfile:srmv22;$line_format_param",
        "DPMUSER" => "user:GLOBAL;$line_format_param",
        "DPMGROUP" => "group:GLOBAL;$line_format_param",
        "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
        "SRMV2_2_PORT" => "port:srmv22;$line_format_envvar",
        "LD_ASSUME_KERNEL" =>"assumekernel:srmv22;$line_format_envvar",
       );

my $xroot_config_file = "/etc/sysconfig/dpm-xrd";
my %xroot_config_rules = (
        "DPM_HOST" => "host:dpm;$line_format_envvar",
        "DPNS_HOST" => "host:dpns;$line_format_envvar",
        "MANAGERHOST", => "host:dpm;$line_format_envvar",
        "MONALISAHOST", => "xrootMonALISAHost:GLOBAL;$line_format_envvar",
        "XRDCONFIG", => "xrootConfig:GLOBAL;$line_format_envvar",
        "XRDOFS" => "xrootOfsPlugin:GLOBAL;$line_format_param",
        "XRDLOCATION" => "installDir:GLOBAL;$line_format_param",
        "XRDLOGDIR" => "logfile:xroot;$line_format_param",
        "XRDPORT" => "port:xroot;$line_format_envvar",
        "XRDUSER" => "user:GLOBAL;$line_format_param",
       );

my $trust_roles = "dpm,dpns,rfio,gsiftp";
my $trust_config_file = "/etc/shift.conf";
my %trust_config_rules = (
        "DPM PROTOCOLS" => "accessProtocols:GLOBAL;$line_format_trust",
        "DPM TRUST" => "dpm->host:dpns,xroot;$line_format_trust",
        "DPNS TRUST" => "dpns->host:dpm,srmv1,srmv2,srm22,rfio;$line_format_trust",
        "RFIOD TRUST" => "rfio->host:dpm,rfio;$line_format_trust",
        "RFIOD WTRUST" => "rfio->host:dpm,rfio;$line_format_trust",
        "RFIOD RTRUST" => "rfio->host:dpm,rfio;$line_format_trust",
        "RFIOD XTRUST" => "rfio->host:dpm,rfio;$line_format_trust",
        "RFIOD FTRUST" => "rfio->host:dpm,rfio;$line_format_trust",
        "RFIO DAEMONV3_WRMT 1" => ";$line_format_trust",
       );

my $lfc_config_file = "/etc/sysconfig/lfcdaemon";
my %lfc_config_rules = (
      "LFCDAEMONLOGFILE" => "logfile:lfc",
      "NSCONFIGFILE" => "dbconfigfile:GLOBAL;$line_format_param",
      "LFCUSER" => "user:GLOBAL;$line_format_param",
      "LFCGROUP" => "group:GLOBAL;$line_format_param",
      "LFC_PORT" => "port:lfc;$line_format_envvar",
      "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
      "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
           );

my $lfcdli_config_file = "/etc/sysconfig/lfc-dli";
my %lfcdli_config_rules = (
         "LFC_HOST" => "host:lfc",
         "DLIDAEMONLOGFILE" => "logfile:lfc-dli",
         "DLI_PORT" => "port:lfc-dli;$line_format_envvar",
         "LFCUSER" => "user:GLOBAL;$line_format_param",
         "LFCGROUP" => "group:GLOBAL;$line_format_param",
         "GRIDMAP" => "gridmapfile:GLOBAL;$line_format_param",
         "GRIDMAPDIR" => "gridmapdir:GLOBAL;$line_format_param",
        );

my %config_files = (
        "dpm" => \$dpm_config_file,
        "dpns" => \$dpns_config_file,
        "gsiftp" => \$gsiftp_config_file,
        "rfio" => \$rfio_config_file,
        "srmv1" => \$srmv1_config_file,
        "srmv2" => \$srmv2_config_file,
        "srmv22" => \$srmv22_config_file,
        "trusts" => \$trust_config_file,
        "xroot" => \$xroot_config_file,
        "lfc" => \$lfc_config_file,
        "lfc-dli" => \$lfcdli_config_file,
       );

my %config_rules = (
        "dpm" => \%dpm_config_rules,
        "dpns" => \%dpns_config_rules,
        "gsiftp" => \%gsiftp_config_rules,
        "rfio" => \%rfio_config_rules,
        "srmv1" => \%srmv1_config_rules,
        "srmv2" => \%srmv2_config_rules,
        "srmv22" => \%srmv22_config_rules,
        "xroot" => \%xroot_config_rules,
        "trusts" => \%trust_config_rules,
        "lfc" => \%lfc_config_rules,
        "lfc-dli" => \%lfcdli_config_rules,
       );
       

# Define services using each role/configuration file (if any), with each service
# separated by a comma. Services will be restarted once even if they have
# multiple dependencies.
# If service list is prefixed by 'role:', list is a name of role that is
# present in this list (take care not to create a loop).
# Service will be restarted if configuration changes.
my %services = (
    "dpm" => "dpm",
    "dpns" => "dpnsdaemon",
    "gsiftp" => "dpm-gsiftp",
    "rfio" => "rfiod",
    "srmv1" => "srmv1",
    "srmv2" => "srmv2",
    "srmv22" => "srmv2.2",
    "xroot" => "",    # will be defined by xrootSpecificActions() according to node type
    "lfc" => "lfcdaemon",
    "lfc-dli" => "lfc-dli",
    "trusts" => "role:dpm,dpns,gsiftp,rfio,xroot",
         );


# Define DB initialization script for each product (DPM / LFC)
my %mysql_init_scripts = (
           "DPM" => "/opt/lcg/yaim/functions/config_DPM_mysql",
           "LFC" => "/opt/lcg/yaim/functions/config_lfc_mysql_server",
          );
my %oracle_init_scripts = (
           "DPM" => "/opt/lcg/yaim/functions/config_DPM_oracle",
           "LFC" => "/opt/lcg/yaim/functions/config_lfc_oracle_server",
          );

# Define nameserver role in each product
my %nameserver_role = (
                       "DPM", "dpns",
                       "LFC", "lfc",
                      );

# Define roles needed access to database
my %db_roles = (
    "DPM" => "dpm,dpns",
    "LFC" => "lfc",
         );

# Gives Db name associate with one role and script to use to create 
# the database associated with a role, if needed.
# DPNS and LFC use the same database but not the same script name to create it
my %db_roles_dbs = (
      "dpm" => "dpm_db",
      "dpns" => "cns_db",
      "lfc" => "cns_db",
       );

my %mysql_db_scripts = (
      "dpm" => "/opt/lcg/share/DPM/create_dpm_tables_mysql.sql",
      "dpns" => "/opt/lcg/share/DPM/create_dpns_tables_mysql.sql",
      "lfc" => "/opt/lcg/share/LFC/create_lfc_tables_mysql.sql",
           );

# Define file where is stored DB connection information
my %db_conn_config = (
          "DPM" => "/opt/lcg/etc/DPMCONFIG",
          "LFC" => "/opt/lcg/etc/NSCONFIG",
         );
my %db_conn_config_mode = (
          "DPM" => "600",
          "LFC" => "600",
         );

my %db_servers;

# Define default values for some global options
my $db_type_def = "mysql";

my %users_def = (
        "DPM" => "dpmmgr",
        "LFC" => "lfcmgr",
       );

# Security related defaults
my $grid_security_dir = "/etc/grid-security";
my $gridmapdir_def = $grid_security_dir."/gridmapdir";
my $hostkey = "hostkey.pem";
my $hostcert = "hostcert.pem";
my %nonroot_roles = (
         "DPM" => "dpm,dpns,srmv1,srmv2,srmv22",
         "LFC" => "lfc,lfc-dli",
        );


# GIP user configuration path
my $gip_user_path = "/software/components/gip2/user";


my @products = ("DPM", "LFC");

my $this_host_name;
my $this_host_domain;
my $this_host_full;

# Global variables to store component configuration
my $dpmlfc_config;
my $dpmlfc_global_options;
my $dpmlfc_db_options;

my $hosts_roles;

# Global context variables containing used by functions
my $config;  # reference to configuration passed to Configure()
my $dm_install_dir;
my $dm_bin_dir;

# xroot related global variables
my $xrootd_config_dir;
my %xrootd_daemon_prefix = ('head' => 'dpm-manager-',
                            'disk' => 'dpm-',
                           );
# xrootd_services is used to track association between a daemon name
# (the key) and its associatated service name.
# Because the daemon/service name of Cluster Management Service changed from olb to cms,
# the appropriate CMS entry will be added to xrootd_services based on configuration property
# 'cmsDaemon' (used as a selector in xrootd_cms_services).
my %xrootd_services = ('xrootd' => 'xrd',
                      );
my %xrootd_cms_services = ('olbd' => 'olb',
                           'cmsd' => 'cms',
                          );

##########################################################################
sub Configure($$@) {
##########################################################################
    
  (my $self, $config) = @_;
  
  $this_host_name = hostname();
  $this_host_domain = hostdomain();
  $this_host_full = join ".", $this_host_name, $this_host_domain;

  # Process separatly DPM and LFC configuration
  
  my $comp_max_servers;
  for my $product (@products) {

    # Establish context for other functions
    $self->defineCurrentProduct($product);

    $self->loadGlobalOption("installDir");
    $dm_install_dir = $self->getGlobalOption("installDir");
    unless ( defined($dm_install_dir) ) {
      $dm_install_dir = $dm_install_dir_default;
    }
    $self->setGlobalOption("installDir",$dm_install_dir);
    $dm_bin_dir = $dm_install_dir . "/bin";
    
    if ( $product eq "DPM" ) {
      $hosts_roles = \@dpm_roles;
      $comp_max_servers = \%dpm_comp_max_servers;

      # Some xroot-specific initializations. Useless in LFC context...
      $xrootd_config_dir = $dm_install_dir . "/etc/xrootd";
      if ( $config->elementExists($xroot_options_base."/ofsPlugin") ) {
        $self->setGlobalOption("xrootOfsPlugin",$config->getElement($xroot_options_base."/ofsPlugin")->getValue());
        $self->debug(1,"Global option 'xrootOfsPlugin' defined to ".$self->getGlobalOption("xrootOfsPlugin"));
      }
      if ( $config->elementExists($xroot_options_base."/config") ) {
        $self->setGlobalOption("xrootConfig",$config->getElement($xroot_options_base."/config")->getValue());
        $self->debug(1,"Global option 'xrootConfig' defined to ".$self->getGlobalOption("xrootConfig"));
      }
      if ( $config->elementExists($xroot_options_base."/MonALISAHost") ) {
        $self->setGlobalOption("xrootMonALISAHost",$config->getElement($xroot_options_base."/MonALISAHost")->getValue());
        $self->debug(1,"Global option 'xrootMonALISAHost' defined to ".$self->getGlobalOption("xrootMonALISAHost"));
      }
      
    } else {
      $hosts_roles = \@lfc_roles;
      $comp_max_servers = \%lfc_comp_max_servers;
    }


    # Retrieve some general options
    # Don't define 'user' global option with a default value to keep it
    # undefined during rules processing

    $self->loadGlobalOption("user");
    $self->loadGlobalOption("group");
    $self->loadGlobalOption("gridmapfile");
    $self->loadGlobalOption("gridmapdir");
    $self->loadGlobalOption("accessProtocols");
    $self->loadGlobalOption("controlProtocols");


    # Define with product default value if not specified
    my $db_options_base = $base."/options/".lc($product)."/db/";
    if ( $config->elementExists($db_options_base."configfile") ) {
      $self->setGlobalOption("dbconfigfile",$config->getElement($db_options_base."configfile")->getValue());
      $self->debug(1,"Global option 'dbconfigfile' defined to ".$self->getGlobalOption("dbconfigfile"));
    } else {
      $self->setGlobalOption("dbconfigfile",$db_conn_config{$product});
      $self->debug(1,"Global option 'dbconfigfile' set to default : ".$self->getGlobalOption("dbconfigfile"));
    }
    if ( $config->elementExists($db_options_base."configmode") ) {
      $self->setGlobalOption("dbconfigmode",$config->getElement($db_options_base."configmode")->getValue());
      $self->debug(1,"Global option 'dbconfigmode' defined to ".$self->getGlobalOption("dbconfigmode"));
    } else {
      $self->setGlobalOption("dbconfigmode",$db_conn_config_mode{$product});
      $self->debug(1,"Global option 'dbconfigmode' set to default : ".$self->getGlobalOption("dbconfigmode"));
    }


    # At least $base/dpm or $base/lfc must exist

    for my $role (@{$hosts_roles}) {
      my $comp_base = "$base/$role";
      if ($config->elementExists("$comp_base")) {
        my @servers = $config->getElement("$comp_base")->getList();
        if ( @servers <= ${$comp_max_servers}{$role} ) {
          my $def_host;
          for my $server (@servers) {
            my %server_config = $server->getHash();
            my $role_host;
            if (exists($server_config{host})) {
              $role_host = $server_config{host}->getValue();
              if ( ($role eq "dpm") || ($role eq "lfc") ) {
                if ( $role eq "lfc" ){
                  if ( $self->hostHasRoles("dpns") ) {
                    $self->error("LFC server and DPNS server cannot be run on the same node. Skipping LFC configuration.");
                    return 0;
                  }
                }
                $def_host = $role_host;
              }
            } else {
              if ( ($role eq "dpm") || ($role eq "lfc") ) {
                $self->error("Error : No $product host defined.");
                return 1;
              } else {
                $role_host = $def_host;
              }
            }
            
            $self->addHostInRole($role,$role_host,\%server_config);
          }
        } else {
          $self->error("Too many ".uc($role)." servers (maximum=${$comp_max_servers}{$role})");
          return 0;
        }
      }
    }

    # Update configuration files for every configured role
    for my $role (@{$hosts_roles}) {
      if ( $self->hostHasRoles($role) ) {
        $self->info("Checking configuration for ".$role);
        # Do it before standard config as it defines some xroot parameters
        # according to xroot node type.
        if ( $role eq 'xroot' ) {
          $self->xrootSpecificConfig();
        }
        $self->updateConfigFile($role);
        for my $service ($self->getRoleServices($role)) {
          $self->enableService($service);
        }
      }
    }

    if ( $product eq "DPM" ) {
      $self->updateConfigFile("trusts") if $self->hostHasRoles($trust_roles);
    }

    # Do necessary DB initializations (only if current host has one role needing
    # DB access
    if ( $self->hostHasRoles($db_roles{$product}) ) {
      $self->info("Checking database configuration...");
      my $status = $self->initDb();
      # Negative status means success with changes requiring services restart
      if ( $status < 0 ) {
        for my $role_to_restart ($db_roles{$product}) {
          $self->serviceRestartNeeded($role_to_restart);
        }
      }
    }


    # Check permissions on grid-security directories if some daemons not running
    # as root are configured on the local machine.
    # These changes don't require a service restart.
    # Running both LFC and DPM related non root daemons on the same machine
    # if they don't use the same group may lead to configuration conflict
    # on gridmapdir permissions
    my @roles_nonroot = split /\s*,\s*/, $nonroot_roles{$product};
    for my $role (@roles_nonroot) {
      if ( $self->hostHasRoles($role) ) {
        $self->checkSecurity();
        last;    # Do only once for all the roles
      }
    }

  }

  # Restart services that need to be (DPM/LFC services are stateless).
  # Don't signal error as it has already been signaled by restartServices().
  if ( $self->restartServices() ) {
    return(1);
  }


  # If product is DPM and current node is DPNS server or if product is LFC and
  # this node runs lfc daemon, do namespace configuration for VOs
  my $vos_base = $base.'/vos';
  for my $product (@products) {
    $self->defineCurrentProduct($product);
    if ( $self->hostHasRoles($nameserver_role{$product}) ) {
      $self->info("Checking namespace configuration for supported VOs...");
      $self->NSRootConfig();
      if (  $config->elementExists($vos_base) ) {
        my $vos_config = $config->getElement($vos_base);
        my $vos = $vos_config->getTree();
        for my $vo (sort(keys(%$vos))) {
          # A VO may be present without any specific setting
          my %vo_args;
          if ( ref($vos->{$vo}) eq "HASH" ) {
            %vo_args = %{$vos->{$vo}};
          }
          $self->NSConfigureVO($vo,%vo_args);
        }
      }
    }
  }


  # If the current node is a DPM server (running dpm daemon) and pool configuration
  # is present in the profile, configure pools.
  $self->defineCurrentProduct("DPM");
  if ( $self->hostHasRoles('dpm') ) {
    my $pool_base = $base.'/pools';
    if ( $config->elementExists($pool_base) ) {
      my $pools_config = $config->getElement($pool_base);
      my $pools = $pools_config->getTree();
      for my $pool (sort(keys(%$pools))) {
        my $pool_args = %{$pools->{$pool}};
        $self->DPMConfigurePool($pool,%{$pool_args});
      }
    }
  }

  return 0;
}


# Function to configure DPM pools
# Returns 0 if the pool already exists or has been configured successfully, else error code of 
# the failed command.
# No attempt is made to modify an existing pool.
sub DPMConfigurePool () {
  my $function_name = "DPMConfigurePool";
  my $self = shift;
  my $status = 0;
  my $pool_name;
  if ( @_ > 0 ) {
    $pool_name = shift;
  } else {
    $self->error("$function_name: pool name argument missing.");
    return (1);
  }
  my %pool_args;
  if ( @_ > 0 ) {
    %pool_args = shift;
  } else {
    $self->error("$function_name: pool properties argument missing.");
    return (1);
  }
    
  my $product = $self->getCurrentProduct();

  $self->info('Pool configuration not yet implemented');
  
  return($status);
}

# Function to check if a directory already exists in namespace
# Returns 0 if the directory already exists, -1 if not, error code
# if namespace command returned another error.

sub NSCheckDir () {
  my $function_name = "NSCheckDir";
  my $self = shift;
  my $directory;
  if ( @_ > 0 ) {
    $directory = shift;
  } else {
    $self->error("$function_name: directory argument missing.");
    return (1);
  }
  
  my $product = $self->getCurrentProduct();

  my $cmd;
  if ( $product eq 'DPM' ) {
    $ENV{DPNS_HOST} = $this_host_full;
    $cmd = $dm_bin_dir.'/dpns-ls';
  }else {
    $ENV{LFC_HOST} = $this_host_full;
    $cmd = $dm_bin_dir.'/lfc-ls';
  }
  $cmd .= ' '.$directory;

  $self->debug(1,"$function_name: checking if directory $directory exists in $product namespace");

  my $errormsg='';
  my $status = $self->execCmd($cmd, \$errormsg);
  if ( $status ) {
    $self->debug(1,"$function_name: directory $directory not found ($cmd status=$status, error=$errormsg)");
  } else {
    $self->debug(1,"$function_name: directory $directory found");
  }
  
  return($status);
}

# Function to configure namespace root (/dpm/domain/home for DPM, /grid for LFC).
# Returns 0 if already configured or if configuration has been done successfully.
# Root is considered already configured if it exists (permission/ACL not checked).

sub NSRootConfig () {
  my $function_name = "NSRootConfig";
  my $self = shift;
  my $status = 0;
  
  my $product = $self->getCurrentProduct();

  my $root = $self->NSGetRoot();

  $self->debug(1,"$function_name: checking NS root ($root) configuration for $product");

  # Check if root already exists.
  # Do it recursively starting from DPM root up to top level parent.
  # First identify the first missing level and then create missing levels.

  # root_toks[0] is empty as root begins by /  
  my @root_toks = split /\//, $root;
  my $ns_root_ok = 1;
  my $tok_ok;
  for ($tok_ok=@root_toks-1; $tok_ok>0; $tok_ok--) {
    my $path;
    for (my $j=1; $j<=$tok_ok; $j++) {
      $path .= '/'.$root_toks[$j];
    }
    $self->debug(2,"$function_name: checking $path");
    if ( $self->NSCheckDir($path) ) {
      $self->debug(1,"$function_name: $path missing");
      $ns_root_ok = 0;
    } else {
      last;
    }
  }

  if ( ! $ns_root_ok ) {
    for (my $i=$tok_ok+1; $i<@root_toks; $i++) {
      my $path;
      for (my $j=1; $j<=$i; $j++) {
        $path .= '/'.$root_toks[$j];
      }
      $status = $self->execNSCmd("mkdir $path");
      if ( $status ) {
        $self->error("Error creating $path");
        return(2);
      }
      $status = $self->execNSCmd("chmod 775 $path");
      if ( $status ) {
        $self->error("Error defining $path permissions");
        return(2);
      }
      $status = $self->execNSCmd("setacl -m d:u::7,d:g::7,d:o:5 $path");
      if ( $status ) {
        $self->error("Error defining $path ACL");
        return(2);
      }
    }
    $self->info("Namespace root ($root) for $product initialized");
  }
    
  return($status);
}


# Function to configure namespace for a VO. Namespace root must have been configured
# before (NSRootConfig()).
# Returns 0 if already configured or if configuration has been done successfully.
# Root is considered already configured if it exists (permission/ACL not checked).

sub NSConfigureVO () {
  my $function_name = "NSConfigureVO";
  my $self = shift;
  my $status = 0;
  my $vo_name;
  if ( @_ > 0 ) {
    $vo_name = shift;
  } else {
    $self->error("$function_name: VO name argument missing.");
    return (1);
  }
  my %vo_args;
  if ( @_ > 0 ) {
    %vo_args = shift;
  }
    
  my $product = $self->getCurrentProduct();

  my $vo_home = $self->NSGetRoot().'/'.$vo_name;

  $self->debug(1,"$function_name: checking VO $vo_name NS configuration ($vo_home) for $product");

  # Check if VO home already exists. Create and configure it if not.

  if ( $self->NSCheckDir($vo_home) ) {
    $self->debug(1,"$function_name: $vo_home missing");

    my $gid_option = '';
    if ( defined($vo_args{gid}) ) {
      $gid_option = '--gid '.$vo_args{gid};
    }
    $status = $self->execNSCmd("entergrpmap --group $vo_name $gid_option");
    if ( $status ) {
      $self->debug(1,"Error creating virtual GID for VO $vo_name : probably already exists.");
    }    
    $status = $self->execNSCmd("mkdir $vo_home");
    if ( $status ) {
      $self->error("Error creating $vo_home");
      return(2);
    }
    $status = $self->execNSCmd("chown root:$vo_name $vo_home");
    if ( $status ) {
      $self->error("Error setting owner for $vo_home");
      return(2);
    }
    $status = $self->execNSCmd("chmod 775 $vo_home");
    if ( $status ) {
      $self->error("Error defining $vo_home permissions");
      return(2);
    }
    $status = $self->execNSCmd("setacl -m d:u::7,d:g::7,d:o:5 $vo_home");
    if ( $status ) {
      $self->error("Error defining $vo_home ACL");
      return(2);
    }
    $self->info("VO $vo_name namespace ($vo_home) for $product initialized");
  }
    
  return($status);
}


# Function returning the namespace root according to the currently selected product
sub NSGetRoot () {
  my $function_name = "NSGetRoot";
  my $self = shift;
  
  my $product = $self->getCurrentProduct();

  $self->debug(2,"$function_name: returning namespace root for $product");

  my $root;
  if ( $product eq 'DPM' ) {
    $root = '/dpm/'.$this_host_domain.'/home';
  }else {
    $root = '/grid';
  }
 
  return($root);
}


# Function to execute a nameserver command.
# Returns command status code.

sub execNSCmd () {
  my $function_name = "execNSCmd";
  my $self = shift;
  my $ns_cmd;
  if ( @_ > 0 ) {
    $ns_cmd = shift;
  } else {
    $self->error("$function_name: command argument missing.");
    return (1);
  }
  
  my $product = $self->getCurrentProduct();

  my $cmd = $dm_bin_dir;
  if ( $product eq 'DPM' ) {
    $ENV{DPNS_HOST} = $this_host_full;
    $cmd .= '/dpns-';
  }else {
    $ENV{LFC_HOST} = $this_host_full;
    $cmd .= '/lfc-';
  }
  $cmd .= $ns_cmd;

  $self->debug(1,"$function_name: execution command '$cmd'");

  my $errormsg='';
  my $status = $self->execCmd($cmd, \$errormsg);
  if ( $status ) {
    $self->debug(1,"$function_name: error returned by executed command ($cmd status=$status, error=$errormsg)")
  } else {
    $self->debug(2,"$function_name: command completed successfully")    
  }
  
  return($status);
}


# Function to execute an arbitrary command.
# Command must be a full path, its existence is checked  before execution and stderr is returned in
# reference provided as second argument, if present. stdout is discarded.
# Returns command status code.

sub execCmd () {
  my $function_name = "execCmd";
  my $self = shift;
  my $cmd;
  if ( @_ > 0 ) {
    $cmd = shift;
  } else {
    $self->error("$function_name: command argument missing.");
    return (1);
  }
  my $error;
  if ( @_ > 0 ) {
    $error = shift;
  }
  
  $self->debug(1,"$function_name: executing command '$cmd'");

  my ($verb, @args) = split /\s+/, $cmd;
  if ( ! -x $verb ) {
    $self->error("Command $verb not found");
    return(2);
  }
  
  my @errormsg = qx%$cmd 2>&1%;
  my $status = $? >> 8;

  if ( $status ) {
    $self->debug(1,"$function_name: commad $verb failed (status=$status, error=".join("",@errormsg).")");
    if ( defined($error) ) {
      $$error = join("",@errormsg);
    }
  } else {
    $self->debug(2,"$function_name: command $verb completed successfully")    
  }
  
  return($status);
}


# Function to define currently processed product
# Must be called before other function that need a product context
#
# Arguments :
#  product : DPM or LFC
sub defineCurrentProduct() {
  my $function_name = "defineCurrentProduct";
  my $self = shift;
  
  my $product = shift;
  unless ( $product ) {
    $self->error("$function_name: 'product' argument missing");
    return 0;
  }

  $self->{CURRENTPRODUCT} = $product;
  $self->debug(1,"$function_name: product context defined to $self->{CURRENTPRODUCT}");
}


# Function to get currently processed product
#
# Arguments :
#  none
sub getCurrentProduct() {
  my $function_name = "getCurrentProduct";
  my $self = shift;
  
  $self->debug(2,"$function_name: returning product ($self->{CURRENTPRODUCT})");
  return $self->{CURRENTPRODUCT};
}


# Function returning the host FQDN.
# localhost is handled as a special case where no domain should be added.
#
# Arguments :
#  host : a host name
sub hostFQDN () {
  my $function_name = "hostFQDN";
  my $self = shift;
  
  my $host = shift;
  unless ( $host ) {
    $self->error("$function_name: 'host' argument missing");
    return 0;
  }

  (my $host_name, my $domain) = split /\./, $host, 2;

  unless ( $domain || ($host eq "localhost") ) {
    $host = "$host.$this_host_domain";
  }

  return $host;
}


# Function to check permissions of GRIDMAPDIR and verify that host key/cert
# are present in the right place to be used by DPM or LFC
#
# Arguments :
sub checkSecurity () {
  my $function_name = "checkSecurity";
  my $self = shift;

  my $product = $self->getCurrentProduct();

  $self->info("Checking host certificate and key configuration for $product");

  my $daemon_group = $self->getDaemonGroup();
  my $daemon_user = $self->getDaemonUser();
  my $changes;

  # GRIDMAPDIR must be writable by group used by product daemons
  my $gridmapdir = $self->getGlobalOption("gridmapdir");
  unless ( $gridmapdir ) {
    $gridmapdir = $gridmapdir_def;
  }
  if ( -d $gridmapdir ) {
    $self->debug(1,"$function_name: Checking permission on $gridmapdir");
    $changes = LC::Check::status($gridmapdir,
         group => $daemon_group,
         mode => 01774
        );
    unless (defined($changes)) {
      $self->error("error setting $gridmapdir for $product");
    }
  } else {
      $self->error("$gridmapdir not found or not a directory. Check gridmap stuff is installed and properly configured");
  }

  # Put a private copy of hostcert/hostkey owned by product daemons account
  # in subdirectory of /etc/grid-security with the same name as the daemon
  # userid
  my $daemon_security_dir = $grid_security_dir."/".$daemon_user;
  my $host_hostkey = $grid_security_dir."/".$hostkey;
  my $host_hostcert = $grid_security_dir."/".$hostcert;
  my $do_keycert_config = 1;

  $self->debug(1,"$function_name: Checking existence of host key and certifiate");
  unless ( -f $host_hostkey ) {
    $self->error("Host key ($host_hostkey) not found. Check your configuration");
    $do_keycert_config = 0;
  }
  unless ( -f $host_hostcert ) {
    $self->error("Host certificate ($host_hostcert) not found. Check your configuration");
    $do_keycert_config = 0;
  }

  if ( $do_keycert_config ) {
    $self->debug(1,"$function_name: Checking existence and permission of $daemon_security_dir");
    $changes = LC::Check::directory($daemon_security_dir
         );
    unless (defined($changes)) {
      $self->error("error creating $daemon_security_dir");
      return 1;
    }
    $changes = LC::Check::status($daemon_security_dir,
         mode => 0755,
         owner => $daemon_user,
         group => $daemon_group
        );
    unless (defined($changes)) {
      $self->error("error setting security on $daemon_security_dir");
      return 1;
    }

    $self->debug(1,"$function_name: Copying host certificate ($hostcert) and key ($hostkey) to $daemon_security_dir");
    my $daemon_hostkey .= $daemon_security_dir."/".lc($product)."key.pem";
    $changes = LC::Check::file($daemon_hostkey,
             source => $host_hostkey,
             owner => $daemon_user,
             group => $daemon_group,
             mode => 0400
            );
    unless (defined($changes)) {
      $self->error("error creating $hostkey copy for $product");
    }
    my $daemon_hostcert .= $daemon_security_dir."/".lc($product)."cert.pem";
    $changes = LC::Check::file($daemon_hostcert,
             source => $host_hostcert,
             owner => $daemon_user,
             group => $daemon_group,
             mode => 0644
            );
    unless (defined($changes)) {
      $self->error("error creating $hostcert copy for $product");
    }
  }

}


# Function to store global options value
#
# Arguments :
#  option : option name
#  value : option value
sub setGlobalOption () {
  my $function_name = "setGlobalOption";
  my $self = shift;

  my $option = shift;
  unless ( $option ) {
    $self->error("$function_name: 'option' argument missing");
    return 0;
  }
  my $value = shift;
  unless ( defined($value) ) {
    $self->error("$function_name: 'value' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();

  my $options_set = "GLOBALOPTS".$product;

  unless ( defined($self->{$options_set}) ) {
    $self->{$options_set} = {};
  }

  $self->{$options_set}->{$option} = $value;

  $self->debug(2,"$function_name: global option '$option' set to '$value' for $product");

}


# Function to retrieve a global option value
#
# Arguments :
#  option : option name
sub getGlobalOption () {
  my $function_name = "getGlobalOption";
  my $self = shift;

  my $option = shift;
  unless ( $option ) {
    $self->error("$function_name: 'option' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();

  my $options_set = "GLOBALOPTS".$product;
  if ( defined($self->{$options_set}->{$option}) ) {
    $self->debug(2,"$function_name: returning global option $option (value=$self->{$options_set}->{$option}) for $product");
  } else {
    $self->debug(2,"$function_name: global option '$option' not found for $product");
  }
  return $self->{$options_set}->{$option};

}


# Function to retrieve a global option value from configuration
# and set the corresponding attribute
# Arguments :
#  option : option name
sub loadGlobalOption () {
  my $function_name = "loadGlobalOption";
  my $self = shift;

  my $option = shift;
  unless ( $option ) {
    $self->error("$function_name: 'option' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();

  my $options_base = $base."/options/".lc($product)."/";

  if ( $config->elementExists($options_base.$option) ) {
    my $value = $config->getElement($options_base.$option)->getTree();
    $self->setGlobalOption($option,$value);
    $self->debug(2,"Global option '$option' found : ".$self->getGlobalOption($option));
  }


}


# Function to retrieve a DB option value from configuration
# Arguments :
#  option : option name
sub getDbOption () {
  my $function_name = "getDbOption";
  my $self = shift;

  my $option = shift;
  unless ( $option ) {
    $self->error("$function_name: 'option' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();

  my $options_base = $base."/options/".lc($product)."/db/";

  if ( $config->elementExists($options_base.$option) ) {
    return $config->getElement($options_base.$option)->getValue();
  } else {
      $self->debug(1,"DB option '$option' not found for product $product");
      return undef;
    }


}


# Function returning the userid used by product daemons
# Default : as specified in %users_def
#
# Arguments : 
#  none
sub getDaemonUser () {
  my $function_name = "getDaemonUser";
  my $self = shift;

  my $product = $self->getCurrentProduct();

  my $daemon_user = $self->getGlobalOption("user");
  unless ( $daemon_user ) {
    $daemon_user = $users_def{$product};
    $self->debug(1,"$function_name: daemon user set to default value ($daemon_user)");
  }
 
  return $daemon_user;
}


# Function returning the group used by product daemons
# Default : same as userid
#
# Arguments : 
#  none
sub getDaemonGroup () {
  my $function_name = "getDaemonGroup";
  my $self = shift;

  my $daemon_group = $self->getGlobalOption("group");
  unless ( $daemon_group ) {
    $daemon_group = $self->getDaemonUser();
    $self->debug(1,"$function_name: daemon group set to default value ($daemon_group)");
  }

  return $daemon_group;
}


# Function returning the server to use to manage databases.
# Returns the db server or localhost if db server is the current node
# (to maximize chance to get success on an unconfigured server)
#
# Arguments : 
#  none
sub getDbAdminServer () {
  my $function_name = "getDbAdminServer";
  my $self = shift;

  my $product = $self->getCurrentProduct();

  my $db_admin_server = $self->getGlobalOption("dbserver");
  unless ( $db_admin_server ) {
    $self->error("Database server not defined");
  }
  if ( $db_admin_server eq $this_host_full ) {
    $self->debug(2,"$function_name: database server is current host. Changing management server to localhost");
    $db_admin_server = "localhost";
  } else {
    $self->debug(2,"$function_name: database management server is $db_admin_server");
  }
  return $db_admin_server;
}


# Function to execute silently a mysql command. Host, user and password are retrived
# from context global variables. stdout and stderr are redirected to /dev/null
# Returns status code from the command (0 if success)
#
# Arguments :
#  command : mysql command to execute (anything without connexion information)
sub mysqlExecCmd () {
  my $function_name = "mysqlExecCmd";
  my $self = shift;

  my $command = shift;
  unless ( $command ) {
    $self->error("$function_name: 'command' argument missing");
    return 0;
  }

  my $db_admin_user = $self->getGlobalOption("dbadminuser");
  my $db_admin_pwd = $self->getGlobalOption("dbadminpwd");
  my $db_admin_server = $self->getDbAdminServer();

  $self->debug(2,"$function_name: executing MySQL command '$command' on $db_admin_server (user:$db_admin_user, pwd:$db_admin_pwd)");

  my $status = system("mysql -h $db_admin_server -u '$db_admin_user' --password='$db_admin_pwd' $command > /dev/null 2>&1");

  return $status
}


# Function to check and if necessary/possible change MySQL administrator password
# Returns 0 in case of success.
#
# User is added for localhost and server indicated in options.
#
# Arguments :
#  none
sub mysqlCheckAdminPwd() {
  my $function_name = "mysqlCheckAdminPwd";
  my $self = shift;

  my $product = $self->getCurrentProduct();
  my $db_admin_user = $self->getGlobalOption("dbadminuser");
  my $db_admin_pwd = $self->getGlobalOption("dbadminpwd");
  my $db_admin_pwd_old = $self->getGlobalOption("dboldadminpwd");
  my $db_admin_server = $self->getDbAdminServer();
  my $status = 1;  # Assume failure by default

  $self->debug(1,"$function_name: Checking MySQL administrator on $db_admin_server (user=$db_admin_user, pwd=$db_admin_pwd)");

  # First check if administrator account is working without password (try to use mysql dabase)
  my $admin_pwd_saved = $db_admin_pwd;
  $self->setGlobalOption("dbadminpwd", "");
  $status = $self->mysqlExecCmd("--exec 'use mysql'");
  $self->setGlobalOption("dbadminpwd", $admin_pwd_saved);
  
  if ( $status ) {  # administrator has a password set, try it
    # First check if administrator password is working (just trying to connect)
    $status = $self->mysqlExecCmd("</dev/null");
  } else {
    $self->debug(1,"$function_name: MySQL administrator ($db_admin_server) password not set on $db_admin_server");
    $status = 1;  # Force initialization of password
  }

  # If it fails, try to change it assuming a password has not yet been set
  if ( $status ) {
    $self->debug(1,"$function_name: trying to set administrator password on $db_admin_server");
    
#    # if oldpassword is set then try and use it
#    if ($db_admin_pwd_old) {
#      $admin_pwd_saved = $db_admin_pwd;
#   	  $self->setGlobalOption("dbadminpwd", "$db_admin_pwd_old");
#    }
    
    $status = system("mysqladmin -h $db_admin_server -u '$db_admin_user' password '$db_admin_pwd' > /dev/null 2>&1");
    if ( $status && ($db_admin_server ne "localhost") ) {
      $self->warn("Remote database server ($db_admin_server) : check access is allowed with full privileges from $db_admin_user on $this_host_full");
    }
#	  $self->setGlobalOption("dbadminpwd", $admin_pwd_saved);
  } else {
    $self->debug(1,"$function_name: MySQL administrator password succeeded");
  }

  return $status;
}


# Function to add a database user for the product. Usercan be retrieved from options
# or passed as arguments
# Returns 0 in case of success (user already exists with the right password
# or successful creation)
#
# Arguments (optional) :
#     User : DB user to create. Defaults to 'dbuser' global option.
#     Password : password for the user. Defaults to 'dbpwd' global option.
#     DB rights : rights to give to the user. Defaults to 'ALL'
#     Short password hash : true/false. Default : false.
sub mysqlAddUser() {
  my $function_name = "mysqlAddUser";
  my $self = shift;

  my $product = $self->getCurrentProduct();
  my $db_server = $self->getGlobalOption("dbserver");

  my $db_user;
  if ( @_ > 0 ) {
    $db_user = shift;
  } else {
    $db_user = $self->getGlobalOption("dbuser");
  }

  my $db_pwd;
  if ( @_ > 0 ) {
    $db_pwd = shift;
  } else {
    $db_pwd = $self->getGlobalOption("dbpwd");
  }

  my $db_rights;
  if ( @_ > 0 ) {
    $db_rights = shift;
  } else {
    $db_rights = 'ALL';
  }

  my $short_pwd_hash;
  if ( @_ > 0 ) {
    $short_pwd_hash = shift;
  } else {
    $short_pwd_hash = 0;
  }

  my @db_hosts = ($db_server, 'localhost');
  
  my $status = 0;
  for my $host (@db_hosts) {
    $self->debug(1,"$function_name: Adding MySQL connection account for $product ($db_user on $host)");
    $status = $self->mysqlExecCmd("--exec \"grant $db_rights on *.* to '$db_user'\@'$host' identified by '$db_pwd' with grant option\"");
    if ( $status ) {
      # Error already signaled by caller
      $self->debug(1,"Failed to add MySQL connection for $db_user on $host");
      return $status;
    }
    
    # Backward compatibility for pre-4.1 clients, like perl-DBI-1.32
    if ( $short_pwd_hash ) {
      $self->debug(1,"$function_name: Defining password short hash for $db_user on $host)");
      $status = $self->mysqlExecCmd("--exec \"set password for '$db_user'\@'$host' = OLD_PASSWORD('$db_pwd')\"");
      if ( $status ) {
        # Error already signaled by caller
        $self->debug(1,"Failed to define password short hash for $db_user on $host");
        return $status;
      }      
    }
  }
  
  return $status;
}


# Function to add a database
# Returns 0 in case of success (database already exists with the right password
# or successful creation)
#
# Arguments :
#  database : database to create
#  script : script to create the database and tables if it doesn't exist
sub mysqlAddDb() {
  my $function_name = "mysqlAddDb";
  my $self = shift;

  my $database = shift;
  unless ( $database ) {
    $self->error("$function_name: 'database' argument missing");
    return 0;
  }
  my $script = shift;
  unless ( $script ) {
    $self->error("$function_name: 'script' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();
  my $status = 1;  # Assume failure by default

  $self->debug(1,"$function_name: checking if database $database for $product already exists");
  $status = $self->mysqlExecCmd("--exec \"use $database\"");


  if ( $status ) {
    $self->debug(1,"$function_name: creating database $database for $product");
    $status = $self->mysqlExecCmd("< $script");
  } else {
    $self->debug(1,"$function_name: database $database found");
  }

  return $status;
}

# Function to initialize DB tables and create the DB connection information
#
# Arguments : 
#  none
sub initDb () {
  my $function_name = "initDb";
  my $self = shift;

  my $product = $self->getCurrentProduct();
  $self->debug(1,"$function_name: Checking database configuration for $product");

  my $db_config_base = $base."/options/".lc($product)."/db";
  unless ( $config->elementExists("$db_config_base") ) {
    $self->warn("Cannot configure DB connection : configuration missing ($db_config_base)");
    return 1;
  }
  $db_config_base .= "/";

  my $do_db_config = 1;


  my $db_type = $self->getDbOption("type");
  unless ( $db_type ) {
    $self->info("DB type not configured : assuming $db_type_def");
    $db_type = $db_type_def;
  }

  my $daemon_user = $self->getDaemonUser();
  my $daemon_group = $self->getDaemonGroup();

  my $db_user = $self->getDbOption("user");
  unless ( $db_user ) {
    $db_user = $daemon_user;
    $self->debug(1,"$function_name: DB user default used ($db_user)");
  }
  $self->setGlobalOption("dbuser",$db_user);

  my $db_pwd = $self->getDbOption("password");
  unless ( $db_pwd ) {
    $db_pwd = $self->generatePassword();
    $self->info("DB password not configured : generating a new one.");
  }
  $self->setGlobalOption("dbpwd",$db_pwd);

  my $db_server = $self->getDbOption("server");
  unless ( $db_server ) {
    $db_server = $this_host_full;
    $self->debug(1,"$function_name: DB server not configured. Using $db_server");
  }
  $db_server = $self->hostFQDN($db_server);
  if ( exists($db_servers{$db_server}) ) {
    unless ($db_servers{$db_server} eq $product) {
      $self->error("DPM and LFC cannot run on the same server. Skipping database configuration.");
      return 1;
    }
  } else {
    $db_servers{$db_server} = $product;
  }
  $self->setGlobalOption("dbserver",$db_server);


  my $db_admin_pwd = $self->getDbOption("adminpwd");
  my $db_admin_user;
  if ( $db_admin_pwd ) {
    $self->setGlobalOption("dbadminpwd",$db_admin_pwd);
    $db_admin_user = $self->getDbOption("adminuser");
    unless ( $db_admin_user ) {
      $db_admin_user = "root";
      $self->debug(1,"$function_name: DB admin user set to default ($db_admin_user)");
    }
    $self->setGlobalOption("dbadminuser",$db_admin_user);
  } else {
    $do_db_config = 0;
    $self->warn("DB admin password not defined. Skipping database configuration for $product");
  }

  # info_user is the MySQL user used by GIP to collect DPM statistics.
  # Configure only if GIP is configured on the machine.
  my $gip_user;
  my $db_info_user;
  my $db_info_pwd;
  my $db_info_file;
  if ( $config->elementExists($gip_user_path) ) {
    $gip_user = $config->getElement($gip_user_path)->getValue();
    $db_info_user = $self->getDbOption("infoUser");
    unless ( $db_info_user ) {
      $db_info_user = "dminfo";
      $self->debug(1,"$function_name: DB info user set to default ($db_info_user)");
    }
    $self->setGlobalOption("dbinfouser",$db_info_user);
    $db_info_pwd = $self->getDbOption("infoPwd");
    if ( $db_info_pwd ) {
      $self->setGlobalOption("dbinfopwd",$db_info_pwd);
    } else {
      $db_info_pwd = $self->generatePassword();
      $self->info("DB info user's password not configured : generating a new one.");
    }
    $db_info_file= $self->getDbOption("infoFile");
    unless ( $db_info_file ) {
      $db_info_file = $product . "INFO";
      $self->info("DB info connection file not configured. Set to default ($db_info_file)");
    }
  }
  
  my $db_config_done = 1;    # Assume failure
  my $db_init_script;
  if ( $db_type eq "mysql" ) {
      $db_init_script = $mysql_init_scripts{$product};
    MYSQL : {
      if ( $do_db_config ) {
  if ( $self->mysqlCheckAdminPwd() ) {
    $self->error("Unable to use database administrator ($db_admin_user) password. Database configuration skipped");
    $db_config_done = 0;
    last MYSQL;
  }
  if ( $self->mysqlAddUser() ) {
    $self->error("Failure to add database user $db_user for $product. Database configuration skipped");
    $db_config_done = 0;
    last MYSQL;
  }
  if ( $self->mysqlAddUser($db_info_user,$db_info_pwd,'select',1) ) {
    $self->error("Failure to add database user $db_info_user for $product. Database configuration skipped");
    $db_config_done = 0;
    last MYSQL;
  }
  my $product_db_roles = $db_roles{$product};
  my @product_db_roles = split /\s*,\s*/, $product_db_roles;
  for my $role (@product_db_roles) {
    my $database = $db_roles_dbs{$role};
    next unless $database;
    my $db_creation_script = $mysql_db_scripts{$role};
    unless ( $database ) {
      $self->debug(1,"$function_name: No script to create database $database for $product. Database configuration skipped");
      $db_config_done = 0;
      last MYSQL;
    }
    $self->mysqlAddDb($database,$db_creation_script);
  }
      } else {
  $db_config_done = 0;
      }
    }
  } elsif ( $db_type eq "oracle" ) {
      $db_config_done = 0;
      $db_init_script = $oracle_init_scripts{$product};
  } else {
    $self->error("DB type '$db_type' not supported. Configure manually");
  }
  unless ( $db_config_done ) {
    $self->info("$db_type DB configuration must be done manually for $product use ($db_init_script)");
  }

  # Update DB connection configuration file for main user if content has changed
  my $config_contents = "$db_user/$db_pwd\@$db_server";
  my $changes = LC::Check::file($self->getGlobalOption("dbconfigfile").$config_prod_ext,
                                backup => $config_bck_ext,
                                contents => $config_contents,
                                owner => $daemon_user,
                                group => $daemon_group,
                                mode => oct($self->getGlobalOption("dbconfigmode"))
                               );


  # Update DB connection configuration file for information user if content has changed
  # No service needs to be restarted.
  if ( $gip_user ) {
    $config_contents = "$db_info_user/$db_info_pwd\@$db_server";
    my $info_changes = LC::Check::file($db_info_file.$config_prod_ext,
                                  backup => $config_bck_ext,
                                  contents => $config_contents,
                                  owner => $gip_user,
                                  group => $daemon_group,
                                  mode => oct($self->getGlobalOption("dbconfigmode"))
                                 );
    if ( $info_changes < 0 ) {
      $self->error("Error configuring connection file for info user. $product publication into BDII may not work.");
    }
  } else {
    $self->debug(1,"GIP no configured on this node. Skipping $product DB configuration for GIP.");
  }


  # Return a negative status in case of success with changes requiring restart
  # of dependent services
  return ( - $changes);

}


# Function returning the list of services associated with a role, if the role
# is enabled on current node. Services list is returned as an array.
# If the role is not enabled on current node or in case of error (no
# such role or role with no associated service), return an empty array.
#
# Arguments :
#  role : role the services need to be restarted
sub getRoleServices () {
  my $function_name = "getRoleServices";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 0;
  }

  $self->debug(1,"$function_name: retrieving list of services associated with role $role");

  my @services;

  my $service_list = $services{$role};
  unless ( $service_list ) {
    $self->error("$function_name: no services associated with role '$role' (internal error)");
    return @services;
  }

  # If list is a role list instead of a service list (role:...), look for actual service
  # name. No check for potential loop implemented... take care of configuration.
  # Duplicates are removed.

  (my $role_flag, my $roles) = split /:/, $service_list;
  if ( ($role_flag ne "role") && $roles ) {
    $self->error("$function_name: invalid flag ($role_flag) in list of services associated with role $role");
  }

  if ( $roles ) {
    my %enabled_services;
    my @roles = split /\s*,\s*/, $roles;
    for my $role (@roles) {
      if ( $self->hostHasRoles($role) ) {
  if ( exists($services{$role}) ) {
    my @role_services = split /\s*,\s*/, $services{$role};
    for my $service (@role_services) {
      $enabled_services{$service}="";
    }
  } else {
    $self->error("$function_name: no services associated with role '$role' (internal error)");
  }
      } else {
  $self->debug(1,"$function_name: host doesn't have role $role");
      }
    }
    @services = keys %enabled_services;
  } else {
    if ( $self->hostHasRoles($role) ) {
      @services = split /\s*,\s*/, $service_list;
    } else {
      $self->debug(1,"$function_name: host doesn't have role $role");
    }
  }

  return @services;
}


# Function to add a service in the list of services needed to be restarted.
# Services can be a comma separated list.
# Services are added to the list only if the current host has the role
# passed as argument.
# It is valid to pass a role with no associated services (nothing done).
#
# Arguments :
#  roles : roles the associated services need to be restarted (comma separated list)
sub serviceRestartNeeded () {
  my $function_name = "serviceRestartNeeded";
  my $self = shift;

  my $roles = shift;
  unless ( $roles ) {
    $self->error("$function_name: 'roles' argument missing");
    return 0;
  }

  my $list;
  unless ( $list = $self->getServiceRestartList() ) {
    $self->debug(1,"$function_name: Creating list of service needed to be restarted");
    $self->{SERVICERESTARTLIST} = {};
    $list = $self->getServiceRestartList();
  }

  my @roles = split /\s*,\s*/, $roles;
  for my $role (@roles) {
    for my $service ($self->getRoleServices($role)) {
      unless ( exists(${$list}{$service}) ) {
        $self->debug(1,"$function_name: adding '$service' to the list of service needed to be restarted");
        ${$list}{$service} = "";
      }
    }
  }

  $self->debug(2,"$function_name: restart list = '".join(" ",keys(%{$list}))."'");
}


# Return list of services needed to be restarted
sub getServiceRestartList () {
  my $function_name = "getServiceRestartList";
  my $self = shift;

  if ( defined($self->{SERVICERESTARTLIST}) ) {
    $self->debug(2,"$function_name: restart list = ".join(" ",keys(%{$self->{SERVICERESTARTLIST}})));
    return $self->{SERVICERESTARTLIST};
  } else {
    $self->debug(2,"$function_name: list doesn't exist");
    return undef
  }

}


# Enable a service to be started during system startup
#
# Arguments :
#  service : name of the service
sub enableService () {
  my $function_name = "enableService";
  my $self = shift;

  my $service = shift;
  unless ( $service ) {
    $self->error("$function_name: 'service' argument missing");
    return 0;
  }

  $self->debug(1,"$function_name: checking if service $service is enabled");

  unless ( -f "/etc/rc.d/init.d/$service" ) {
    $self->error("Startup script not found for service $service");
    return 1;
  }

  if (system("chkconfig $service > /dev/null 2>&1")) {
    # No need to do chkconfig --ad first, done by default
    $self->info("\tEnabling service $service at startup");
    if ( system("chkconfig $service on") ) {
      $self->error("Failed to enable service $service");
    }
  } else {
    $self->debug(2,"$function_name: $service already enabled");
  }
}


# Restart services needed to be restarted
# Returns 0 if all services have been restarted successfully, else
# the number of services which failed to restart.

sub restartServices () {
  my $function_name = "RestartServices";
  my $self = shift;
  my $global_status = 0;
  
  $self->debug(1,"$function_name: restarting services affected by configuration changes");

  # Need to do stop+start as dpm daemon generally doesn't restart properly with
  # 'restart'. Try to restart even if stop failed (can be just the daemon is 
  # already stopped)
  # Use system() rather than LC::Process::run because LC::Process::run doesn't
  # return start/stop status properly.
  if ( my $list = $self->getServiceRestartList() ) {
    $self->debug(1,"$function_name: list of services to restart : ".join(" ",keys(%{$list})));
    for my $service (keys %{$list}) {
      $self->info("Restarting service $service");
      if (system("service $service stop > /dev/null 2>&1")) {
        # Service can be stopped, don't consider failure to stop as an error
        $self->warn("\tFailed to stop $service");
      }
      sleep 5;    # Give time to the daemon to shut down
      my $attempt = 10;
      my $status;
      while ( $attempt && ($status = system("service $service start > /dev/null 2>&1"))) {
        $self->debug(1,"$function_name: $service startup failed (probably not shutdown yet). Retrying ($attempt attempts remaining)");
        sleep 5;
        $attempt--;
      }
      if ( $status ) {
        $global_status++;
        $self->error("\tFailed to start $service");
      } else {
        $self->info("Service $service restarted successfully");
      }
    }
  }

  return($global_status);
}


# Function returning list of roles hosts name according to the current product
#
# Arguments :
#  none
sub getRolesHostsListName () {
  my $function_name = "getRolesHostsListName";
  my $self = shift;

  my $product = $self->getCurrentProduct();

  return "ROLESHOSTSLIST".$product;
}


# Function to create a role hosts list. Created host list is returned.
# Take care of creating list of role hosts list if doesn't exist yet
# Roles hosts list is hash
#
# Arguments :
#  none
sub createRoleHostsList () {
  my $function_name = "createRoleHostsList";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();

  my $roles_hosts_list;
  unless ( $roles_hosts_list = $self->getRolesHostsList() ) {
    my $roles_hosts_list_name = $self->getRolesHostsListName();
    $self->debug(1,"$function_name: Creating roles hosts list ($roles_hosts_list_name) for product $product");
    $roles_hosts_list = $self->{$roles_hosts_list_name} = {};
  }
  
  ${$roles_hosts_list}{$role} = {};

  return ${$roles_hosts_list}{$role};
}


# Function to get roleS hosts list (list of role hosts list
# Returns reference to roleS hosts list hash
#
# Arguments :
#  none
sub getRolesHostsList () {
  my $function_name = "getRolesHostsList";
  my $self = shift;

  # Check absence of other arguments (to avoid confusion with getRoleHostsList())
  if ( @_ ) {
    $self->error("$function_name: too many arguments. May be confusion with getRoleHostList()");
    return 1;
  }

  my $roles_hosts_list_name = $self->getRolesHostsListName();
  return $self->{$roles_hosts_list_name};
}


# Function to get role hosts list (host list for one role)
# Returns reference to role hosts list hash
#
# Arguments :
#  role : role for which the host list must be returned
sub getRoleHostsList () {
  my $function_name = "getRoleHostsList";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 0;
  }

  my $roles_hosts_list = $self->getRolesHostsList();
  if ( $roles_hosts_list ) {
    return ${$roles_hosts_list}{$role};
  } else {
    return undef;
  }
}


# Function to add a host in a role hosts list.
# Roles hosts list contains is a hash with one list (hash value) per role (hash
# key).
# Each list contains for each role the list of hosts configured
# with this role. Host list is a hash, with hash key the host name and 
# hash value a reference to the configuration hash returned by getElement()
# for this host.
# For each non qualified host name, add local domain name
#
# Arguments
#       role : role for which the hosts list must be normalized
#       host : host to add (a short name is interpreted a local domain name)
#       role : configuration hash returned by getElement() for the host
sub addHostInRole () {
  my $function_name = "addHostInRole";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 0;
  }
  my $host = shift;
  unless ( $host ) {
    $self->error("$function_name: 'host' argument missing");
    return 0;
  }
  my $host_config = shift;
  unless ( $host_config ) {
    $self->error("$function_name: 'host_config' argument missing");
    return 0;
  }

  my $product = $self->getCurrentProduct();

  my $role_host = $self->hostFQDN($host);

  # If it doesn't exist yet, create a hosts list for this role
  my $role_hosts_list = $self->getRoleHostsList($role);
  unless ( $role_hosts_list ) {
    $self->debug(1,"$function_name: creating host list for product $product role ".uc($role)." (product=$product)");
    $role_hosts_list = $self->createRoleHostsList($role);
  }

  if ( ! exists(${$role_hosts_list}{$role_host}) ) {
    $self->debug(1,"Adding host $role_host to  role ".uc($role));
    ${$role_hosts_list}{$role_host} = $host_config;
  } else {
    $self->error("$role_host alreday present in list of hosts configured as a ".uc($role)." server. Using previous definition");
  }

}

# This function returns true if the current machine is listed in the hosts list
# for one of the roles passed as argument.
#
# Arguments
#       roles : comma separated roles list. 
sub hostHasRoles () {
  my $function_name = "hostHasRoles";
  my $self = shift;

  my $roles = shift;
  unless ( $roles ) {
    $self->error("$function_name: 'roles' argument missing");
    return 0;
  }

  my $role_found = 0;    # Assume host doesn't have any role
  my @roles = split /\s*,\s*/, $roles;

  for my $role (@roles) {
    my $role_hosts_list = $self->getRoleHostsList($role);
    if ( $role_hosts_list ) {
      $self->debug(2,"$function_name: checking for role $role (Hosts list=$role_hosts_list)");
    } else {
      $self->debug(2,"$function_name: no host for role $role");
    }
    next if ! exists($role_hosts_list->{$this_host_full});
    $role_found = 1;
    last;
  }
  return $role_found;
}


# This function returns a string containing hosts list for a role (sorted)
#
# Arguments
#       role : role for which the hosts list must be normalized
sub getHostsList () {
  my $function_name = "getHostsList";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 1;
  }

  my $role_hosts_list = $self->getRoleHostsList($role);

  my $hostslist="";
  for my $host (sort keys %{$role_hosts_list}) {
    (my $host_name, my $domain) = split /\./, $host, 2;
    $hostslist .= "$host ";
  }

  # Some config files are sensitive to extra spaces : suppress trailing spaces
  $hostslist =~ s/\s+$//;
  $self->debug(1,"Hosts list for role ".uc($role)." : >>$hostslist<<");
  return $hostslist;
}


# This function formats hosts list suppressing repeated hosts and replacing
# multiple spaces by one.
#
# Arguments :
#        list : list of hosts
#        line_fmt : line format (see $line_format_xxx parameters)
sub formatHostsList () {
  my $function_name = "formatHostsList";
  my $self = shift;

  my $list = shift;
  unless ( $list ) {
    $self->error("$function_name: 'list' argument missing");
    return 1;
  }
  my $list_fmt = shift;
  unless ( defined($list_fmt) ) {
    $self->error("$function_name: 'list_fmt' argument missing");
    return 1;
  }

  $self->debug(2,"$function_name: formatting host list (line fmt=$list_fmt)");

  # Duplicates may exist as result of a join. Checkt it.
  my @hosts = split /\s+/, $list;
  my %hosts;
  for my $host (@hosts) {
    unless ( exists($hosts{$host}) ) {
      $hosts{$host} = "";
    }
  }

  my $newlist="";
  for my $host (sort keys %hosts) {
    $newlist .= "$host ";
  }

  # Some config files are sensitive to extra spaces : suppress trailing spaces
  $newlist =~ s/\s+$//;
  $self->debug(1,"Formatted hosts list : >>$newlist<<");
  return $newlist;
}


# This function formats a configuration line using keyword and value,
# according to the line format requested.
#
# Arguments :
#        keyword : line keyword
#        value : keyword value (can be empty)
#        line_fmt : line format (see $line_format_xxx parameters)
sub formatConfigLine () {
  my $function_name = "formatConfigLine";
  my $self = shift;

  my $keyword = shift;
  unless ( $keyword ) {
    $self->error("$function_name: 'keyword' argument missing");
    return 1;
  }
  my $value = shift;
  unless ( defined($value) ) {
    $self->error("$function_name: 'value' argument missing");
    return 1;
  }
  my $line_fmt = shift;
  unless ( defined($line_fmt) ) {
    $self->error("$function_name: 'line_fmt' argument missing");
    return 1;
  }

  my $config_line = "";

  if ( $line_fmt == $line_format_param ) {
    $config_line = "$keyword=$value\t\t\t# Line generated by Quattor";
  } elsif ( $line_fmt == $line_format_envvar ) {
    $config_line = "export $keyword=$value\t\t# Line generated by Quattor";
  } elsif ( $line_fmt == $line_format_trust ) {
    $config_line = $keyword;
    $config_line .= " $value" if $value;
    # In trust (shift.conf) format, there should be only one blank between
    # tokens and no trailing spaces.
    $config_line =~ s/\s\s+/ /g;
    $config_line =~ s/\s+$//;
  } else {
    $self->error("$function_name: unsupported line format");
  }

  $self->debug(1,"$function_name: Configuration line : >>$config_line<<");
  return $config_line;
}


# This function returns host config (hash returned by getElement()).
#
# Arguments
#       role : role for which the hosts list must be normalized
#       host : host for which configuration must be returned
sub getHostConfig () {
  my $function_name = "getHostConfig";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 1;
  }
  my $host = shift;
  unless ( $host ) {
    $self->error("$function_name: 'host' argument missing");
    return 1;
  }

  my $role_hosts_list = $self->getRoleHostsList($role);

  return ${$role_hosts_list}{$this_host_full};
}


# Create list of lines matching a specific rule in a rules list
# This list in array, with array index corresponding to the order in
# the rules list.
# Each list element is an array, with one element for each line matching the
# corresponding rule. Each element describing a line is a hash describing
# the line number (LINENUM) and the line format (LINEFORMAT).
#
# Created list is returned.
#
# Arguments :
#        config_rules : rules list
sub createRulesMatchesList () {
  my $function_name = "createRulesMatchesList";
  my $self = shift;

  my $config_rules = shift;
  unless ( $config_rules ) {
    $self->error("$function_name: 'config_rules' argument missing");
    return 1;
  }

  $self->{RULESMATCHES} = [];

  my $rule_id = 0;
  for my $keyword (keys(%{$config_rules})) {
    ${$self->{RULESMATCHES}}[$rule_id] = [];
    $rule_id++;
  }

  return $self->{RULESMATCHES};
}


# Function returning reference to list of lines matching a configuration rule
#
# Arguments :
#        rule_id : rule indentifier for which to retrieve matches
sub getRuleMatches () {
  my $function_name = "getRuleMatches";
  my $self = shift;

  my $rule_id = shift;
  unless ( defined($rule_id) ) {
    $self->error("$function_name: 'rule_id' argument missing");
    return 1;
  }

  return ${$self->{RULESMATCHES}}[$rule_id];
}


# Function to add a line in RulesMatchingList
#
# Arguments :
#        rule_id : rule indentifier for which to retrieve matches
#        line_num : matching line number (in the config file)
#        line_fmt : format of the line (see buildConfigContents)
sub addInRulesMatchesList () {
  my $function_name = "addInRulesMatchesList";
  my $self = shift;

  my $rule_id = shift;
  unless ( defined($rule_id) ) {
    $self->error("$function_name: 'rule_id' argument missing");
    return 1;
  }
  my $line_num = shift;
  unless ( defined($line_num) ) {
    $self->error("$function_name: 'line_num' argument missing");
    return 1;
  }
  my $line_fmt = shift;
  unless ( defined($line_fmt) ) {
    $self->error("$function_name: 'line_fmt' argument missing");
    return 1;
  }

  $self->debug(1,"$function_name: adding line $line_num (line fmt=$line_fmt) to rule $rule_id list");
  my $list = $self->getRuleMatches($rule_id);
  my %line;
  $line{LINENUM} = $line_num;
  $line{LINEFORMAT} = $line_fmt;
  push @{$list}, \%line;

}


# Function returning line number corresponding to one element in RulesMatchingList or 'undef' if there is no more element
#
# Arguments :
#        rule_id : rule indentifier for which to retrieve matches
#        entry_num : rule match number
sub getRulesMatchesLineNum () {
  my $function_name = "getRulesMatchesLineNum";
  my $self = shift;

  my $rule_id = shift;
  unless ( defined($rule_id) ) {
    $self->error("$function_name: 'rule_id' argument missing");
    return 1;
  }
  my $entry_num = shift;
  unless ( defined($entry_num) ) {
    $self->error("$function_name: 'entry_num' argument missing");
    return 1;
  }

  my $list = $self->getRuleMatches($rule_id);
  my $entry =  ${$list}[$entry_num];

  return ${$entry}{LINENUM};
}


# Function returning line format corresponding to one element in RulesMatchingList or 'undef' if there is no more element
#
# Arguments :
#        rule_id : rule indentifier for which to retrieve matches
#        entry_num : rule match number
sub getRulesMatchesLineFmt () {
  my $function_name = "getRulesMatchesLineFmt";
  my $self = shift;

  my $rule_id = shift;
  unless ( defined($rule_id) ) {
    $self->error("$function_name: 'rule_id' argument missing");
    return 1;
  }
  my $entry_num = shift;
  unless ( defined($entry_num) ) {
    $self->error("$function_name: 'entry_num' argument missing");
    return 1;
  }

  my $list = $self->getRuleMatches($rule_id);
  my $entry =  ${$list}[$entry_num];

  return ${$entry}{LINEFORMAT};
}


# Build a new configuration file content, using template contents if any and
# applying configuration rules to transform the template.
#
# Arguments :
#       config_rules : config rules corresponding to the file to build
#       template_contents (optional) : config file template to be edit with rules.
#                                      If not present build a new file content.
sub buildConfigContents () {
  my $function_name = "buildConfigContents";
  my $self = shift;

  my $config_rules = shift;
  unless ( $config_rules ) {
    $self->error("$function_name: 'config_rules' argument missing");
    return 1;
  }
  my $template_contents = shift;

  my @newcontents;
  my @rule_lines;
  my $file_line_offset = 1;  # Used in debugging messages
  my $rule_id = 0;

  # Intialize this array of array (each array element is an array containing
  # each line where the keyword is present)
  $self->createRulesMatchesList($config_rules);


  if ( $template_contents ) {
    my $line_num = 0;
    my $intro = "# This file is managed by Quattor - DO NOT EDIT lines generated by Quattor\n#";
    my @previous_contents = split /\n/, $template_contents;

    if ($previous_contents[0] ne $intro) {
      push @newcontents, "$intro\n#" ;
      $line_num++;
      my @intro_lines = split /\cj/, $intro;  # /\cj/ matches embedded \n
      $file_line_offset += @intro_lines;
    }

    # In a template file, keyword must appear in a line in one of the following
    # format (keyword is case sensitive but may contain spaces) :
    #    something KEYWORD=value (ex: RFIOLOGFILE=/var/log/rfiod/log)
    #    KEYWORD  value (ex : RFIOD TRUST grid05.lal.in2p3.fr)
    #    something param_name=<KEYWORD> (ex : export DPNS_HOST=<DPNS_hosname>
    for my $line (@previous_contents) {
      $rule_id = 0;
      for my $keyword (keys(%{$config_rules})) {
  if ( $line =~ /^\#*\s*$keyword\s+/ ) {
    $self->addInRulesMatchesList($rule_id,$line_num,$line_format_trust);
  } elsif ( $line =~ /$keyword=<.*>/ ) {
    $self->addInRulesMatchesList($rule_id,$line_num,$line_format_envvar);
  } elsif ( $line =~ /$keyword=/ ) {
    $self->addInRulesMatchesList($rule_id,$line_num,$line_format_param);
  }
  $rule_id++;
      }
      push @newcontents, $line;
      $line_num++;
    }
  } else {
    my $intro = "# This file is managed by Quattor - DO NOT EDIT";
    push @newcontents, "$intro\n#";
    my @intro_lines = split /\cj/, $intro;  # /\cj/ matches embedded \n
    $file_line_offset += @intro_lines;
  }

  # Each rule format is '[condition->]attribute:role[,role...]' where
  #     condition : a role that must be configured on local host
  #     role and attribute : a role attribute that must be substituted
  # An empty rule is valid and means that only the keyword part must be
  # written.

  $rule_id = 0;
  for my $keyword (keys(%{$config_rules})) {
    my $rule = ${$config_rules}{$keyword};

    ($rule, my $line_fmt) = split /;/, $rule;
    unless ( $line_fmt ) {
      $line_fmt = $line_format_def;
    }

    (my $condition, my $tmp) = split /->/, $rule;
    if ( $tmp ) {
      $rule = $tmp;
    } else {
      $condition = "";
    }
    next if $condition && !$self->hostHasRoles($condition);

    my $config_value = "";
    my @roles;
    (my $attribute, my $roles) = split /:/, $rule;
    if ( $roles ) {
      @roles = split /\s*,\s*/, $roles;
    }

    # Role=GLOBAL is a special case indicating a global option instead of a
    # role option
    for my $role (@roles) {
      if ( $role eq "GLOBAL" ) {
        my $value_tmp = $self->getGlobalOption($attribute);
        if ( ref($value_tmp) eq "ARRAY" ) {
          $config_value = join " ", @$value_tmp;
        } else {
          $config_value = $value_tmp;
        }
      } else {
  if ( $attribute eq "host" ) {
    $config_value .= $self->getHostsList($role)." ";
  } elsif ( $attribute ) {
    # Use first host with  this role
    my $role_hosts = $self->getHostsList($role);
    if ( $role_hosts ) {
      my @role_hosts = split /\s+/, $role_hosts;
      my $server_config = $self->getHostConfig($role,$role_hosts[0]);
      if ( exists(${$server_config}{$attribute}) ) {
        $config_value .= ${$server_config}{$attribute}->getValue()." ";
      } else {
        $self->debug(1,"$function_name: attribute $attribute not found for component ".uc($role));
      }
          } else {
        $self->error("No host with role ".uc($role)." found");
    }
  }
      }
    }

    # $attribute empty means an empty rule : in this case,just write the keyword
    # no line is written if attribute is defined and value is empty.
    # If rule_id has matches in the RulesMatchesList, it means we are updating an existing file (template)
    if ( $attribute ) {
      my $entry_num = 0;
      if ( $self->getRulesMatchesLineNum($rule_id,$entry_num) ) {
  while ( my $line = $self->getRulesMatchesLineNum($rule_id,$entry_num) ) {
    my $file_line = $line + $file_line_offset;
    my $line_fmt = $self->getRulesMatchesLineFmt($rule_id,$entry_num);
    $config_value = $self->formatHostsList($config_value,$line_fmt) if $attribute eq "host";
    if ( $config_value ) {
      $newcontents[$line] = $self->formatConfigLine($keyword,$config_value,$line_fmt);
      $self->debug(1,"$function_name: template line $file_line replaced");
    }
    $entry_num++;
  }
      } else {
  $config_value = $self->formatHostsList($config_value,$line_fmt) if $attribute eq "host";
  if ( $config_value ) {
    push @newcontents, $self->formatConfigLine($keyword,$config_value,$line_fmt);
    $self->debug(1,"$function_name: configuration line added");
  }
      }
    } else {
      push @newcontents, $self->formatConfigLine($keyword,"", $line_fmt);
      $self->debug(1,"$function_name: configuration line added");
    }

    $rule_id++;
  }

  my $newcontents = join "\n",@newcontents;
  $newcontents .= "\n";    # Add LF after last line
  return $newcontents;
}


# Create a new configuration file, using a template if any available and
# applying configuration rules to transform the template.
#
# Arguments :
#       role : role a configuration file must be build for
sub updateConfigFile () {
  my $function_name = "updateConfigFile";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 1;
  }

  $self->debug(1,"$function_name: building configuration file for role ".uc($role));

  my $template_contents;
  
  # Load template configuration file.
  # If a template file with the role-specific extension (if defined) is not found,
  # try the default one. This is to accomodate non-standard extension eventually
  # changed to the standard one.
  my @template_ext;
  my $template_file;
  if ( $config_template_ext{$role} ) {
    push @template_ext, $config_template_ext{$role};
  }
  push @template_ext, $config_template_ext{'DEFAULT'};
  for my $ext (@template_ext) {
    $self->debug(2,"Checking if ".${$config_files{$role}}." template exists with extension $ext");
    $template_file = ${$config_files{$role}}.$ext;
    if ( -e $template_file ) {
      last;
    }
  }
  if ( -e $template_file ) {
    $self->debug(1,"$function_name: template file $template_file found, reading it");
    $template_contents = file_contents($template_file);
    $self->debug(3,"$function_name: template contents :\n$template_contents");
  } else {
    $self->debug(1,"$function_name: template file not found ($template_file). Building a new file from scratch...");
  }

  my $config_contents=$self->buildConfigContents($config_rules{$role}, $template_contents);
  $self->debug(3,"$function_name: Configuration file new contents :\n$config_contents");

  # Update configuration file if content has changed
  my $changes = LC::Check::file(${$config_files{$role}}.$config_prod_ext,
                                backup => $config_bck_ext,
                                contents => $config_contents
                               );
  unless (defined($changes)) {
    $self->error("error creating ".uc($role)."configuration file ($config_files{$role}");
    return;
  }

  # Keep track of services that need to be restarted if changes have been made
  if ( $changes > 0 ) {
    $self->serviceRestartNeeded($role);
  }

}

# Function to generate a random password of a given length. Default length is 16.
sub generatePassword {
  my $self = shift;
  
  my $length = 16;
  if ( @_ > 0 ) {
    $length = shift;
  }

  my $password = '';
  my $possible = 'abcdefghijkmnpqrstuvwxyz23456789_-!,;:.ABCDEFGHJKLMNPQRSTUVWXYZ';
  while (length($password) < $length) {
    $password .= substr($possible, (int(rand(length($possible)))), 1);
  }

  return $password;
}


# Function to configure xrootd specific configuration files.
# Based on YAIM.

sub xrootSpecificConfig () {
  my ($self) = @_;
  my $function_name = "xrootSpecificConfig";
  my $xroot_role = 'xroot';
  my $restart_services = 0;
  
  $self->info('Checking xroot specific configuration...');
  
  # Retrieve xrootd configuration and update xrootd_services based on option 'cmsDaemon'
  my $xroot_config;
  if ( $config->elementExists($xroot_options_base) ) {
    $xroot_config = $config->getElement($xroot_options_base)->getTree();
  }else {
    $self->info('xroot options not defined. Using defaults.')
  }
  my $xroot_headnode = $self->hostHasRoles('dpns');
  my $xroot_diskserver = $self->hostHasRoles('gsiftp');
  my $xroot_token_auth = defined($xroot_config->{ofsPlugin}) && $xroot_config->{ofsPlugin} eq 'TokenAuthzOfs';
  $xrootd_services{$xroot_config->{cmsDaemon}} = $xrootd_cms_services{$xroot_config->{cmsDaemon}};

  # Build xrootd configuration file (based on template provided in distribution, if it exists).
  # The template was not present in the first version of DPM-xrootd.
  if ( defined($xroot_config->{config}) ) {
    my $xrootd_config_dir = '/opt/lcg/etc';
    my $xrootd_config_file = $xrootd_config_dir . '/' . $xroot_config->{config};
    my $xrootd_config_template = $xrootd_config_file . '.templ';
    if ( -f $xrootd_config_template ) {
      if ( !compare($xrootd_config_template,$xrootd_config_file) ) {
        $self->debug(1,"$function_name: xrootd configuration file ($xrootd_config_file) is up-to-date");
      } else {
        $self->info("Updating xrootd configuration file ($xrootd_config_file) with template ($xrootd_config_template)");
        if ( copy ($xrootd_config_template,$xrootd_config_file) ) {
          $restart_services = 1;
        } else {
          $self->warn("Error creating xrootd configuration file ($xroot_config_file)");
        }
      }
    } else {
      $self->debug(2,"$function_name: xrootd configuration file template ($xrootd_config_template) not found. Configuration file ($xrootd_config_file) must be created manually.");
    }
  }
  
  # Build Authz configuration file for token-based authz
  if ( $xroot_token_auth ) {
    # Build authz.cf
    $self->info("Token-based authentication used: checking authz.cf");
    my $exported_vo_path_root = $self->NSGetRoot();
    my $xroot_authz_conf_file = $xrootd_config_dir."/".$xroot_config->{authzConf};
    my $xroot_token_priv_key;
    if ( defined($xroot_config->{tokenPrivateKey}) ) {
      $xroot_token_priv_key = $xrootd_config_dir . '/' . $xroot_config->{tokenPrivateKey};
    } else {
      $xroot_token_priv_key = $xrootd_config_dir . '/pvkey.pem';    
    }
    my $xroot_token_pub_key;
    if ( defined($xroot_config->{tokenPublicKey}) ) {
      $xroot_token_pub_key = $xrootd_config_dir . '/' . $xroot_config->{tokenPublicKey};
    } else {
      $xroot_token_pub_key = $xrootd_config_dir . '/pkey.pem';    
    }
    my $xroot_authz_conf_contents = "Configuration file for xroot authz generated by quattor - DO NOT EDIT.\n\n" .
                                    "# Keys reside in ".$xrootd_config_dir."\n" .
                                    "KEY VO:*       PRIVKEY:".$xroot_token_priv_key." PUBKEY:".$xroot_token_pub_key."\n\n" .
                                    "# Restrict the name space for export\n";
    if ( $xroot_config->{exportedVOs} ) {
      for my $vo (@{$xroot_config->{exportedVOs}} ) {
        my $exported_vo_path = $exported_vo_path_root.'/'.$vo;      
        $xroot_authz_conf_contents .= "EXPORT PATH:".$exported_vo_path." VO:*     ACCESS:ALLOW CERT:*\n";
      }
    } else {
      $self->warn("dpm-xroot: export enabled for all VOs. You should consider restrict to one VO only.");
      $xroot_authz_conf_contents .= "EXPORT PATH:".$exported_vo_path_root." VO:*     ACCESS:ALLOW CERT:*\n";
    } 
  
    $xroot_authz_conf_contents .= "\n# Define operations requiring authorization.\n";
    $xroot_authz_conf_contents .= "# NOAUTHZ operations honour authentication if present but don't require it.\n";
    if ( $xroot_config->{accessRules} ) {
      for my $rule (@{$xroot_config->{accessRules}}) {
        my $auth_ops = join '|', @{$rule->{authenticated}};
        my $noauth_ops = join '|', @{$rule->{unauthenticated}};
        $xroot_authz_conf_contents .= "RULE PATH:".$rule->{path}.
                                      " AUTHZ:$auth_ops| NOAUTHZ:$noauth_ops| VO:".$rule->{vo}." CERT:".$rule->{cert}."\n";
      }
    } else {
      $xroot_authz_conf_contents .= "\n# WARNING: no access rules defined in quattor configuration.\n";
    }
    my $changes = LC::Check::file($xroot_authz_conf_file,
                                  backup => $config_bck_ext,
                                  contents => encode_utf8($xroot_authz_conf_contents),
                                  owner => $self->getDaemonUser(),
                                  group => $self->getDaemonGroup(),
                                  mode => 0400,
                                 );
    if ( $changes > 0 ) {
      $restart_services = 1;
    } elsif ( $changes < 0 ) {
      $self->error("Error updating xrootd authorization configuration ($xroot_authz_conf_file)");
    }
  
    # Set right permissions on token public/private keys
    for my $key ($xroot_token_priv_key,$xroot_token_pub_key) {
      if ( -f $key ) {
        $self->debug(1,"$function_name: Checking permission on $key");
        $changes = LC::Check::status($key,
                                     owner => $self->getDaemonUser(),
                                     group => $self->getDaemonGroup(),
                                     mode => 0400
                                    );
        unless (defined($changes)) {
          $self->error("Error setting permissions on xrootd token key $key");
        }
      } else {
          $self->warn("xrootd token key $key not found.");
      }  
    }
  }

  # Build the list of daemons to run on the current node according to node type
  #   - Disk server must run olbd (service olb) and xrootd (service xrd)
  #   - DPM head node must run manager-olbd (service manager-olb) and manager-xrootd (service manager-xrd)
  #   - A head node acting also as a disk server must run both
  # This is managed by buildind a list of prefix to add before the daemon/service name.
  my @xroot_daemon_prefixes;
  if ( $xroot_headnode ) {
    push @xroot_daemon_prefixes,$xrootd_daemon_prefix{head};
  }
  if ( $xroot_diskserver ) {
    push @xroot_daemon_prefixes,$xrootd_daemon_prefix{disk};      
  }

  # Create symlinks to service daemons according to node type
  
  for my $prefix (@xroot_daemon_prefixes) {
    for my $daemon (keys(%xrootd_services)) {
      my $link_name = $dm_bin_dir . '/' . $prefix . $daemon;
      my $link_target = $dm_bin_dir . '/' . $daemon;
      if ( !-x $link_target ) {
        $self->warn("$link_target missing or not executable. Check your DPM installation.");
      }
      if ( -l $link_name ) {
        $self->debug(1,"$function_name: $link_name already exists. Nothing done.");
      } else {
        if ( -e $link_name ) {
          $self->error("$link_name already exists but is not a symlink.");
          next;
        } else {
          my $status = symlink $link_target, $link_name;
          if ( $status == 1 ) {
            $self->info("Symlink $link_name defined as $link_target");
            $restart_services = 1;
          } else {
            $self->error("Error defining symlink $link_name as $link_target");
          }
        }
      }
    }
  }
  
  # Define services associated with 'xroot' role according to xroot node type
  # and check if a configuration change involves restarting the services.
  
  my @xroot_service_list;
  for my $prefix (@xroot_daemon_prefixes) {
    for my $daemon (keys(%xrootd_services)) {
      my $service = $xrootd_services{$daemon};
      my $service_name = $prefix . $service;
      $self->debug(1,"$function_name: adding service $service_name to role '$xroot_role'");
      push @xroot_service_list, $service_name;
    }
    $services{$xroot_role} = join (",", @xroot_service_list);
    if ( $restart_services ) {
      $self->serviceRestartNeeded($xroot_role);
    }
  }
}

1;      # Required for PERL modules
