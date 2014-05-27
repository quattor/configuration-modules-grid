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
# of configuration files. 
#
# Configuration files are modified only if their contents need to be changed,
# not at every run of the component. In case of changes, the services depending
# on the modified files are restared.
#
# Adding support for a new configuration variable should be pretty easy.
# Basically, if this is a role specific variable, you just need add a 
# parsing rule that use it in the %xxx_config_rules
# for the configuration file. If this is a global variable, you also need to
# load it from the configuration file as this is done for other configuration
# variables (at the beginning of Configure()). Look at the comments before
# %xxx_roles definitions to know about the parsing rules format.
#
# An effort has been made to document the code. Be sure to understand it before
# modifying.
#
# In case of problems, use --debug option of ncm-ncd. This will produce a lot
# of debugging information. 2 debugging levels are available (1, 2).
#
#######################################################################

package NCM::Component::${project.artifactId};

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;

use EDG::WP4::CCM::Element;

use File::Path;
use File::Copy;
use File::Compare;
use File::Basename;
use File::stat;

use LC::Check;
use CAF::FileWriter;
use CAF::FileEditor;
use CAF::Process;

use Encode qw(encode_utf8);
use Fcntl qw(SEEK_SET);

local(*DTA);

use Net::Domain qw(hostname hostfqdn hostdomain);


# Define paths for convenience. 
my $dm_install_root_default = "";

# Define some commands explicitly
my $chkconfig = "/sbin/chkconfig";
my $servicecmd = "/sbin/service";

my $dpm_def_host;

my $config_bck_ext = ".old";    # Replaced version extension
#my $config_prod_ext = ".new";    # For testing purpose only
my $config_prod_ext = "";    # For testing purpose only


# Constants use to format lines in configuration files
use constant LINE_FORMAT_PARAM => 1;
use constant LINE_FORMAT_ENVVAR => 2;
use constant LINE_FORMAT_TRUST => 3;
use constant LINE_VALUE_AS_IS => 0;
use constant LINE_VALUE_BOOLEAN => 1;
my $line_format_def = LINE_FORMAT_PARAM;

# dpm and lfc MUST be the first element in their respective @xxx_roles array to 
# correctly apply defaults
# Role names used here must be the same as key in other hashes.
my @dpm_roles = (
     "copyd",
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
          "copyd" => 1,
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


# Following hashes define parsing rules to build a configuration.
# Hash key is the line keyword in configuration file and 
# hash value is the parsing rule for the keyword value. Parsing rule format is :
#       [role_condition->]option_name:option_role[,option_role,...];line_fmt[;value_fmt]
# 'role_condition' is a role that must be present on the local machine for the
# rule to be applied or ALWAYS if the rule must be applied even if the role is disabled
# (mainly used for RUN_xxxDAEMON variables).
# 'option_name' is the name of an option that will be retrieved from the configuration
# 'option_role' is the role the option is attached to (for example 'host:dpns'
# means 'host' option of 'dpns' role. 'GLOBAL' is a special value for 'option_role'
# indicating that the option is global option and not a role specific option.
# 'line_fmt' indicates the line format for the parameter : 3 formats are 
# supported :
#  - envvar : a sh shell environment variable definition (export VAR=val)
#  - param : a sh shell variable definition (VAR=val)
#  - trust : a 'keyword value' line, as used by /etc/shift.conf
# Line format has an impact on hosts list if there is one. For trust format,
# each host in the local domain is inserted with its FQDN and local host is removed. 
# 'value_fmt' allows special formatting of the value. This is mainly used for boolean
# values so that they are encoded as 'yes' or 'no'.
# If there are several servers for a role the option value from all the servers# is used for 'host' option, and only the server corresponding to current host
# for other options.
my $copyd_config_file = "/etc/sysconfig/dpmcopyd";
my %copyd_config_rules = (
        "ALLOW_COREDUMP" =>"allowCoreDump:copyd;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "DPM_HOST" => "host:dpm;".LINE_FORMAT_PARAM,
        "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
        "DPMCOPYDLOGFILE" => "logfile:copyd;".LINE_FORMAT_PARAM,
        #"DPMCOPYD_PORT" => "port:copyd;".LINE_FORMAT_PARAM,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
        ##"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_PARAM,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
        "RUN_DPMCOPYDAEMON" => "ALWAYS->copyd_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "ULIMIT_N" => "maxOpenFiles:copyd;".LINE_FORMAT_PARAM,
       );

my $dpm_config_file = "/etc/sysconfig/dpm";
my %dpm_config_rules = (
      "ALLOW_COREDUMP" =>"allowCoreDump:dpm;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
      "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
      "DPMDAEMONLOGFILE" => "logfile:dpm;".LINE_FORMAT_PARAM,
      #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
      #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
      #"DPM_PORT" => "port:dpm;".LINE_FORMAT_PARAM,
      "DPM_USE_SYNCGET" => "useSyncGet:dpm;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
      "NB_FTHREADS" => "fastThreads:dpm;".LINE_FORMAT_PARAM,
      "NB_STHREADS" => "slowThreads:dpm;".LINE_FORMAT_PARAM,
      "RUN_DPMDAEMON" => "ALWAYS->dpm_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "ULIMIT_N" => "maxOpenFiles:dpm;".LINE_FORMAT_PARAM,
           );

my $dpns_config_file = "/etc/sysconfig/dpnsdaemon";
my %dpns_config_rules = (
       "ALLOW_COREDUMP" =>"allowCoreDump:dpns;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
       #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
       #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
       "DPNSDAEMONLOGFILE" => "logfile:dpns;".LINE_FORMAT_PARAM,
       #"DPNS_PORT" => "port:dpns;".LINE_FORMAT_PARAM,
       "NB_THREADS" => "threads:dpns;".LINE_FORMAT_PARAM,
       "NSCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
       "RUN_DPNSDAEMON" => "ALWAYS->dpns_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
       "RUN_READONLY" => "readonly:dpns;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
       "ULIMIT_N" => "maxOpenFiles:dpns;".LINE_FORMAT_PARAM,
      );

my $gsiftp_config_file = "/etc/sysconfig/dpm-gsiftp";
my %gsiftp_config_rules = (
         "DPM_HOST" => "host:dpm;".LINE_FORMAT_PARAM,
         "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
         "FTPLOGFILE" => "logfile:gsiftp;".LINE_FORMAT_PARAM,
         "GLOBUS_TCP_PORT_RANGE" => "portRange:gsiftp;".LINE_FORMAT_PARAM,
         "OPTIONS" => "startupOptions:gsiftp;".LINE_FORMAT_PARAM,
         "RUN_DPMFTP" => "ALWAYS->gsiftp_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        );

my $rfio_config_file = "/etc/sysconfig/rfiod";
my %rfio_config_rules = (
       "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
       "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
       "OPTIONS" => "startupOptions:rfio;".LINE_FORMAT_PARAM,
       "RFIOLOGFILE" => "logfile:rfio;".LINE_FORMAT_PARAM,
       "RFIO_PORT_RANGE" => "portRange:rfio;".LINE_FORMAT_PARAM,
       "RUN_RFIOD" => "ALWAYS->rfio_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
       "ULIMIT_N" => "maxOpenFiles:rfio;".LINE_FORMAT_PARAM,
       );

my $srmv1_config_file = "/etc/sysconfig/srmv1";
my %srmv1_config_rules = (
        "ALLOW_COREDUMP" =>"allowCoreDump:srmv1;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
        #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
        "DPM_HOST" => "host:dpm;".LINE_FORMAT_PARAM,
        "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_PARAM,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
        "RUN_SRMV1DAEMON" => "ALWAYS->srmv1_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "SRMV1DAEMONLOGFILE" => "logfile:srmv1;".LINE_FORMAT_PARAM,
        #"SRMV1_PORT" => "port:srmv1;".LINE_FORMAT_PARAM,
        "ULIMIT_N" => "maxOpenFiles:srmv1;".LINE_FORMAT_PARAM,
       );

my $srmv2_config_file = "/etc/sysconfig/srmv2";
my %srmv2_config_rules = (
        "ALLOW_COREDUMP" =>"allowCoreDump:srmv2;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
        #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
        "DPM_HOST" => "host:dpm;".LINE_FORMAT_PARAM,
        "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_PARAM,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
        "RUN_SRMV2DAEMON" => "ALWAYS->srmv2_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "SRMV2DAEMONLOGFILE" => "logfile:srmv2;".LINE_FORMAT_PARAM,
        #"SRMV2_PORT" => "port:srmv2;".LINE_FORMAT_PARAM,
        "ULIMIT_N" => "maxOpenFiles:srmv2;".LINE_FORMAT_PARAM,
       );

my $srmv22_config_file = "/etc/sysconfig/srmv2.2";
my %srmv22_config_rules = (
        "ALLOW_COREDUMP" =>"allowCoreDump:srmv22;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
        #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
        "DPM_HOST" => "host:dpm;".LINE_FORMAT_PARAM,
        "DPNS_HOST" => "host:dpns;".LINE_FORMAT_PARAM,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_PARAM,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
        "NB_THREADS" => "threads:srmv22;".LINE_FORMAT_PARAM,
        "RUN_SRMV2DAEMON" => "ALWAYS->srmv22_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
        "SRMV22DAEMONLOGFILE" => "logfile:srmv22;".LINE_FORMAT_PARAM,
        #"SRMV2_2_PORT" => "port:srmv22;".LINE_FORMAT_PARAM,
        "ULIMIT_N" => "maxOpenFiles:srmv22;".LINE_FORMAT_PARAM,
       );

my $trust_roles = "dpm,dpns,rfio,gsiftp";
my $trust_config_file = "/etc/shift.conf";
my %trust_config_rules = (
        "DPM PROTOCOLS" => "accessProtocols:GLOBAL;".LINE_FORMAT_TRUST,
        "DPM TRUST" => "dpm->host:dpns,xroot;".LINE_FORMAT_TRUST,
        "DPNS TRUST" => "dpns->host:dpm,srmv1,srmv2,srm22,rfio;".LINE_FORMAT_TRUST,
        "RFIOD TRUST" => "rfio->host:dpm,rfio;".LINE_FORMAT_TRUST,
        "RFIOD WTRUST" => "rfio->host:dpm,rfio;".LINE_FORMAT_TRUST,
        "RFIOD RTRUST" => "rfio->host:dpm,rfio;".LINE_FORMAT_TRUST,
        "RFIOD XTRUST" => "rfio->host:dpm,rfio;".LINE_FORMAT_TRUST,
        "RFIOD FTRUST" => "rfio->host:dpm,rfio;".LINE_FORMAT_TRUST,
        "RFIO DAEMONV3_WRMT 1" => ";".LINE_FORMAT_TRUST,
        "DPM REQCLEAN" => "dpm->requestMaxAge:dpm;".LINE_FORMAT_TRUST,
       );

my $lfc_config_file = "/etc/sysconfig/lfcdaemon";
my %lfc_config_rules = (
      "LFCDAEMONLOGFILE" => "logfile:lfc",
      #"LFCGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
      #"LFC_PORT" => "port:lfc;".LINE_FORMAT_ENVVAR,
      #"LFCUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
      "NB_THREADS" => "threads:lfc;".LINE_FORMAT_PARAM,
      "NSCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_PARAM,
      "RUN_DISABLEAUTOVIDS" => "disableAutoVirtualIDs:lfc;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "RUN_LFCDAEMON" => "ALWAYS->lfc_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "RUN_READONLY" => "readonly:lfc;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "ULIMIT_N" => "maxOpenFiles:lfc;".LINE_FORMAT_PARAM,
           );

my $lfcdli_config_file = "/etc/sysconfig/lfc-dli";
my %lfcdli_config_rules = (
         "DLIDAEMONLOGFILE" => "logfile:lfc-dli",
         #"DLI_PORT" => "port:lfc-dli;".LINE_FORMAT_ENVVAR,
         "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_PARAM,
         "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_PARAM,
         #"LFCGROUP" => "group:GLOBAL;".LINE_FORMAT_PARAM,
         "LFC_HOST" => "host:lfc",
         #"LFCUSER" => "user:GLOBAL;".LINE_FORMAT_PARAM,
         "RUN_DLIDAEMON" => "ALWAYS->lfc-dli_service_enabled:GLOBAL;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
         "ULIMIT_N" => "maxOpenFiles:lfc-dli;".LINE_FORMAT_PARAM,
        );

my %config_files = (
        "copyd" => \$copyd_config_file,
        "dpm" => \$dpm_config_file,
        "dpns" => \$dpns_config_file,
        "gsiftp" => \$gsiftp_config_file,
        "rfio" => \$rfio_config_file,
        "srmv1" => \$srmv1_config_file,
        "srmv2" => \$srmv2_config_file,
        "srmv22" => \$srmv22_config_file,
        "trusts" => \$trust_config_file,
        "lfc" => \$lfc_config_file,
        "lfc-dli" => \$lfcdli_config_file,
       );

my %config_rules = (
        "copyd" => \%copyd_config_rules,
        "dpm" => \%dpm_config_rules,
        "dpns" => \%dpns_config_rules,
        "gsiftp" => \%gsiftp_config_rules,
        "rfio" => \%rfio_config_rules,
        "srmv1" => \%srmv1_config_rules,
        "srmv2" => \%srmv2_config_rules,
        "srmv22" => \%srmv22_config_rules,
        "trusts" => \%trust_config_rules,
        "lfc" => \%lfc_config_rules,
        "lfc-dli" => \%lfcdli_config_rules,
       );
       

# Define services using each role/configuration file (if any), with each service
# separated by a comma. Services will be restarted once even if they have
# multiple dependencies.
# If service list is prefixed by 'role:', list is a name of role that is
# present in this list (take care not to create a loop).
# 'trusts' is a special entry associated with modifications of /etc/shift.conf.
# Service will be restarted if configuration changes.
my %services = (
    "copyd" => "dpmcopyd",
    "dpm" => "dpm",
    "dpns" => "dpnsdaemon",
    "gsiftp" => "dpm-gsiftp",
    "rfio" => "rfiod",
    "srmv1" => "srmv1",
    "srmv2" => "srmv2",
    "srmv22" => "srmv2.2",
    "lfc" => "lfcdaemon",
    "lfc-dli" => "lfc-dli",
    #"trusts" => "role:dpm,dpns,gsiftp,rfio,xroot",   # shift.conf modifications are automaticaly detected without a need to restart daemons
         );


# Define nameserver role in each product
my %nameserver_role = (
                       "DPM", "dpns",
                       "LFC", "lfc",
                      );

# Define roles needing access to database
my %db_roles = (
    "DPM" => "dpm,dpns",
    "LFC" => "lfc",
         );


# Define file where is stored DB connection information
my %db_conn_config = (
          "DPM" => "/etc/DPMCONFIG",
          "LFC" => "/etc/NSCONFIG",
         );
my %db_conn_config_mode = (
          "DPM" => "600",
          "LFC" => "600",
         );

my %db_servers;

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
         "DPM" => "copyd,dpm,dpns,srmv1,srmv2,srmv22",
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
my $dm_install_root;
my $dm_bin_dir;

# Pan path for the component configuration, variable to host the profile contents and other
# constants related to profile
use constant PANPATH => "/software/components/${project.artifactId}";
my $profile;


##########################################################################
sub Configure($$@) {
##########################################################################
    
  (my $self, $config) = @_;
  
  $this_host_name = hostname();
  $this_host_domain = hostdomain();
  $this_host_full = join ".", $this_host_name, $this_host_domain;

  $profile = $config->getElement(PANPATH)->getTree();

  # Process separatly DPM and LFC configuration
  
  my $comp_max_servers;
  for my $product (@products) {

    # Establish context for other functions
    $self->defineCurrentProduct($product);

    $self->loadGlobalOption("installDir");
    $dm_install_root = $self->getGlobalOption("installDir");
    unless ( defined($dm_install_root) ) {
      $dm_install_root = $dm_install_root_default;
    }
    $self->setGlobalOption("installDir",$dm_install_root);
    if ((length($dm_install_root) == 0) || ($dm_install_root eq "/")) {
      $dm_install_root = "";
      $dm_bin_dir = "/usr/bin";
    } else {
      $dm_bin_dir = $dm_install_root . "/bin";      
    }
    
    if ( $product eq "DPM" ) {
      $hosts_roles = \@dpm_roles;
      $comp_max_servers = \%dpm_comp_max_servers;
    } else {
      $hosts_roles = \@lfc_roles;
      $comp_max_servers = \%lfc_comp_max_servers;
    }

    # Check that the product is configured, else there is no point in doing
    # what follows, even though this is mainly harmless.
    my $product_configured = 0;
    foreach my $role (@$hosts_roles) {
      if ( exists($profile->{$role}) ) {
        $product_configured = 1; 
        last;  
      }
    }
    if ( ! $product_configured ) {
      $self->debug(1,"Product $product not configured: skipping its configuration");
      next;  
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
    if ( my $v = $self->getDbOption('configfile') ) {
      $self->setGlobalOption("dbconfigfile",$v);
      $self->debug(1,"Global option 'dbconfigfile' defined to ".$self->getGlobalOption("dbconfigfile"));
    } else {
      $self->setGlobalOption("dbconfigfile",$db_conn_config{$product});
      $self->debug(1,"Global option 'dbconfigfile' set to default : ".$self->getGlobalOption("dbconfigfile"));
    }
    if ( my $v = $self->getDbOption('configmode') ) {
      $self->setGlobalOption("dbconfigmode",$v);
      $self->debug(1,"Global option 'dbconfigmode' defined to ".$self->getGlobalOption("dbconfigmode"));
    } else {
      $self->setGlobalOption("dbconfigmode",$db_conn_config_mode{$product});
      $self->debug(1,"Global option 'dbconfigmode' set to default : ".$self->getGlobalOption("dbconfigmode"));
    }


    # At least $profile->{dpm} or $profile->{lfc} must exist

    for my $role (@{$hosts_roles}) {
      # By default, assume this role is disabled on local host
      $self->setGlobalOption($role."_service_enabled",0);        
      if ( exists($profile->{$role}) ) {
        my $servers = $profile->{$role};
        if ( keys(%{$servers}) <= ${$comp_max_servers}{$role} ) {
          my $def_host;
          while ( my ($role_host,$host_params) = each(%{$servers}) ) {
            if ( ($role eq "dpm") || ($role eq "lfc") ) {
              if ( $role eq "lfc" ){
                if ( $self->hostHasRoles("dpns") ) {
                  $self->error("LFC server and DPNS server cannot be run on the same node. Skipping LFC configuration.");
                  return 0;
                }
              }
            }            
            $self->addHostInRole($role,$role_host,$host_params);
            if ( $role_host eq $this_host_full ) {
              $self->setGlobalOption($role."_service_enabled",1);
            }
          }
        } else {
          $self->error("Too many ".uc($role)." servers (maximum=${$comp_max_servers}{$role})");
          return 0;
        }
      }
    }

    # Update configuration files for every configured role.
    # xroot is a special case as it is managed by a separate component, ncm-xrootd.
    for my $role (@{$hosts_roles}) {
      if ( $role ne 'xroot' ) {
        if ( $self->hostHasRoles($role) ) {
          $self->info("Checking configuration for ".$role);
          $self->updateRoleConfig($role);
          for my $service ($self->getRoleServices($role)) {
            $self->enableService($service);
          }
        } else {
          $self->info("Checking that role ".$role." is disabled...");        
          $self->updateRoleConfig($role,1);
        }
      }
    }

    if ( $product eq "DPM" ) {
      $self->updateRoleConfig("trusts") if $self->hostHasRoles($trust_roles);
    }

    # Build init script to control all enabled services
    $self->buildEnabledServiceInitScript();

    # Do necessary DB initializations (only if current host has one role needing
    # DB access
    if ( $self->hostHasRoles($db_roles{$product}) ) {
      $self->info("Checking ".$self->getCurrentProduct()." database configuration...");
      my $status = $self->createDbConfigFile();
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
  for my $product (@products) {
    $self->defineCurrentProduct($product);
    if ( $self->hostHasRoles($nameserver_role{$product}) ) {
      $self->info("Checking namespace configuration for supported VOs...");
      $self->NSRootConfig();
      if ( exists($profile->{vos}) ) {
        my $vos = $profile->{vos};
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
    if ( exists($profile->{pools}) ) {
      my $pools = $profile->{pools};
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

  my @cmd_array = split /\s+/, $cmd;
  my $verb = $cmd_array[0];
  if ( ! -x $verb ) {
    $self->error("Command $verb not found");
    return(2);
  }
  
  my $errormsg = CAF::Process->new(\@cmd_array,log=>$self)->output();
  my $status = $?;

  if ( $status ) {
    $self->debug(1,"$function_name: commad $verb failed (status=$status, error=".$errormsg.")");
    if ( defined($error) ) {
      $$error = $errormsg;
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

  if ( exists($profile->{options}->{lc($product)}->{$option}) ) {
    my $value = $profile->{options}->{lc($product)}->{$option};
    $self->setGlobalOption($option,$value);
    $self->debug(2,"$function_name: Global option '$option' found : ".$self->getGlobalOption($option));
  } else {
    $self->debug(2,"$function_name: Global option '$option' not found : ");    
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

  if ( exists($profile->{options}->{lc($product)}->{db}->{$option}) ) {
    return $profile->{options}->{lc($product)}->{db}->{$option};
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


# Function to create the DB configuration file
#
# Arguments : 
#  none
sub createDbConfigFile () {
  my $function_name = "createDbConfigFile";
  my $self = shift;

  my $product = $self->getCurrentProduct();
  $self->debug(1,"$function_name: Creating database configuration file for $product");

  unless ( exists($profile->{options}->{lc($product)}->{db}) ) {
    $self->warn("Cannot configure DB connection : configuration missing in profile");
    return 1;
  }

  my $do_db_config = 1;

  # Owner of the DB configuration file
  my $daemon_user = $self->getDaemonUser();
  my $daemon_group = $self->getDaemonGroup();

  my $db_user = $self->getDbOption("user");
  unless ( $db_user ) {
    $self->warn("Cannot configure DB connection : DB username missing");
    return 1; 
  }
  $self->setGlobalOption("dbuser",$db_user);

  my $db_pwd = $self->getDbOption("password");
  unless ( $db_pwd ) {
    $self->warn("Cannot configure DB connection : DB password missing");
    return 1;
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


  # info_user is the MySQL user used by GIP to collect DPM statistics.
  # Configure only if GIP is configured on the machine.
  my $gip_user;
  my $db_info_user;
  my $db_info_pwd;
  my $db_info_file;
  if ( $config->elementExists($gip_user_path) ) {
    $gip_user = $config->getElement($gip_user_path)->getValue();
    $db_info_user = $self->getDbOption("infoUser");
    if ( $db_info_user ) {
      $self->setGlobalOption("dbinfouser",$db_info_user);
      $db_info_pwd = $self->getDbOption("infoPwd");
      if ( $db_info_pwd ) {
        $self->setGlobalOption("dbinfopwd",$db_info_pwd);
      } else {
        $self->warn("Cannot configure DB for info user : DB password missing.");
        return 1;
      }
      $db_info_file= $self->getDbOption("infoFile");
      unless ( $db_info_file ) {
        $db_info_file = $product . "INFO";
        $self->info("DB info connection file not configured. Set to default ($db_info_file)");
      }
    } else {
      $self->debug(1,"$function_name: DB infoUser not defined, DB configuration for GIP ignored.");
    }
  } else {
    $self->debug(1,"GIP no configured on this node. Skipping $product DB configuration for GIP.");
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
  if ( $db_info_user ) {
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
    $self->debug(1,"$function_name: no services associated with role '$role'");
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


# Function returning name of hash handling the list of enabled services for to the current product
#
# Arguments :
#  none
sub getEnabledServiceListName () {
  my $function_name = "getEnabledServiceListName";
  my $self = shift;

  my $product = $self->getCurrentProduct();

  return "SERVICEENABLEDLIST".$product;
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

  CAF::Process->new([$chkconfig, $service],log=>$self)->run();
  if ( $? ) {
    # No need to do chkconfig --add first, done by default
    $self->info("Enabling service $service at startup");
    CAF::Process->new([$chkconfig, $service, "on"],log=>$self)->run();
    if ( $? ) {
      $self->error("Failed to enable service $service");
    }
  } else {
    $self->debug(2,"$function_name: $service already enabled");
  }

  my $enabled_service_list_name = $self->getEnabledServiceListName();
  unless ( defined($self->{$enabled_service_list_name}) ) {
      $self->{$enabled_service_list_name} = {};
  }
  $self->{$enabled_service_list_name}->{$service} = 1;     # Value is useless

}


# Generate an init script to control (start/stop/restart) all enabled services.

sub buildEnabledServiceInitScript () {
  my $function_name = "buildEnabledServiceInitScript";
  my $self = shift;

  my $init_script_name = '/etc/init.d/'.lc($self->getCurrentProduct()).'-all-daemons';
  my $enabled_service_list_name = $self->getEnabledServiceListName();
  my $contents;

  # The list should not be defined if it is empty...
  if ( $self->{$enabled_service_list_name} ) {
    $self->info("Checking init script used to control all ".$self->getCurrentProduct()." enabled services (".$init_script_name.")...");
    $contents = "#!/bin/sh\n\n";
    for my $service (keys(%{$self->{$enabled_service_list_name}})) {
      if ( $self->{$enabled_service_list_name}->{$service} ) {
        $contents .= "/etc/init.d/".$service." \$*\n";
      }
    }
    
    my $status = LC::Check::file($init_script_name,
                                 contents => $contents,
                                 owner => 'root',
                                 group => 'root',
                                 mode => 0755,
                                 );
    if ( $status < 0 ) {
      $self->warn("Error creating init script to control all ".$self->getCurrentProduct()." services ($init_script_name)");
    }
  } else {
    $self->debug(1,"$function_name: no service enabled for ".$self->getCurrentProduct().' ('.$init_script_name.')');
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

  # Need to do stop+start as sometimes dpm daemon doesn't restart properly with
  # 'restart'. Try to restart even if stop failed (can be just the daemon is 
  # already stopped)
  if ( my $list = $self->getServiceRestartList() ) {
    $self->debug(1,"$function_name: list of services to restart : ".join(" ",keys(%{$list})));
    for my $service (keys %{$list}) {
      $self->info("Restarting service $service");
      CAF::Process->new([$servicecmd, $service, "stop"],log=>$self)->run();
      if ( $? ) {
        # Service can be stopped, don't consider failure to stop as an error
        $self->warn("\tFailed to stop $service");
      }
      sleep 5;    # Give time to the daemon to shut down
      my $attempt = 10;
      my $status;
      my $command = CAF::Process->new([$servicecmd, $service, "start"],log=>$self);
      $command->run();
      $status = $?;
      while ( $attempt && $status ) {
        $self->debug(1,"$function_name: $service startup failed (probably not shutdown yet). Retrying ($attempt attempts remaining)");
        sleep 5;
        $attempt--;
        $command->run();
        $status = $?;
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


# Function returning name of hash handling the list of  hosts per role for to the current product
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
# hash value a reference to the host configuration hash retrieved from
# the profile.
# For each non qualified host name, add local domain name
#
# Arguments
#       role : role for which the hosts list must be normalized
#       host : host to add (a short name is interpreted a local domain name)
#       role : host configuration hash
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

  if ( $line_fmt == LINE_FORMAT_PARAM ) {
    $config_line = "$keyword=$value";
  } elsif ( $line_fmt == LINE_FORMAT_ENVVAR ) {
    $config_line = "export $keyword=$value";
  } elsif ( $line_fmt == LINE_FORMAT_TRUST ) {
    $config_line = $keyword;
    $config_line .= " $value" if $value;
    # In trust (shift.conf) format, there should be only one blank between
    # tokens and no trailing spaces.
    $config_line =~ s/\s\s+/ /g;
    $config_line =~ s/\s+$//;
  } else {
    $self->error("$function_name: unsupported line format");
  }

  $self->debug(2,"$function_name: Configuration line : >>$config_line<<");
  return $config_line;
}


# This function returns host config.
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


# Update configuration file content,  applying configuration rules.
#
# Arguments :
#       file_name: name of the file to update
#       config_rules: config rules corresponding to the file to build
#       role_disabled (optional): flag indicating that role is disabled (D: 0)
#                                 only rules with condition=ALWAYS will be applied

sub updateConfigFile () {
  my $function_name = "updateConfigFile";
  my $self = shift;

  my $file_name = shift;
  unless ( $file_name ) {
    $self->error("$function_name: 'file_name' argument missing");
    return 1;
  }
  my $config_rules = shift;
  unless ( $config_rules ) {
    $self->error("$function_name: 'config_rules' argument missing");
    return 1;
  }

  my $role_disabled = shift;
  unless ( defined($role_disabled) ) {
    # Assume role is enabled
    $role_disabled = 0;
  }

  my $fh = CAF::FileEditor->new($file_name, log => $self);
  seek($fh, 0, SEEK_SET);

  # Check that config file has an appropriate header
  my $intro_pattern = "# This file is managed by Quattor";
  my $intro = "# This file is managed by Quattor - DO NOT EDIT lines generated by Quattor";
  $fh->add_or_replace_lines(qr/^$intro_pattern/,
                            qr/^$intro$/,
                            $intro."\n#\n",
                            BEGINNING_OF_FILE,
                           );
  
  # Loop over all config rule entries.
  # Config rules are stored in a hash whose key is the variable to write
  # and whose value is the rule itself.
  # Each rule format is '[condition->]attribute:role[,role...];line_fmt' where
  #     condition: a role that must be configured on local host or ALWAYS 
  #                if the variable must be configured even if the service is disabled.
  #     role and attribute: a role attribute that must be substituted
  #     line_fmt: the format to use when building the line
  # An empty rule is valid and means that the keyword part must be
  # written as is, using the line_fmt specified.
  
  my $rule_id = 0;
  while ( my ($keyword,$rule) = each(%{$config_rules}) ) {

    # Split different elements of the rule
    ($rule, my $line_fmt, my $value_fmt) = split /;/, $rule;
    unless ( $line_fmt ) {
      $line_fmt = $line_format_def;
    }
    unless ( $value_fmt ) {
      $value_fmt = LINE_VALUE_AS_IS;
    }

    (my $condition, my $tmp) = split /->/, $rule;
    if ( $tmp ) {
      $rule = $tmp;
    } else {
      $condition = "";
    }
    next if $role_disabled && ($condition ne "ALWAYS");
    next if $condition && ($condition ne "ALWAYS") && !$self->hostHasRoles($condition);
    $self->debug(1,"$function_name: processing rule ".$rule_id."(variable=>>>".$keyword.
                      "<<<, condition=>>>".$condition."<<<, rule=>>>".$rule."<<<, fmt=".$line_fmt.")");

    my $config_value = "";
    my @roles;
    (my $attribute, my $roles) = split /:/, $rule;
    if ( $roles ) {
      @roles = split /\s*,\s*/, $roles;
    }

    # Build the value to be substitued for each role specified.
    # Role=GLOBAL is a special case indicating a global option instead of a
    # role option
    for my $role (@roles) {
      if ( $role eq "GLOBAL" ) {
        my $value_tmp = $self->getGlobalOption($attribute);
        if ( ref($value_tmp) eq "ARRAY" ) {
          $config_value = join " ", @$value_tmp;
        } else {
          if ( $value_fmt == LINE_VALUE_BOOLEAN ) {
            if ( $value_tmp ) {
              $config_value = '"yes"';
            } else {
              $config_value = '"no"';
            }
          } else {          
            $config_value = $value_tmp;
          }
        }
      } else {
        if ( $attribute eq "host" ) {
          $config_value .= $self->getHostsList($role)." ";
        } elsif ( $attribute ) {
          my $role_hosts = $self->getHostsList($role);
          if ( $role_hosts ) {
            # Use first host with  this role if current host is not enabled for
            # the role. Not really sensible to refer a host specific configuration
            # for a role not executed on the local host.
            my $h;
            if ( grep(/$this_host_full/,$role_hosts) ) {
              $h = $this_host_full;
            } else {              
              my @role_hosts = split /\s+/, $role_hosts;
              $h = $role_hosts[0];
            }
            my $server_config = $self->getHostConfig($role,$h);
            if ( exists($server_config->{$attribute}) ) {
              my $v;
              if ( $value_fmt == LINE_VALUE_BOOLEAN ) {
                if ( $server_config->{$attribute} ) {
                  $v = '"yes"';
                } else {
                  $v = '"no"';
                }
              } else {
                $v= $server_config->{$attribute};                
              }
              $config_value .= $v." ";
            } else {
              $self->debug(1,"$function_name: attribute $attribute not found for component ".uc($role));
            }
          } else {
              $self->error("No host with role ".uc($role)." found");
          }
        }
          $self->debug(2,"$function_name: adding attribute".$attribute."for role ".$role." (config_value=".$config_value.")");
      }
    }

    # $attribute empty means an empty rule : in this case,just write the keyword
    # no line is written if attribute is defined and value is empty.
    # If rule_id has matches in the RulesMatchesList, it means we are updating an existing file (template)
    my $newline;
    my $keyword_pattern;
    if ( $attribute ) {
      $config_value = $self->formatHostsList($config_value,$line_fmt) if $attribute eq "host";
      if ( $config_value ) {
        $newline = $self->formatConfigLine($keyword,$config_value,$line_fmt);
      }
      if ( $line_fmt == LINE_FORMAT_PARAM ) {
        $keyword_pattern = "#?\\s*$keyword=";
      } elsif ( $line_fmt == LINE_FORMAT_ENVVAR ) {
        $keyword_pattern = "#?\\s*export $keyword=";
      } elsif ( $line_fmt == LINE_FORMAT_TRUST ) {
        $keyword_pattern = "#?\\s*$keyword\\s+";
      }
    } else {
      $keyword_pattern = "#?\\s*$keyword";
      $keyword_pattern =~ s/\s+/\\s+/g;
      $newline = $self->formatConfigLine($keyword,"", $line_fmt);
    }

    if ( $newline ) {
      $self->debug(1,"$function_name: checking expected configuration line ($newline) with pattern >>>".$keyword_pattern."<<<");
      $fh->add_or_replace_lines(qr/^$keyword_pattern/,
                                qr/^$newline$/,
                                $newline."\t\t# Line generated by Quattor\n",
                                ENDING_OF_FILE,
                               );      
    }

    $rule_id++;
  }

  # Update configuration file if content has changed
  my $changes = $fh->close();

  return $changes;
}


# Update a role configuration file, applying the appropriate configuration rules.
# This function retrieves the config file associated with role and then calls
# updateConfigFile() to actually do the update. It flags the service associated
# with the role for restart if the config file was changed.
#
# Arguments :
#       role : role a configuration file must be build for
#       role_disabled (optional): flag indicating that role is disabled (D: 0)
#                                 only rules with condition=ALWAYS will be applied
sub updateRoleConfig () {
  my $function_name = "updateRoleConfig";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing");
    return 1;
  }

  my $role_disabled = shift;
  unless ( defined($role_disabled) ) {
    # Assume role is enabled
    $role_disabled = 0;
  }

  $self->debug(1,"$function_name: building configuration file for role ".uc($role)." (".${$config_files{$role}}.")");

  my $changes=$self->updateConfigFile(${$config_files{$role}},$config_rules{$role},$role_disabled);

    # Keep track of services that need to be restarted if changes have been made
  if ( $changes > 0 ) {
    $self->serviceRestartNeeded($role);
  }
}


1;      # Required for PERL modules
