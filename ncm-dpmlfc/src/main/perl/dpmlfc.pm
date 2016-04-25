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
use warnings;
use vars qw($EC);
use parent qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;

use EDG::WP4::CCM::Element;

use Readonly;

use File::Path;
use File::Copy;
use File::Compare;
use File::Basename;
use File::stat;

use LC::Check;
use CAF::FileWriter;
use CAF::FileEditor;
use CAF::FileReader;
use CAF::Process;
use CAF::Object;
use CAF::RuleBasedEditor qw(:rule_constants);

use Encode qw(encode_utf8);
use Fcntl qw(SEEK_SET);

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


# dpm and lfc MUST be the first element in their respective @xxx_roles array to 
# correctly apply defaults
# Role names used here must be the same as key in other hashes.
my @dpm_roles = (
     "copyd",
     "dav",
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
          "dav" => 999,
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
#       [condition->]option_name:option_set[,option_set,...];line_fmt[;value_fmt]
#
# If the line keyword (hash key) is starting with a '-', this means that the matching
# configuration line must be removed/commented out (instead of added/updated) from the
# configuration file if present. If it is starting with a '?', this means that the
# matching line must be removed/commented out if the option is undefined.
#
# 'condition': an option or an option set that must exist for the rule to be applied.
#              Both option_set and option_name:option_set are accepted (see below).
#              Only one option set is allowed and only existence, not value is tested.
#              In addition, the condition may be negated (option or option_set must
#              not exist) by prepending a '!' to it.
#
# 'option_name' is the name of an option that will be retrieved from the configuration
# 'option_set' is the set of options the option is located in (for example 'dpnsHost:dpm'
# means 'dpnsHost' option of 'dpm' option set. 'GLOBAL' is a special value for 'option_set'
# indicating that the option is a global option, instead of belonging to a specific option set.
#
# 'line_fmt' indicates the line format for the parameter : 3 formats are 
# supported :
#  - envvar : a sh shell environment variable definition (export VAR=val)
#  - param : a sh shell variable definition (VAR=val)
#  - xrdcfg : a 'keyword value' line, as used by Xrootd config files.
#  - xrdcfg_setenv : a 'setenv' line, as used by Xrootd config files.
#  - xrdcfg_set : a 'set' line, as used by Xrootd config files.
# Inline comments are not supported in xrdcfg family of formats.
# Line format has an impact on hosts list if there is one.
#
# 'value_fmt' allows special formatting of the value. This is mainly used for boolean
# values so that they are encoded as 'yes' or 'no'.
# If there are several servers for a role the option value from all the servers# is used for 'host' option, and only the server corresponding to current host
# for other options.
#
# NOTE: DPM_HOST/DPNS_HOST are added exported as some components require this in recent DPM versions (1.8.8+).
#       Unfortunately, the sysconfig template file provided in the RPM has an uncommented unexported version of the
#       variables which is not syntactically correct (suggested value between <>). It is necessary to comment this line
#       in addition to defining the exported variable. This is done by prefixing the variable name with a '-'.
#       If this is not done, the resulting sysconfig file may contain syntax errors preventing the correct daemon operations.
my $copyd_config_file = "/etc/sysconfig/dpmcopyd";
my %copyd_config_rules = (
        "ALLOW_COREDUMP" => "allowCoreDump:copyd;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        "DPMCOPYDLOGFILE" => "logfile:copyd;".LINE_FORMAT_SH_VAR,
        #"DPMCOPYD_PORT" => "port:copyd;".LINE_FORMAT_SH_VAR,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
        ##"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
        "RUN_DPMCOPYDAEMON" => "ALWAYS->role_enabled:copyd;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "ULIMIT_N" => "maxOpenFiles:copyd;".LINE_FORMAT_SH_VAR,
        "GLOBUS_THREAD_MODEL" => "globusThreadModel:copyd;".LINE_FORMAT_ENV_VAR,
       );

my $dav_config_file = "/etc/httpd/conf.d/zlcgdm-dav.conf";
my %dav_config_rules = (
        "DiskAnon" =>"DiskAnonUser:dav;".LINE_FORMAT_KEY_VAL,
        "DiskFlags" =>"DiskFlags:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "NSAnon" =>"NSAnonUser:dav;".LINE_FORMAT_KEY_VAL,
        "NSFlags" =>"NSFlags:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "NSMaxReplicas" =>"NSMaxReplicas:dav;".LINE_FORMAT_KEY_VAL,
        "NSRedirectPort" =>"NSRedirectPort:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "NSSecureRedirect" =>"NSSecureRedirect:dav;".LINE_FORMAT_KEY_VAL,
        "NSServer" =>"NSServer:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "NSTrustedDNS" =>"NSTrustedDNs:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "NSType" =>"NSType:dav;".LINE_FORMAT_KEY_VAL,
        "SSLCertificateFile" =>"SSLCertFile:dav;".LINE_FORMAT_KEY_VAL,
        "SSLCertificateKeyFile" =>"SSLCertKey:dav;".LINE_FORMAT_KEY_VAL,
        "SSLCACertificatePath" =>"SSLCACertPath:dav;".LINE_FORMAT_KEY_VAL,
        "SSLCARevocationPath" =>"SSLCARevocationPath:dav;".LINE_FORMAT_KEY_VAL,
        "?SSLCipherSuite" =>"SSLCipherSuite:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "?SSLHonorCipherOrder" =>"SSLHonorCipherOrder:dav;".LINE_FORMAT_KEY_VAL,
        "SSLOptions" =>"SSLOptions:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "SSLProtocol" =>"SSLProtocol:dav;".LINE_FORMAT_KEY_VAL.";".LINE_VALUE_ARRAY,
        "SSLSessionCache" =>"SSLSessionCache:dav;".LINE_FORMAT_KEY_VAL,
        "SSLSessionCacheTimeout" =>"SSLSessionCacheTimeout:dav;".LINE_FORMAT_KEY_VAL,
        "SSLVerifyClient" =>"SSLVerifyClient:dav;".LINE_FORMAT_KEY_VAL,
        "SSLVerifyDepth" =>"SSLVerifyDepth:dav;".LINE_FORMAT_KEY_VAL,
);

my $dpm_config_file = "/etc/sysconfig/dpm";
my %dpm_config_rules = (
      "ALLOW_COREDUMP" => "allowCoreDump:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
      "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
      "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
      "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
      "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
      "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
      "DPMDAEMONLOGFILE" => "logfile:dpm;".LINE_FORMAT_SH_VAR,
      #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
      #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
      #"DPM_PORT" => "port:dpm;".LINE_FORMAT_SH_VAR,
      "DPM_USE_SYNCGET" => "useSyncGet:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
      "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
      "NB_FTHREADS" => "fastThreads:dpm;".LINE_FORMAT_SH_VAR,
      "NB_STHREADS" => "slowThreads:dpm;".LINE_FORMAT_SH_VAR,
      "RUN_DPMDAEMON" => "ALWAYS->role_enabled:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
      "ULIMIT_N" => "maxOpenFiles:dpm;".LINE_FORMAT_SH_VAR,
      "GLOBUS_THREAD_MODEL" => "globusThreadModel:dpm;".LINE_FORMAT_ENV_VAR,
           );

my $dpns_config_file = "/etc/sysconfig/dpnsdaemon";
my %dpns_config_rules = (
       "ALLOW_COREDUMP" => "allowCoreDump:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
       "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
       "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
       "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
       "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
       #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
       #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
       "DPNSDAEMONLOGFILE" => "logfile:dpns;".LINE_FORMAT_SH_VAR,
       #"DPNS_PORT" => "port:dpns;".LINE_FORMAT_SH_VAR,
       "NB_THREADS" => "threads:dpns;".LINE_FORMAT_SH_VAR,
       "NSCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
       "RUN_DPNSDAEMON" => "ALWAYS->role_enabled:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
       "RUN_READONLY" => "readonly:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
       "ULIMIT_N" => "maxOpenFiles:dpns;".LINE_FORMAT_SH_VAR,
       "GLOBUS_THREAD_MODEL" => "globusThreadModel:dpns;".LINE_FORMAT_ENV_VAR,
      );

my $gsiftp_config_file = "/etc/sysconfig/dpm-gsiftp";
my %gsiftp_config_rules = (
         "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
         "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
         "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
         "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
         "FTPLOGFILE" => "logfile:gsiftp;".LINE_FORMAT_SH_VAR,
         "GLOBUS_TCP_PORT_RANGE" => "portRange:gsiftp;".LINE_FORMAT_SH_VAR,
         "OPTIONS" => "startupOptions:gsiftp;".LINE_FORMAT_SH_VAR,
         "RUN_DPMFTP" => "ALWAYS->role_enabled:gsiftp;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        );

my $rfio_config_file = "/etc/sysconfig/rfiod";
my %rfio_config_rules = (
       "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
       "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
       "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
       "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
       "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
       "OPTIONS" => "startupOptions:rfio;".LINE_FORMAT_SH_VAR,
       "RFIOLOGFILE" => "logfile:rfio;".LINE_FORMAT_SH_VAR,
       "RFIO_PORT_RANGE" => "portRange:rfio;".LINE_FORMAT_SH_VAR,
       "RUN_RFIOD" => "ALWAYS->role_enabled:rfio;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
       "ULIMIT_N" => "maxOpenFiles:rfio;".LINE_FORMAT_SH_VAR,
       );

my $srmv1_config_file = "/etc/sysconfig/srmv1";
my %srmv1_config_rules = (
        "ALLOW_COREDUMP" => "allowCoreDump:srmv1;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
        #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
        "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
        "RUN_SRMV1DAEMON" => "ALWAYS->role_enabled:srmv1;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "SRMV1DAEMONLOGFILE" => "logfile:srmv1;".LINE_FORMAT_SH_VAR,
        #"SRMV1_PORT" => "port:srmv1;".LINE_FORMAT_SH_VAR,
        "ULIMIT_N" => "maxOpenFiles:srmv1;".LINE_FORMAT_SH_VAR,
        "GLOBUS_THREAD_MODEL" => "globusThreadModel:srmv1;".LINE_FORMAT_ENV_VAR,
       );

my $srmv2_config_file = "/etc/sysconfig/srmv2";
my %srmv2_config_rules = (
        "ALLOW_COREDUMP" => "allowCoreDump:srmv2;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
        #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
        "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
        "RUN_SRMV2DAEMON" => "ALWAYS->role_enabled:srmv2;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "SRMV2DAEMONLOGFILE" => "logfile:srmv2;".LINE_FORMAT_SH_VAR,
        #"SRMV2_PORT" => "port:srmv2;".LINE_FORMAT_SH_VAR,
        "ULIMIT_N" => "maxOpenFiles:srmv2;".LINE_FORMAT_SH_VAR,
        "GLOBUS_THREAD_MODEL" => "globusThreadModel:srmv2;".LINE_FORMAT_ENV_VAR,
       );

my $srmv22_config_file = "/etc/sysconfig/srmv2.2";
my %srmv22_config_rules = (
        "ALLOW_COREDUMP" => "allowCoreDump:srmv22;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "DPMCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        #"DPMGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
        #"DPMUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
        "-DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPM_HOST" => "hostlist:dpm;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "-DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_ARRAY,
        "DPNS_HOST" => "hostlist:dpns;".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
        "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_SH_VAR,
        "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
        "NB_THREADS" => "threads:srmv22;".LINE_FORMAT_SH_VAR,
        "RUN_SRMV2DAEMON" => "ALWAYS->role_enabled:srmv22;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
        "SRMV22DAEMONLOGFILE" => "logfile:srmv22;".LINE_FORMAT_SH_VAR,
        #"SRMV2_2_PORT" => "port:srmv22;".LINE_FORMAT_SH_VAR,
        "ULIMIT_N" => "maxOpenFiles:srmv22;".LINE_FORMAT_SH_VAR,
        "GLOBUS_THREAD_MODEL" => "globusThreadModel:srmv22;".LINE_FORMAT_ENV_VAR,
       );

my $trust_roles = "dpm,dpns,rfio,gsiftp";
my $trust_config_file = "/etc/shift.conf";
my %trust_config_rules = (
        "DPM PROTOCOLS" => "accessProtocols:GLOBAL;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY,
        "DPM TRUST" => "dpm->hostlist:dpns,xroot;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "DPNS TRUST" => "dpns->hostlist:dpm,srmv1,srmv2,srmv22,rfio;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "RFIOD TRUST" => "rfio->hostlist:dpm,rfio;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "RFIOD WTRUST" => "rfio->hostlist:dpm,rfio;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "RFIOD RTRUST" => "rfio->hostlist:dpm,rfio;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "RFIOD XTRUST" => "rfio->hostlist:dpm,rfio;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "RFIOD FTRUST" => "rfio->hostlist:dpm,rfio;".LINE_FORMAT_KEY_VAL.';'.LINE_VALUE_ARRAY.':'.LINE_VALUE_OPT_UNIQUE,
        "RFIO DAEMONV3_WRMT 1" => ";".LINE_FORMAT_KEY_VAL,
        "DPM REQCLEAN" => "dpm->requestMaxAge:dpm;".LINE_FORMAT_KEY_VAL,
       );

my $lfc_config_file = "/etc/sysconfig/lfcdaemon";
my %lfc_config_rules = (
      "LFCDAEMONLOGFILE" => "logfile:lfc",
      #"LFCGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
      #"LFC_PORT" => "port:lfc;".LINE_FORMAT_ENV_VAR,
      #"LFCUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
      "NB_THREADS" => "threads:lfc;".LINE_FORMAT_SH_VAR,
      "NSCONFIGFILE" => "dbconfigfile:GLOBAL;".LINE_FORMAT_SH_VAR,
      "RUN_DISABLEAUTOVIDS" => "disableAutoVirtualIDs:lfc;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
      "RUN_LFCDAEMON" => "ALWAYS->role_enabled:lfc;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
      "RUN_READONLY" => "readonly:lfc;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
      "ULIMIT_N" => "maxOpenFiles:lfc;".LINE_FORMAT_SH_VAR,
           );

my $lfcdli_config_file = "/etc/sysconfig/lfc-dli";
my %lfcdli_config_rules = (
         "DLIDAEMONLOGFILE" => "logfile:lfc-dli",
         #"DLI_PORT" => "port:lfc-dli;".LINE_FORMAT_ENV_VAR,
         "GRIDMAP" => "gridmapfile:GLOBAL;".LINE_FORMAT_SH_VAR,
         "GRIDMAPDIR" => "gridmapdir:GLOBAL;".LINE_FORMAT_SH_VAR,
         #"LFCGROUP" => "group:GLOBAL;".LINE_FORMAT_SH_VAR,
         "LFC_HOST" => "hostlist:lfc".LINE_FORMAT_ENV_VAR.";".LINE_VALUE_ARRAY,
         #"LFCUSER" => "user:GLOBAL;".LINE_FORMAT_SH_VAR,
         "RUN_DLIDAEMON" => "ALWAYS->role_enabled:lfc-dli;".LINE_FORMAT_SH_VAR.";".LINE_VALUE_BOOLEAN,
         "ULIMIT_N" => "maxOpenFiles:lfc-dli;".LINE_FORMAT_SH_VAR,
        );

my %config_files = (
        "copyd" => \$copyd_config_file,
        "dav" => \$dav_config_file,
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
        "dav" => \%dav_config_rules,
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
    "dav" => "httpd",
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
Readonly my $GIP2_USER_PAN_PATH => "/software/components/gip2/user";

my @products = ("DPM", "LFC");

my $this_host_full;
my $this_host_domain;

# Global variables to store component configuration
my $config_options;

# Global context variables used by functions
my $dm_install_root;
my $dm_bin_dir;

# dpmlfc configuration
my $dpmlfc_config;

# Product (DPM or LFC) processed
my $product;

# List of services enabled/to restart on the current node
my $enabled_service_list;
my $service_restart_list;

# GIP user
my $gip_user;

##########################################################################
sub Configure {
##########################################################################
    
  my ( $self, $config) = @_;
  
  my $current_node_fqdn = join ".", hostname(), hostdomain();

  return $self->configureNode($current_node_fqdn, $config);
}


##########################################################################
# Do the real work here: the only reason for this method is to allow
# testing by mocking the hostname.
#
# Arguments
#     host_fqdn: FQDN of the host to configure
#     profile: host profile (this component needs more than dpmlfc config)
sub configureNode {
##########################################################################
    
  my ( $self, $host_fqdn, $profile) = @_;
  unless ( $host_fqdn && $profile ) {
    $self->error("configureNode: missing argument (internal error)");
    return (2);
  }

  $this_host_full = $host_fqdn;
  (my $this_host_name, $this_host_domain) = split /\./, $this_host_full, 2;

  $dpmlfc_config = $profile->getElement($self->prefix())->getTree();
  if ( $profile->elementExists($GIP2_USER_PAN_PATH) ) {
    $gip_user = $profile->getElement($GIP2_USER_PAN_PATH)->getValue();
  }

  # Process separatly DPM and LFC configuration
  
  my $comp_max_servers;
  for my $p (@products) {
    $product = $p;
    $self->debug(1,"Processing configuration for $product");

    $dm_install_root = $self->getGlobalOption("installDir");
    unless ( defined($dm_install_root) ) {
      $dm_install_root = $dm_install_root_default;
    }
    $config_options->{installDir} = $dm_install_root;
    if ((length($dm_install_root) == 0) || ($dm_install_root eq "/")) {
      $dm_install_root = "";
      $dm_bin_dir = "/usr/bin";
    } else {
      $dm_bin_dir = $dm_install_root . "/bin";      
    }
    
    my $hosts_roles;
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
      if ( exists($dpmlfc_config->{$role}) ) {
        $product_configured = 1; 
        last;  
      }
    }
    if ( ! $product_configured ) {
      $self->debug(1,"Product $product not configured: skipping its configuration");
      next;  
    }

    # Initialize options hash for the current product.
    # Options hash contains global options and one sub-hash for each role.
    # Sub-hash for each contains the options for the current host and the role host list.
    # Do it after validating that the current product is configured to keep the previous
    # values accessible (unit tests).

    $config_options = {};
    $enabled_service_list = {};
    $service_restart_list = {};

    # Retrieve some general options
    # Don't define 'user' global option with a default value to keep it
    # undefined during rules processing

    if ( defined($self->getGlobalOption("user")) ) {
      $config_options->{user} = $self->getGlobalOption("user");
    }
    if ( defined($self->getGlobalOption("group")) ) {
      $config_options->{group} = $self->getGlobalOption("group");
    }
    if ( defined($self->getGlobalOption("gridmapfile")) ) {
      $config_options->{gridmapfile} = $self->getGlobalOption("gridmapfile");
    }
    if ( defined($self->getGlobalOption("gridmapdir")) ) {
      $config_options->{gridmapdir} = $self->getGlobalOption("gridmapdir");
    }
    if ( defined($self->getGlobalOption("accessProtocols")) ) {
      $config_options->{accessProtocols} = $self->getGlobalOption("accessProtocols");
    }
    if ( defined($self->getGlobalOption("controlProtocols")) ) {
      $config_options->{controlProtocols} = $self->getGlobalOption("controlProtocols");
    }
    if ( my $v = $self->getDbOption('configfile') ) {
      $config_options->{dbconfigfile} = $v;
      $self->debug(1,"Global option 'dbconfigfile' defined to ".$config_options->{dbconfigfile});
    } else {
      $config_options->{dbconfigfile} = $db_conn_config{$product};
      $self->debug(1,"Global option 'dbconfigfile' set to default : ".$config_options->{dbconfigfile});
    }


    # At least $dpmlfc_config->{dpm} or $dpmlfc_config->{lfc} must exist

    my @actual_hosts_roles;
    my $role_host_list = {};
    for my $role (@$hosts_roles) {
      # By default, assume this role is disabled on local host.
      # Temporarily, define the option in global options.
      $config_options->{$role."_service_enabled"} = 0;
      if ( exists($dpmlfc_config->{$role}) ) {
        push @actual_hosts_roles, $role;
        my $servers = $dpmlfc_config->{$role};
        if ( keys(%{$servers}) <= ${$comp_max_servers}{$role} ) {
          my $def_host;
          for my $role_host (keys(%{$servers})) {
            if ( ($role eq "dpm") || ($role eq "lfc") ) {
              if ( $role eq "lfc" ){
                if ( exists($dpmlfc_config->{"dpns"}) ) {
                  $self->error("LFC server and DPNS server cannot be run on the same node. Skipping LFC configuration.");
                  return 0;
                }
              }
            }
            $role_host_list->{$role}->{$role_host} = '';            
            if ( $role_host eq $this_host_full ) {
              $config_options->{$role."_service_enabled"} = 1;
            }
          }
        } else {
          $self->error("Too many ".uc($role)." servers (maximum=${$comp_max_servers}{$role})");
          return 0;
        }
      }
    }

    # Retrieve from profile configuration about roles.
    # For each role retrieve the role configuration for this host if it is in the role list,
    # else the information from the first host in the list. Then apply all the related
    # protocol options as default values for non specified host specific options.
    # In addition, add role host list and copy the role enabled info from global options to 
    # the role options.
    for my $role (@$hosts_roles) {
      if ( grep(/^$role$/,@actual_hosts_roles) ) {
        my @role_hosts = sort(keys(%{$role_host_list->{$role}}));
        if ( @role_hosts ) {
          # Use first host with  this role if current host is not enabled for
          # the role. Not really sensible to refer a host specific configuration
          # for a role not executed on the local host.
          my $h;
          if ( exists($dpmlfc_config->{$role}->{$this_host_full}) ) {
            $h = $this_host_full;
            $self->debug(2,"Host $this_host_full supporting role $role: using its configuration");
          } else {              
            $h = $role_hosts[0];
            $self->debug(2,"Host $this_host_full not found in role $role: using configuration from host $h");
          }
          $config_options->{$role} = $self->getHostConfig($role,$h);
          while ( my ($option, $optval) = each(%{$dpmlfc_config->{protocols}->{$role}})) {
            unless ( exists($config_options->{$role}->{$option}) ) {
              $config_options->{$role}->{$option} = $optval;
            }
          }
          $config_options->{$role}->{hostlist} = \@role_hosts;
        } else {
          $self->error("Internal error: no host with role ".uc($role)." found");
        }
      }
      $config_options->{$role}->{role_enabled} = $config_options->{$role.'_service_enabled'};
      delete $config_options->{$role.'_service_enabled'};
      $self->debug(3,"Keys in $role options: ".join(",",keys(%{$config_options->{$role}})));
    }
    $self->debug(3,"Keys in config_options: ".join(",",keys(%{$config_options})));

    # Update configuration files for every configured role.
    # xroot is a special case as it is managed by a separate component, ncm-xrootd.
    for my $role (@{$hosts_roles}) {
      if ( $role ne 'xroot' ) {
        if ( $self->hostHasRoles($role) ) {
          $self->info("Checking configuration for ".$role);
          $self->updateRoleConfig($role,$config_options);
          for my $service ($self->getRoleServices($role)) {
            $self->enableService($service);
          }
        } else {
          $self->info("Checking that role ".$role." is disabled...");        
          $self->updateRoleConfig($role,$config_options);
        }
      }
    }

    if ( $product eq "DPM" ) {
      $config_options->{trusts}->{role_enabled} = 1;
      $self->updateRoleConfig("trusts",$config_options) if $self->hostHasRoles($trust_roles);
    }

    # Build init script to control all enabled services
    $self->buildEnabledServiceInitScript();

    # Do necessary DB initializations (only if current host has one role needing
    # DB access
    if ( $self->hostHasRoles($db_roles{$product}) ) {
      $self->info("Checking ".$product." database configuration...");
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

    # Restart services that need to be (DPM/LFC services are stateless).
    # Don't signal error as it has already been signaled by restartServices().
    if ( $self->restartServices() ) {
      next;
    }
  
  
    # If product is DPM and current node is DPNS server or if product is LFC and
    # this node runs lfc daemon, do namespace configuration for VOs
    if ( $self->hostHasRoles($nameserver_role{$product}) ) {
      $self->info("Checking namespace configuration for supported VOs...");
      $self->NSRootConfig();
      if ( exists($dpmlfc_config->{vos}) ) {
        my $vos = $dpmlfc_config->{vos};
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
  
  
    # If the current node is a DPM server (running dpm daemon) and pool configuration
    # is present in the profile, configure pools.
    if ( ($product eq 'DPM') && $self->hostHasRoles('dpm') ) {
      if ( exists($dpmlfc_config->{pools}) ) {
        my $pools = $dpmlfc_config->{pools};
        for my $pool (sort(keys(%$pools))) {
          my $pool_args = %{$pools->{$pool}};
          $self->DPMConfigurePool($pool,$pool_args);
        }
      }
    }

  }

  return 0;
}


# Function to configure DPM pools
# Returns 0 if the pool already exists or has been configured successfully, else error code of 
# the failed command.
# No attempt is made to modify an existing pool.
sub DPMConfigurePool {
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
  my $pool_args;
  if ( @_ > 0 ) {
    $pool_args = shift;
  } else {
    $self->error("$function_name: pool properties argument missing.");
    return (1);
  }
    
  $self->info('Pool configuration not yet implemented');
  
  return($status);
}

# Function to check if a directory already exists in namespace
# Returns 0 if the directory already exists, -1 if not, error code
# if namespace command returned another error.

sub NSCheckDir {
  my $function_name = "NSCheckDir";
  my $self = shift;
  my $directory;
  if ( @_ > 0 ) {
    $directory = shift;
  } else {
    $self->error("$function_name: directory argument missing.");
    return (1);
  }
  
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

sub NSRootConfig {
  my $function_name = "NSRootConfig";
  my $self = shift;
  my $status = 0;
  
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
      $self->debug(1,"$function_name: $path missing (internal error)");
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

sub NSConfigureVO {
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
    
  my $vo_home = $self->NSGetRoot().'/'.$vo_name;

  $self->debug(1,"$function_name: checking VO $vo_name NS configuration ($vo_home) for $product");

  # Check if VO home already exists. Create and configure it if not.

  if ( $self->NSCheckDir($vo_home) ) {
    $self->debug(1,"$function_name: $vo_home missing (internal error)");

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
sub NSGetRoot {
  my $function_name = "NSGetRoot";
  my $self = shift;
  
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

sub execNSCmd {
  my $function_name = "execNSCmd";
  my $self = shift;
  my $ns_cmd;
  if ( @_ > 0 ) {
    $ns_cmd = shift;
  } else {
    $self->error("$function_name: command argument missing.");
    return (1);
  }
  
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

sub execCmd {
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


# Function returning the host FQDN.
# localhost is handled as a special case where no domain should be added.
#
# Arguments :
#  host : a host name
sub hostFQDN {
  my $function_name = "hostFQDN";
  my $self = shift;
  
  my $host = shift;
  unless ( $host ) {
    $self->error("$function_name: 'host' argument missing (internal error)");
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
sub checkSecurity {
  my $function_name = "checkSecurity";
  my $self = shift;

  $self->info("Checking host certificate and key configuration for $product");

  my $daemon_group = $self->getDaemonGroup();
  my $daemon_user = $self->getDaemonUser();
  my $changes;

  # GRIDMAPDIR must be writable by group used by product daemons
  my $gridmapdir = $self->getGlobalOption("gridmapdir");
  unless ( $gridmapdir ) {
    $gridmapdir = $gridmapdir_def;
  }
  if ( -d $gridmapdir || $CAF::Object::NoAction ) {
    $self->debug(1,"$function_name: Checking permission on $gridmapdir");
    unless ( $CAF::Object::NoAction ) {
      $changes = LC::Check::status($gridmapdir,
                                   group => $daemon_group,
                                   mode => 01774
                                  );
      unless (defined($changes)) {
        $self->error("error setting $gridmapdir for $product");
      }
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

  unless ( $CAF::Object::NoAction ) {
    $self->debug(1,"$function_name: Checking existence and permission of $daemon_security_dir");
    $changes = LC::Check::directory($daemon_security_dir);
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
  };

  $self->debug(1,"$function_name: Copying host certificate ($hostcert) and key ($hostkey) to $daemon_security_dir");
  my $daemon_hostkey .= $daemon_security_dir."/".lc($product)."key.pem";
  my $daemon_hostcert .= $daemon_security_dir."/".lc($product)."cert.pem";
  my $key_src = CAF::FileReader->new($host_hostkey);
  my $cert_src = CAF::FileReader->new($host_hostcert);
  unless ( $key_src && $cert_src) {
    $self->error("Host key ($host_hostkey) not found. Check your configuration") unless $key_src;
    $self->error("Host certificate ($host_hostcert) not found. Check your configuration") unless $cert_src;
    return 1
  }
  my $key_fh = CAF::FileWriter->new($daemon_hostkey,
                                    owner => $daemon_user,
                                    group => $daemon_group,
                                    mode => 0400,
                                   );
  print $key_fh "$key_src";
  $key_src->close();
  $changes = $key_fh->close();
  unless (defined($changes)) {
    $self->error("error creating $hostkey copy for $product");
  }

  my $cert_fh = CAF::FileWriter->new($daemon_hostcert,
                                     owner => $daemon_user,
                                     group => $daemon_group,
                                     mode => 0644,
                                    );
  print $cert_fh "$cert_src";
  $cert_src->close();
  $changes = $cert_fh->close();
  unless (defined($changes)) {
    $self->error("error creating $hostcert copy for $product");
  }

}


# Function to return a global option value from configuration
# Arguments :
#  option : option name
sub getGlobalOption {
  my $function_name = "getGlobalOption";
  my $self = shift;

  my $option = shift;
  unless ( $option ) {
    $self->error("$function_name: 'option' argument missing (internal error)");
    return 0;
  }

  if ( exists($dpmlfc_config->{options}->{lc($product)}->{$option}) ) {
    my $value = $dpmlfc_config->{options}->{lc($product)}->{$option};
    $self->debug(2,"$function_name: Global option '$option' found : ".$value);
    return $value;
  } else {
    $self->debug(2,"$function_name: Global option '$option' not found : ");    
    return undef;
  }


}


# Function to retrieve a DB option value from configuration
# Arguments :
#  option : option name
sub getDbOption {
  my $function_name = "getDbOption";
  my $self = shift;

  my $option = shift;
  unless ( $option ) {
    $self->error("$function_name: 'option' argument missing (internal error)");
    return 0;
  }

  if ( exists($dpmlfc_config->{options}->{lc($product)}->{db}->{$option}) ) {
    return $dpmlfc_config->{options}->{lc($product)}->{db}->{$option};
  } else {
    $self->debug(1,"$function_name: DB option '$option' not found for product $product");
    return undef;
  }

}


# Function returning the userid used by product daemons
# Default : as specified in %users_def
#
# Arguments : 
#  none
sub getDaemonUser {
  my $function_name = "getDaemonUser";
  my $self = shift;

  my $daemon_user = $config_options->{"user"};
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
sub getDaemonGroup {
  my $function_name = "getDaemonGroup";
  my $self = shift;

  my $daemon_group = $config_options->{"group"};
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
sub getDbAdminServer {
  my $function_name = "getDbAdminServer";
  my $self = shift;

  my $db_admin_server = $config_options->{"dbserver"};
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
sub createDbConfigFile {
  my $function_name = "createDbConfigFile";
  my $self = shift;

  $self->debug(1,"$function_name: Creating database configuration file for $product");

  unless ( exists($dpmlfc_config->{options}->{lc($product)}->{db}) ) {
    $self->warn("Cannot configure DB connection : configuration missing in profile");
    return 1;
  }

  my $do_db_config = 1;

  # Owner and mode of the DB configuration file
  my $daemon_user = $self->getDaemonUser();
  my $daemon_group = $self->getDaemonGroup();
  my $dbconfigmode = $self->getDbOption('configmode');
  if ( $dbconfigmode ) {
    $self->debug(1,"Global option 'dbconfigmode' defined to ".$dbconfigmode);
  } else {
    $dbconfigmode = $db_conn_config_mode{$product};
    $self->debug(1,"Global option 'dbconfigmode' set to default : ".$dbconfigmode);
  }

  my $db_user = $self->getDbOption("user");
  unless ( $db_user ) {
    $self->warn("Cannot configure DB connection : DB username missing (internal error)");
    return 1; 
  }
  $config_options->{"dbuser"} = $db_user;

  my $db_pwd = $self->getDbOption("password");
  unless ( $db_pwd ) {
    $self->warn("Cannot configure DB connection : DB password missing (internal error)");
    return 1;
  }
  $config_options->{"dbpwd"} = $db_pwd;

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
  $config_options->{"dbserver"} = $db_server;


  # info_user is the MySQL user used by GIP to collect DPM statistics.
  # Configure only if GIP is configured on the machine.
  my $db_info_user;
  my $db_info_pwd;
  my $db_info_file;
  if ( $gip_user ) {
    $db_info_user = $self->getDbOption("infoUser");
    if ( $db_info_user ) {
      $config_options->{"dbinfouser"} = $db_info_user;
      $db_info_pwd = $self->getDbOption("infoPwd");
      if ( $db_info_pwd ) {
        $config_options->{"dbinfopwd"} = $db_info_pwd;
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
    $self->debug(1,"GIP not configured on this node. Skipping $product DB configuration for GIP.");
  }

  # Update DB connection configuration file for main user if content has changed
  my $config_contents = "$db_user/$db_pwd\@$db_server";
  my $config_fh = CAF::FileWriter->new($config_options->{"dbconfigfile"}.$config_prod_ext,
                                       backup => $config_bck_ext,
                                       owner => $daemon_user,
                                       group => $daemon_group,
                                       mode => oct($dbconfigmode),
                                       log => $self,
                                      );
  print $config_fh "$db_user/$db_pwd\@$db_server\n";
  my $changes = $config_fh->close();


  # Update DB connection configuration file for information user if content has changed
  # No service needs to be restarted.
  if ( $db_info_user ) {
    my $info_fh = CAF::FileWriter->new($db_info_file.$config_prod_ext,
                                       backup => $config_bck_ext,
                                       owner => $gip_user,
                                       group => $daemon_group,
                                       mode => oct($dbconfigmode),
                                       log => $self,
                                      );
    print $info_fh "$db_info_user/$db_info_pwd\@$db_server\n";
    my $info_changes = $info_fh->close();
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
sub getRoleServices {
  my $function_name = "getRoleServices";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing (internal error)");
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
sub serviceRestartNeeded {
  my $function_name = "serviceRestartNeeded";
  my $self = shift;

  my $roles = shift;
  unless ( $roles ) {
    $self->error("$function_name: 'roles' argument missing (internal error)");
    return 0;
  }

  my @roles = split /\s*,\s*/, $roles;
  for my $role (@roles) {
    $self->debug(2,"$function_name: marking role '$role' services for restart");
    for my $service ($self->getRoleServices($role)) {
      unless ( exists($service_restart_list->{$service}) ) {
        $self->debug(1,"$function_name: adding '$service' to the list of services needed to be restarted");
        $service_restart_list->{$service} = 1;      # Value is useless
      }
    }
  }

  $self->getServiceRestartList();
}


# Return the list of services to be restarted as a space-separated list.
# For unit testing mainly.
#
# Arguments: None
#
# Return value: string containing the sorted list of services to be restarted
sub getServiceRestartList {
  my $function_name = "getServiceRestartList";
  my $self = shift;

  my $service_list = join(" ",sort(keys(%$service_restart_list)));
  $self->debug(2,"$function_name: restart list = '$service_list'");
  return $service_list;
}

# Enable a service to be started during system startup
#
# Arguments :
#  service : name of the service
sub enableService {
  my $function_name = "enableService";
  my $self = shift;

  my $service = shift;
  unless ( $service ) {
    $self->error("$function_name: 'service' argument missing (internal error)");
    return 0;
  }

  $self->debug(1,"$function_name: checking if service $service is enabled");

  unless ( -f "/etc/rc.d/init.d/$service" || $CAF::Object::NoAction ) {
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
  } elsif ( ! $CAF::Object::NoAction ) {
    $self->debug(2,"$function_name: $service already enabled");
  }

  $enabled_service_list->{$service} = 1;     # Value is useless

}


# Generate an init script to control (start/stop/restart) all enabled services.

sub buildEnabledServiceInitScript {
  my $function_name = "buildEnabledServiceInitScript";
  my $self = shift;

  my $init_script_name = '/etc/init.d/'.lc($product).'-all-daemons';
  my $contents;

  # Don't do anything if the list is empty
  if ( %$enabled_service_list ) {
    $self->info("Checking init script used to control all ".$product." enabled services (".$init_script_name.")...");
    $contents = "#!/bin/sh\n\n";
    for my $service (sort(keys(%$enabled_service_list))) {
      if ( $enabled_service_list->{$service} ) {
        $contents .= "/etc/init.d/".$service." \$*\n";
      }
    }
    
    my $fh = CAF::FileWriter->new($init_script_name,
                                  owner => 'root',
                                  group => 'root',
                                  mode => 0755,
                                  log => $self,
                                 );
    print $fh $contents;
    if ( $fh->close() < 0 ) {
      $self->warn("Error creating init script to control all ".$product." services ($init_script_name)");
    }
  } else {
    $self->debug(1,"$function_name: no service enabled for ".$product.' ('.$init_script_name.')');
  }
}


# Restart services needed to be restarted
# Returns 0 if all services have been restarted successfully, else
# the number of services which failed to restart.

sub restartServices {
  my $function_name = "RestartServices";
  my $self = shift;
  my $global_status = 0;
  
  $self->debug(1,"$function_name: restarting services affected by configuration changes");

  # Need to do stop+start as sometimes dpm daemon doesn't restart properly with
  # 'restart'. Try to restart even if stop failed (can be just the daemon is 
  # already stopped)
  if ( %$service_restart_list ) {
    $self->debug(1,"$function_name: list of services to restart : ".join(" ",keys(%$service_restart_list)));
    for my $service (keys %$service_restart_list) {
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


# This function returns true if the current machine is listed in the hosts list
# for one of the roles passed as argument.
#
# Arguments
#       roles : comma separated roles list. 
sub hostHasRoles {
  my $function_name = "hostHasRoles";
  my $self = shift;

  my $roles = shift;
  unless ( $roles ) {
    $self->error("$function_name: 'roles' argument missing (internal error)");
    return 0;
  }

  my $role_found = 0;    # Assume host doesn't have any role
  my @roles = split /\s*,\s*/, $roles;

  for my $role (@roles) {
    $self->debug(2,"$function_name: checking for role >>>$role<<< on host >>>$this_host_full<<<");
    if ( exists($config_options->{$role}) ) {
      if ( grep(/^$this_host_full$/,@{$config_options->{$role}->{hostlist}}) ) {
        $self->debug(1,"$function_name: role $role found on host $this_host_full");
        $role_found = 1;
        last;        
      } else {
        $self->debug(1,"$function_name: role $role NOT found on host $this_host_full");    
      }
    } else {
      $self->error("$function_name: role $role not defined in configuration");
    }
  }
  return $role_found;
}


# This function returns host config.
#
# Arguments
#       role : role for which the hosts list must be normalized
#       host : host for which configuration must be returned
sub getHostConfig {
  my $function_name = "getHostConfig";
  my $self = shift;

  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing (internal error)");
    return 1;
  }
  my $host = shift;
  unless ( $host ) {
    $self->error("$function_name: 'host' argument missing (internal error)");
    return 1;
  }

  if ( exists($dpmlfc_config->{$role}) && exists($dpmlfc_config->{$role}->{$host}) ) {
    $self->debug(3,"$function_name: keys in $role options: ".join(",",keys(%{$dpmlfc_config->{$role}->{$host}})));
    return $dpmlfc_config->{$role}->{$host};
  } else {
    $self->verbose("$function_name: host '$host' not found in role '$role' options: returning an empty option set");
    return {};
  }
}


# Update a role configuration file, applying the appropriate configuration rules.
# This function retrieves the config file associated with role and then calls
# updateConfigFile() to actually do the update. It flags the service associated
# with the role for restart if the config file was changed.
#
# Arguments :
#       role: role a configuration file must be build for
#       config: hash containing the global options and the configuration of roles
sub updateRoleConfig {
  my $function_name = "updateRoleConfig";
  my $self = shift;
 
  my $role = shift;
  unless ( $role ) {
    $self->error("$function_name: 'role' argument missing (internal error)");
    return 1;
  }
 
  my $config = shift;
  unless ( $config ) {
    $self->error("$function_name: 'config' argument missing (internal error)");
    return 1;
  }
 
  # Check if the role is enabled on local host: if not, set flag to apply only ALWAYS rules
  my %parser_options;
  $parser_options{always_rules_only} = ! (exists($config->{$role}) && $config->{$role}->{role_enabled});
 
  $self->debug(1,"$function_name: building configuration file for role ".uc($role)." (".${$config_files{$role}}.")");
 
  my $changes = 0;
  my $fh = CAF::RuleBasedEditor->new(${$config_files{$role}}, log => $self);
  if ( defined($fh) ) {
    unless ( $fh->updateFile($config_rules{$role}, $config, \%parser_options) ) {
      $self->error("Error updating ".${$config_files{$role}});
    }
    $changes = $fh->close();
  } else {
      $self->error("Error opening ".${$config_files{$role}});
  }
 
  # Keep track of services that need to be restarted if changes have been made
  if ( $changes > 0 ) {
    $self->serviceRestartNeeded($role);
  }
}


##########################################################################
# This is a helper function returning the appropriate rule based on the
# dpmlfc service.
# This function is mainly to help with unit testing (get rules).
sub getRules {
##########################################################################

  my ( $self, $service) = @_;

  unless ( $config_rules{$service} ) {
    $self->error("Internal error: invalid service '$service)");
    return;
  }

  return $config_rules{$service};

}


1;      # Required for PERL modules
