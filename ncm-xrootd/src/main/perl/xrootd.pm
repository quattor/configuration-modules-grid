# $license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
#
#
# This component is dedicated to Xrootd configuration management. It hs been designed
# to be very flexible and need no major change to handle changes in
# configuration file format, by using parsing rules to update the contents
# of configuration files. Original version is strongly based on ncm-dpmlfc,
# used to manage DPM/LFC.
#
# Configuration files are modified only if their contents need to be changed,
# not at every run of the component. In case of changes, the services depending
# on the modified files are restared.
#
# Adding support for a new configuration variable should be pretty easy.
# Basically, if this is a role specific variable, you just need add a
# parsing rule that use it in the %xxx_config_rules
# for the configuration file.
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
our $EC = LC::Exception::Context->new->will_store_all;

our @EXPORT = qw( $XROOTD_SYSCONFIG_FILE );
use Readonly;

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
use CAF::RuleBasedEditor qw(:rule_constants);

use Encode qw(encode_utf8);
use Fcntl qw(SEEK_SET);

local (*DTA);

use Net::Domain qw(hostname hostfqdn hostdomain);


# Define paths for convenience.
use constant XROOTD_INSTALL_ROOT_DEFAULT => "";

# Define some commands explicitly
use constant SERVICECMD => "/sbin/service";

# Backup file extension
Readonly my $BACKUP_FILE_EXT => '.old';

# Role names used here must be the same as key in other hashes.
my @xrootd_roles = (
                    "disk",
                    "redir",
                    "fedredir",
                   );
# Following hash define the maximum supported servers for each role
my %role_max_servers = (
                        "disk"     => 1,
                        "redir"    => 1,
                        "fedredir" => 999,
                       );


# Following hashes define parsing rules to build a configuration.
# Hash key is the line keyword in configuration file and
# hash value is the parsing rule for the keyword value. Parsing rule format is :
#       [condition->]option_name:option_set[,option_set,...];line_fmt[;value_fmt]
#
# If the line keyword (hash key) is starting with a '-', this means that the matching
# configuration line must be removed/commented out (instead of added/updated) from the
# configuration file if present.
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

Readonly our $XROOTD_SYSCONFIG_FILE => "/etc/sysconfig/xrootd";
my %xrootd_sysconfig_rules = (
    "CMSD_INSTANCES"              => "cmsdInstances:GLOBAL;" . LINE_FORMAT_SH_VAR . ";" . LINE_VALUE_HASH_KEYS,
    "CMSD_%%INSTANCE%%_OPTIONS"   => "cmsdInstances:GLOBAL;" . LINE_FORMAT_SH_VAR . ";" . LINE_VALUE_INSTANCE_PARAMS,
    "DAEMON_COREFILE_LIMIT"       => "coreMaxSize:dpm;" . LINE_FORMAT_SH_VAR,
    "DPM_HOST"                    => "dpmHost:dpm;" . LINE_FORMAT_SH_VAR,
    "DPMXRD_ALTERNATE_HOSTNAMES"  => "alternateNames:dpm;" . LINE_FORMAT_SH_VAR,
    "DPNS_HOST"                   => "dpnsHost:dpm;" . LINE_FORMAT_SH_VAR,
    "MALLOC_ARENA_MAX"            => "mallocArenaMax:GLOBAL;" . LINE_FORMAT_SH_VAR,
    "XROOTD_GROUP"                => "daemonGroup:GLOBAL;" . LINE_FORMAT_SH_VAR,
    "XROOTD_INSTANCES"            => "xrootdOrderedInstances:GLOBAL;" . LINE_FORMAT_SH_VAR . ";" . LINE_VALUE_ARRAY,
    "XROOTD_%%INSTANCE%%_OPTIONS" => "xrootdInstances:GLOBAL;" . LINE_FORMAT_SH_VAR . ";" . LINE_VALUE_INSTANCE_PARAMS,
    "XROOTD_USER"                 => "daemonUser:GLOBAL;" . LINE_FORMAT_SH_VAR,
);

my %disk_config_rules = (
    "all.sitename"   => "siteName:GLOBAL;" . LINE_FORMAT_KW_VAL,
    "xrd.report"     => "reportingOptions:GLOBAL;" . LINE_FORMAT_KW_VAL,
    "xrootd.monitor" => "monitoringOptions:GLOBAL;" . LINE_FORMAT_KW_VAL,
                        );

my %redir_config_rules = (
    "all.sitename"          => "siteName:GLOBAL;" . LINE_FORMAT_KW_VAL,
    "dpmhost"               => "dpmHost:dpm;" . LINE_FORMAT_KW_VAL_SET,
    "dpm.defaultprefix"     => "defaultPrefix:dpm;" . LINE_FORMAT_KW_VAL,
    "dpm.fixedidrestrict"   => "authorizedPaths:dpm;" . LINE_FORMAT_KW_VAL . ";" . LINE_VALUE_ARRAY,
    "dpm.fqan"              => "mappedFQANs:dpm;" . LINE_FORMAT_KW_VAL . ";" . LINE_VALUE_ARRAY,
    "dpm.principal"         => "principal:dpm;" . LINE_FORMAT_KW_VAL,
    "dpm.replacementprefix" => "replacementPrefix:dpm;" . LINE_FORMAT_KW_VAL . ";" . LINE_VALUE_HASH,
    "ofs.authlib"           => "authzLibraries:GLOBAL;" . LINE_FORMAT_KW_VAL . ";" . LINE_VALUE_ARRAY,
    "xrd.report"            => "reportingOptions:GLOBAL;" . LINE_FORMAT_KW_VAL,
    "xrootd.monitor"        => "monitoringOptions:GLOBAL;" . LINE_FORMAT_KW_VAL,
    "xrootd.redirect" => "localRedirectParams:GLOBAL;" . LINE_FORMAT_KW_VAL . ";" . LINE_VALUE_ARRAY . ':' . LINE_VALUE_OPT_SINGLE,
    "DPM_CONRETRY"    => "dpmConnectionRetry:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPM_HOST"        => "dpmHost:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPNS_CONRETRY"   => "dpnsConnectionRetry:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPNS_HOST"       => "dpnsHost:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "TTOKENAUTHZ_AUTHORIZATIONFILE" => "authzConf:tokenAuthz;" . LINE_FORMAT_KW_VAL_SETENV,
);

my %fedredir_config_rules = (
    "all.export"            => "validPathPrefix:fedparams;" . LINE_FORMAT_KW_VAL,
    "all.manager"           => "federationCmsdManager:fedparams;" . LINE_FORMAT_KW_VAL,
    "all.sitename"          => "siteName:GLOBAL;" . LINE_FORMAT_KW_VAL,
    "dpm.defaultprefix"     => "!namePrefix:fedparams->defaultPrefix:dpm;" . LINE_FORMAT_KW_VAL,
    "dpm.namelib"           => "n2nLibrary:fedparams;" . LINE_FORMAT_KW_VAL,
    "dpm.namecheck"         => "namePrefix:fedparams;" . LINE_FORMAT_KW_VAL,
    "dpm.replacementprefix" => "!namePrefix:fedparams->replacementPrefix:dpm;" . LINE_FORMAT_KW_VAL . ";" . LINE_VALUE_HASH,
    "pss.origin"            => "localRedirector:fedparams;" . LINE_FORMAT_KW_VAL,
    "xrd.port"              => "localPort:fedparams;" . LINE_FORMAT_KW_VAL,
    "xrd.report"            => "reportingOptions:fedparams;" . LINE_FORMAT_KW_VAL,
    "xrootfedxrdmanager"    => "federationXrdManager:fedparams;" . LINE_FORMAT_KW_VAL_SET,
    "xrootfedcmsdmanager"   => "federationCmsdManager:fedparams;" . LINE_FORMAT_KW_VAL_SET,
    "xrootfedlport"         => "localPort:fedparams;" . LINE_FORMAT_KW_VAL_SET,
    "xrootd.monitor"        => "monitoringOptions:fedparams;" . LINE_FORMAT_KW_VAL,
    "xrootd.redirect"       => "redirectParams:fedparams;" . LINE_FORMAT_KW_VAL,
    "CSEC_MECH"             => "lfcHost:fedparams->lfcSecurityMechanism:fedparams;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPM_CONRETRY"          => "dpmConnectionRetry:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPM_HOST"              => "dpmHost:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPNS_CONRETRY"         => "dpnsConnectionRetry:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "DPNS_HOST"             => "dpnsHost:dpm;" . LINE_FORMAT_KW_VAL_SETENV,
    "LFC_CONRETRY"          => "lfcHost:fedparams->lfcConnectionRetry:fedparams;" . LINE_FORMAT_KW_VAL_SETENV,
    "LFC_HOST"              => "lfcHost:fedparams;" . LINE_FORMAT_KW_VAL_SETENV,
    "X509_USER_PROXY"       => "proxyLocation:fedparams;" . LINE_FORMAT_KW_VAL_SETENV,
);

my %config_rules = (
                    "disk"      => \%disk_config_rules,
                    "redir"     => \%redir_config_rules,
                    "fedredir"  => \%fedredir_config_rules,
                    "sysconfig" => \%xrootd_sysconfig_rules,
                   );

# Global variables to store component configuration
# Global context variables containing used by functions
use constant DM_INSTALL_ROOT => "";

# xroot related global variables
my %xrootd_daemon_prefix = (
                            'head' => '',
                            'disk' => '',
                           );
# xrootd_services is used to track association between a daemon name
# (the key) and its associatated service names (can be a comma separated list).
my %xrootd_services = (
                       'cmsd'   => 'cmsd',
                       'xrootd' => 'xrootd',
                      );


##########################################################################
# This is a helper function returning the appropriate rule based on the
# xrootd node type.
# This function is mainly to help with unit testing (get rules).
sub getRules
{
##########################################################################

    my ($self, $node_type) = @_;

    unless ($config_rules{$node_type}) {
        $self->error("Internal error: invalid node type '$node_type)");
        return;
    }

    return $config_rules{$node_type};

}


##########################################################################
# This is a helper function merging into global options all localRedirect
# paramaters defined in the options for each federation.
# This function is mainly to help with unit testing.
sub mergeLocalRedirects
{
##########################################################################

    my ($self, $options) = @_;

    if ($options->{federations}) {
        $options->{localRedirectParams} = [];
        foreach my $federation (sort keys %{$options->{federations}}) {
            my $params = $options->{federations}->{$federation};
            if (defined($params->{localRedirectParams})) {
                push @{$options->{localRedirectParams}}, $params->{localRedirectParams};
            }
        }
    }
}


##########################################################################
sub Configure
{
##########################################################################

    my ($self, $config) = @_;

    my $this_host_name   = hostname();
    my $this_host_domain = hostdomain();
    my $this_host_full   = join ".", $this_host_name, $this_host_domain;

    my $xrootd_config  = $config->getElement($self->prefix())->getTree();
    my $xrootd_options = $xrootd_config->{options};

    return $self->configureNode($this_host_full, $xrootd_config);
}


##########################################################################
# Do the real work here: the only reason for this method is to allow
# testing by mocking the hostname.
sub configureNode
{
##########################################################################

    my ($self, $this_host_full, $xrootd_config) = @_;
    unless ($this_host_full && $xrootd_config) {
        $self->error("configureNode: missing argument (internal error)");
        return (2);
    }
    my $xrootd_options = $xrootd_config->{options};

    # Process separatly DPM and LFC configuration

    my $comp_max_servers;

    # Check that current node is part of the configuration

    if (!exists($xrootd_config->{hosts}->{$this_host_full})) {
        $self->error("Local host ($this_host_full) is not part of the xrootd configuration");
        return (2);
    }

    # General initializations
    my $xrootd_install_root;
    if (defined($xrootd_options->{installDir})) {
        $xrootd_install_root = $xrootd_options->{installDir};
    } else {
        $xrootd_install_root = XROOTD_INSTALL_ROOT_DEFAULT;
    }
    if ($xrootd_install_root eq '/') {
        $xrootd_install_root = "";
    }
    my $xrootd_bin_dir = $xrootd_install_root . '/usr/bin';

    my $xrootd_config_dir = $xrootd_options->{configDir};
    unless ($xrootd_config_dir =~ /^\s*\//) {
        $xrootd_config_dir = $xrootd_install_root . '/etc/' . $xrootd_config_dir;
    }
    if (defined($xrootd_options->{config})) {
        my $xrootd_options_file = $xrootd_options->{config};
        unless ($xrootd_options_file =~ /^\s*\//) {
            $xrootd_options_file = $xrootd_install_root . '/etc/' . $xrootd_options->{config};
        }
    }

    # When editing config files, remove lines present and matching a rule whose condition is not met
    my %parser_options;
    $parser_options{remove_if_undef} = 1;

    # Update configuration file for each role (Xrootd instance) held by the local node.
    # Roles 'redir' and 'fedredir' require some specific processing before updating
    # the configuration.
    #
    # Redir (local redirector):
    #   - If there are federations configured in the cluster, the local redirector must
    #     be configured to redirect to federation for the namespace they manage. This
    #     is specified in a federation-specific parameter 'localRedirectParams'. These
    #     parameters must be put in an array into the global options for easier processing
    #     by the rule parser.
    #
    # Fedredir (redirector partitipating to federation):
    #   - There is a matching instance of cmsd to start for each xrootd instances, sharing
    #     the same configuration file. The schema should enforce the consistency, thus
    #     it is not checked here.
    #   - Each fedredir instance belongs to a federation whose parameters are described
    #     in hash 'federations' in option. As the parser cannot deal with such a structure
    #     copy the relevant federation parameters in 'fedparams' option set for each instance.

    my $changes;
    my $roles = $xrootd_config->{hosts}->{$this_host_full}->{roles};
    if (defined($xrootd_options->{xrootdInstances})) {
        # We need to build a list of the xrootd instances with the local redirector first
        # that will be used to decide the startup order. A federation redirector cannot
        # start successfully until he established the contact with the local redirector.
        $xrootd_options->{xrootdOrderedInstances} = [];
        foreach my $instance (sort keys %{$xrootd_options->{xrootdInstances}}) {
            my $params        = $xrootd_options->{xrootdInstances}->{$instance};
            my $instance_type = $params->{type};
            if (grep(/^$instance_type$/, @$roles)) {
                $self->info("Checking xrootd instance '$instance' configuration ($params->{configFile})...");
                if ($instance_type eq 'redir') {
                    @{$xrootd_options->{xrootdOrderedInstances}} = ($instance, @{$xrootd_options->{xrootdOrderedInstances}});
                    $self->mergeLocalRedirects($xrootd_options);
                } else {
                    push @{$xrootd_options->{xrootdOrderedInstances}}, $instance;
                    if ($instance_type eq 'fedredir') {
                        my $federation = $params->{federation};
                        $self->debug(2, "Copying parameters for federation $federation to 'fedparams' option set");
                        $xrootd_options->{fedparams} = $xrootd_options->{federations}->{$federation};
                        # Normally enforced by schema validation...
                        if (exists($xrootd_options->{cmsdInstances}) && exists($xrootd_options->{cmsdInstances}->{$instance})) {
                            # cmsd configuration file is normally the same as the xrootd instance
                            if ($xrootd_options->{cmsdInstances}->{$instance}->{configFile} ne $params->{configFile}) {
                                $changes = $self->updateConfigFile(
                                                                   $xrootd_options->{cmsdInstances}->{$instance}->{configFile},
                                                                   $self->getRules($instance_type),
                                                                   $xrootd_options,
                                                                   \%parser_options
                                                                  );
                                if ($changes < 0) {
                                    $self->error(  "Error updating cmsd configuration for instance $instance_type ("
                                                 . $xrootd_options->{cmsdInstances}->{$instance}->{configFile}
                                                 . ")");
                                }
                            }
                        } else {
                            $self->error("No cmsd instance matching the xrootd fedredir instance '$instance'");
                        }
                    }
                }
                $changes = $self->updateConfigFile(
                                                   $params->{configFile},
                                                   $self->getRules($instance_type),
                                                   $xrootd_options,
                                                   \%parser_options
                                                  );
                if ($changes > 0) {
                    $self->serviceRestartNeeded('xrootd', $instance);
                    if ($instance_type eq 'fedredir') {
                        $self->debug(1, "Xrootd instance $instance is a fedredir: add matching cmsd instance to the restart list.");
                        $self->serviceRestartNeeded('cmsd', $instance);
                    }
                } elsif ($changes < 0) {
                    $self->error("Error updating xrootd configuration for instance $instance_type (" . $params->{configFile} . ")");
                }
            }
        }
    }


    # Build Authz configuration file for token-based authz
    if (exists($xrootd_options->{tokenAuthz}) && grep(/^redir$/, @$roles)) {
        # Build authz.cf
        my $token_auth_conf = $xrootd_options->{tokenAuthz};
        $self->info("Token-based authorization used: checking its configuration...");
        my $exported_vo_path_root  = $token_auth_conf->{exportedPathRoot};
        my $xrootd_authz_conf_file = $token_auth_conf->{authzConf};
        unless ($xrootd_authz_conf_file =~ /^\s*\//) {
            $xrootd_authz_conf_file = $xrootd_config_dir . "/" . $xrootd_authz_conf_file;
        }
        $self->debug(1, "Authorization configuration file:" . $token_auth_conf->{authzConf});
        my $xrootd_token_priv_key;
        if (defined($token_auth_conf->{tokenPrivateKey})) {
            $xrootd_token_priv_key = $token_auth_conf->{tokenPrivateKey};
        } else {
            $xrootd_token_priv_key = $xrootd_config_dir . '/pvkey.pem';
        }
        my $xrootd_token_pub_key;
        if (defined($token_auth_conf->{tokenPublicKey})) {
            $xrootd_token_pub_key = $token_auth_conf->{tokenPublicKey};
        } else {
            $xrootd_token_pub_key = $xrootd_config_dir . '/pvkey.pem';
        }

        $self->debug(1, "Opening token authz configuration file ($xrootd_authz_conf_file)");
        my $fh = CAF::FileWriter->new(
                                      $xrootd_authz_conf_file,
                                      backup => $BACKUP_FILE_EXT,
                                      owner  => $xrootd_options->{daemonUser},
                                      group  => $xrootd_options->{daemonGroup},
                                      mode   => 0400,
                                      log    => $self,
                                     );
        print $fh "Configuration file for xroot authz generated by quattor - DO NOT EDIT.\n\n"
          . "# Keys reside in "
          . $xrootd_config_dir . "\n"
          . "KEY VO:*       PRIVKEY:"
          . $xrootd_token_priv_key
          . " PUBKEY:"
          . $xrootd_token_pub_key . "\n\n"
          . "# Restrict the name space exported\n";
        if ($token_auth_conf->{exportedVOs}) {
            foreach my $vo (sort keys %{$token_auth_conf->{exportedVOs}}) {
                my $params = $token_auth_conf->{exportedVOs}->{$vo};
                my $exported_full_path;
                if (exists($params->{'path'})) {
                    my $exported_path = $params->{'path'};
                    if ($exported_path =~ /^\//) {
                        $exported_full_path = $exported_path;
                    } else {
                        $exported_full_path = $exported_vo_path_root . '/' . $exported_path;
                    }
                } else {
                    $exported_full_path = $exported_vo_path_root . '/' . $vo;
                }
                # VO token should not be defined to a particular VO as the VO name is not necessarily defined
                # in the token. The important goal of this line is to restrict the namespace portion accessible
                # though the token-based authz.
                print $fh "EXPORT PATH:" . $exported_full_path . " VO:*     ACCESS:ALLOW CERT:*\n";
            }
        } else {
            $self->warn("dpm-xroot: export enabled for all VOs. You should consider restrict to one VO only.");
            print $fh "EXPORT PATH:" . $exported_vo_path_root . " VO:*     ACCESS:ALLOW CERT:*\n";
        }

        print $fh "\n# Define operations requiring authorization.\n";
        print $fh "# NOAUTHZ operations honour authentication if present but don't require it.\n";
        if ($token_auth_conf->{accessRules}) {
            for my $rule (@{$token_auth_conf->{accessRules}}) {
                my $auth_ops   = join '|', @{$rule->{authenticated}};
                my $noauth_ops = join '|', @{$rule->{unauthenticated}};
                print $fh "RULE PATH:"
                  . $rule->{path}
                  . " AUTHZ:$auth_ops| NOAUTHZ:$noauth_ops| VO:"
                  . $rule->{vo}
                  . " CERT:"
                  . $rule->{cert} . "\n";
            }
        } else {
            print $fh "\n# WARNING: no access rules defined in quattor configuration.\n";
        }

        $changes = $fh->close();
        if ($changes > 0) {
            $self->serviceRestartNeeded('xrootd');
        } elsif ($changes < 0) {
            $self->error("Error updating xrootd authorization configuration ($xrootd_authz_conf_file)");
        }

        # Set right permissions on token public/private keys
        for my $key ($xrootd_token_priv_key, $xrootd_token_pub_key) {
            if (-f $key) {
                $self->debug(1, "Checking permission on $key");
                $changes = LC::Check::status(
                                             $key,
                                             owner => $xrootd_options->{daemonUser},
                                             group => $xrootd_options->{daemonGroup},
                                             mode  => 0400,
                                            );
                unless (defined($changes)) {
                    $self->error("Error setting permissions on xrootd token key $key");
                }
            } else {
                $self->warn("xrootd token key $key not found.");
            }
        }
    } else {
        $self->debug(1, "Token-based authentication disabled.");
    }


    # DPM/Xrootd sysconfig file if enabled
    if (defined($xrootd_options->{dpm})) {
        $self->info("Checking DPM/Xrootd plugin configuration ($XROOTD_SYSCONFIG_FILE)...");
        $changes = $self->updateConfigFile(
                                           $XROOTD_SYSCONFIG_FILE,
                                           $self->getRules('sysconfig'),
                                           $xrootd_options,
                                           \%parser_options
                                          );
        if ($changes > 0) {
            # Add the services to the restart list only if there is not already some instances of the
            # service to be restarted. This is done to avoid unnecessary restart of an instance if the
            # change in DPM/Xrootd sysconfig file is not affecting it. As there is no reliable way to predict
            # the instances that may be affected by a particular change in this file, the rationale is that
            # if the configuration file of an instance has been updated, thus the change in this config file
            # probably only affects this instance. If there was no other changes related that put an instance
            # on the restart list, restart every instance both for xrootd and cmsd. This will also stop
            # instances that are no longer part of the configuration.
            if ($xrootd_options->{cmsdInstances}) {
                $self->serviceRestartNeeded('xrootd,cmsd', '', 1);
            } else {
                $self->serviceRestartNeeded('xrootd', '', 1);
            }
        } elsif ($changes < 0) {
            $self->error("Error updating xrootd sysconfig file ($XROOTD_SYSCONFIG_FILE)");
        }
    } else {
        $self->debug(1, "DPM/Xrootd plugin disabled.");
    }


    # Restart services.
    # Don't signal error as it has already been signaled by restartServices().
    if ($xrootd_options->{restartServices} && $self->restartServices()) {
        return (1);
    }


    return 0;
}


# Function to add a service in the list of services needed to be restarted.
# Services can be a comma separated list.
# It is valid to pass a role with no associated services (nothing done).
#
# Arguments :
#  roles : roles for which the associated services need to be restarted (comma separated list)
#  instance (optional): service instance to restart. When no instance is specified, all service
#                       instances are restarted. If several roles are specified, the instance
#                       will be applied to all roles.
#  if_no_instance : flag to prevent addition of a service in the list if no instance was
#                   specified and if there is already some instances of the service
#                   in the restart list. This is used to avoid restarting too many instances.
sub serviceRestartNeeded ()
{
    my $function_name = "serviceRestartNeeded";
    my $self          = shift;

    my $roles = shift;
    unless ($roles) {
        $self->error("$function_name: 'roles' argument missing");
        return 0;
    }
    my $instance       = shift;
    my $if_no_instance = shift;
    unless (defined($if_no_instance)) {
        $if_no_instance = 0;
    }

    my $list;
    unless ($list = $self->getServiceRestartList()) {
        $self->debug(1, "$function_name: Creating list of service needed to be restarted");
        $self->{SERVICERESTARTLIST} = {};
        $list = $self->getServiceRestartList();
    }

    my @roles = split /\s*,\s*/, $roles;
    for my $role (@roles) {
        my @services = split /\s*,\s*/, $xrootd_services{$role};
        foreach my $service (@services) {
            unless (exists($list->{$service})) {
                $self->debug(1, "$function_name: adding '$service' to the list of service needed to be restarted");
                $list->{$service} = {};
            }
            if ($instance) {
                $self->debug(1, "$function_name: adding instance $instance of $service");
                $list->{$service}->{$instance} = '';
            } elsif (keys(%{$list->{$service}}) != 0) {
                if ($if_no_instance) {
                    $self->debug(1,
                                 "Service $service already has some instances in the restart list: ignoring attempt to restart all instances"
                                );
                } else {
                    # Reset to all instances
                    $list->{$service} = {};
                }
            }
        }
    }

    $self->debug(2, "$function_name: restart list = '" . join(" ", keys(%{$list})) . "'");
}


# Return list of services needed to be restarted
sub getServiceRestartList ()
{
    my $function_name = "getServiceRestartList";
    my $self          = shift;

    if (defined($self->{SERVICERESTARTLIST})) {
        $self->debug(2, "$function_name: restart list = " . join(" ", keys(%{$self->{SERVICERESTARTLIST}})));
        return $self->{SERVICERESTARTLIST};
    } else {
        $self->debug(2, "$function_name: list doesn't exist");
        return undef;
    }
}


# Return if a specific service is already in the restart list
#
# Arguments:
#   - service: name of the service to check
sub serviceRestartEnabled ()
{
    my $function_name = "serviceRestartEnabled";
    my $self          = shift;

    my $service = shift;
    unless ($service) {
        $self->error("$function_name: 'service' argument missing");
        return 0;
    }

    $self->debug(2, "$function_name: Checking if service $service is already in the restart list");

    my $list = $self->getServiceRestartList();

    if (exists($list->{$service})) {
        return 1;
    } else {
        return 0;
    }
}


# Restart services needed to be restarted
# Returns 0 if all services have been restarted successfully, else
# the number of services which failed to restart.

sub restartServices ()
{
    my $function_name = "RestartServices";
    my $self          = shift;
    my $global_status = 0;

    $self->debug(1, "$function_name: restarting services affected by configuration changes");

    # Need to do stop+start as sometimes dpm daemon doesn't restart properly with
    # 'restart'. Try to restart even if stop failed (can be just the daemon is
    # already stopped)
    if (my $list = $self->getServiceRestartList()) {
        $self->debug(1, "$function_name: list of services to restart : " . join(" ", keys(%{$list})));
        for my $service (keys %{$list}) {
            my @instances = keys(%{$list->{$service}});
            my @cmd = (SERVICECMD, $service, "stop");
            if (@instances > 0) {
                @cmd = (@cmd, @instances);
            }
            $self->info("Restarting service $service instances " . join(" ", @instances));
            $self->debug(1, "Restart command: " . join(" ", @cmd));
            CAF::Process->new(\@cmd, log => $self)->run();
            if ($?) {
                # Service can be stopped, don't consider failure to stop as an error
                $self->warn("\tFailed to stop $service");
            }
            sleep 5;    # Give time to the daemon to shut down
            my $attempt = 5;
            my $status;
            # Start all instances in case some have not yet been started or have been stopped manually.
            # This is harmless to start an already started instance.
            my $command = CAF::Process->new([SERVICECMD, $service, "start"], log => $self);
            $command->run();
            $status = $?;
            while ($attempt && $status) {
                $self->debug(1,
                             "$function_name: $service startup failed (probably not shutdown yet). Retrying ($attempt attempts remaining)"
                            );
                sleep 5;
                $attempt--;
                $command->run();
                $status = $?;
            }
            if ($status) {
                $global_status++;
                $self->error("\tFailed to start $service");
            } else {
                $self->info("Service $service restarted successfully");
            }
        }
    }

    return ($global_status);
}


# Update a config file using the CAF::RuleBasedEditor
#
# Arguments:
#   - config_file: name of the configuration file to edit
#   - rules: rules to apply
#   - config: configuration to use with rules
#   - parser_options: rule parser options
#
# Return value:
#   Success: number of resulting changes in the configuration file
#   Failure: undef

sub updateConfigFile ()
{
    my $function_name = "updateConfigFile";
    my ($self, $config_file, $rules, $config, $parser_options) = @_;

    unless ($config_file) {
        $self->error("$function_name: 'config_file' argument missing");
        return;
    }
    unless ($rules) {
        $self->error("$function_name: 'rules' argument missing");
        return;
    }
    unless ($config) {
        $self->error("$function_name: 'config' argument missing");
        return;
    }

    my $changes = 0;
    my $fh = CAF::RuleBasedEditor->new($config_file, log => $self);
    if (defined($fh)) {
        unless ($fh->updateFile($rules, $config, $parser_options)) {
            $self->error("Error updating " . $config_file);
        }
        $changes = $fh->close();
    } else {
        $self->error("Error opening " . $config_file);
    }

    return $changes;
}


1;    # Required for PERL modules

