# -*- mode: cperl -*-
# ${license-info}
# ${author-info}
# ${build-info}

use strict;
use warnings;
use Test::More tests => 10;
use Test::NoWarnings;
use Test::Quattor;
use NCM::Component::dpmlfc;
use Readonly;
use CAF::Object;
Test::NoWarnings::clear_warnings();


=pod

=head1 SYNOPSIS

Basic test for dpmlfc configuration (variable deletion)

=cut

Readonly my $DPM_CONF_FILE => "/etc/sysconfig/dpm";

Readonly my $DPM_INITIAL_CONF_1 => '# should the dpm daemon run?
# any string but "yes" will equivalent to "NO"
#
RUN_DPMDAEMON="yes"
#
# should we run with another limit on the number of file descriptors than the default?
# any string will be passed to ulimit -n
#ULIMIT_N=4096
#
###############################################################################################
# Change and uncomment the variables below if your setup is different than the one by default #
###############################################################################################

ALLOW_COREDUMP="yes"

#################
# DPM variables #
#################

# - DPM Name Server host : please change !!!!!!
#DPNS_HOST=grid05.lal.in2p3.fr

# - make sure we use globus pthread model
export GLOBUS_THREAD_MODEL=pthread
';

Readonly my $DPM_INITIAL_CONF_2 => $DPM_INITIAL_CONF_1 . '
# Duplicated line
ALLOW_COREDUMP="yes"
';

Readonly my $DPM_EXPECTED_CONF_1 => '# This file is managed by Quattor - DO NOT EDIT lines generated by Quattor
#
# should the dpm daemon run?
# any string but "yes" will equivalent to "NO"
#
RUN_DPMDAEMON="yes"
#
# should we run with another limit on the number of file descriptors than the default?
# any string will be passed to ulimit -n
#ULIMIT_N=4096
#
###############################################################################################
# Change and uncomment the variables below if your setup is different than the one by default #
###############################################################################################

#ALLOW_COREDUMP="yes"

#################
# DPM variables #
#################

# - DPM Name Server host : please change !!!!!!
#DPNS_HOST=grid05.lal.in2p3.fr

# - make sure we use globus pthread model
#export GLOBUS_THREAD_MODEL=pthread
';

Readonly my $DPM_EXPECTED_CONF_2 => '# This file is managed by Quattor - DO NOT EDIT lines generated by Quattor
#
# should the dpm daemon run?
# any string but "yes" will equivalent to "NO"
#
RUN_DPMDAEMON="yes"
#
# should we run with another limit on the number of file descriptors than the default?
# any string will be passed to ulimit -n
#ULIMIT_N=4096
#
###############################################################################################
# Change and uncomment the variables below if your setup is different than the one by default #
###############################################################################################

#ALLOW_COREDUMP="yes"

#################
# DPM variables #
#################

# - DPM Name Server host : please change !!!!!!
#DPNS_HOST=grid05.lal.in2p3.fr

# - make sure we use globus pthread model
export GLOBUS_THREAD_MODEL=pthread
';

Readonly my $DPM_EXPECTED_CONF_3 => $DPM_EXPECTED_CONF_1 . '
# Duplicated line
#ALLOW_COREDUMP="yes"
';


# Copied from dpmlfc.pm
use constant LINE_FORMAT_PARAM => 1;
use constant LINE_FORMAT_ENVVAR => 2;
use constant LINE_FORMAT_XRDCFG => 3;
use constant LINE_FORMAT_XRDCFG_SETENV => 4;
use constant LINE_FORMAT_XRDCFG_SET => 5;
use constant LINE_VALUE_AS_IS => 0;
use constant LINE_VALUE_BOOLEAN => 1;
use constant LINE_VALUE_HOST_LIST => 2;
use constant LINE_VALUE_INSTANCE_PARAMS => 3;
use constant LINE_VALUE_ARRAY => 4;
use constant LINE_VALUE_HASH_KEYS => 5;
use constant LINE_VALUE_STRING_HASH => 6;
use constant LINE_VALUE_OPT_NONE => 0;
use constant LINE_VALUE_OPT_SINGLE => 1;
use constant LINE_FORMAT_DEFAULT => LINE_FORMAT_PARAM;
use constant LINE_QUATTOR_COMMENT => "\t\t# Line generated by Quattor";

my %config_rules_1 = (
      "-ALLOW_COREDUMP" => "allowCoreDump:dpm;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "-GLOBUS_THREAD_MODEL" => "globusThreadModel:dpm;".LINE_FORMAT_ENVVAR,
     );

my %config_rules_2 = (
      "ALLOW_COREDUMP" => "allowCoreDump:dpm;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "GLOBUS_THREAD_MODEL" => "globusThreadModel:dpm;".LINE_FORMAT_ENVVAR,
     );

my %config_rules_3 = (
      "ALLOW_COREDUMP" => "!srmv22->allowCoreDump:dpm;".LINE_FORMAT_PARAM.";".LINE_VALUE_BOOLEAN,
      "GLOBUS_THREAD_MODEL" => "dpns->globusThreadModel:dpm;".LINE_FORMAT_ENVVAR,
     );

my %parser_options = ("remove_if_undef" => 1);

$CAF::Object::NoAction = 1;

my $comp = NCM::Component::dpmlfc->new('dpmlfc');

# Test negated keywords
my $dpm_options = {};
set_file_contents($DPM_CONF_FILE,$DPM_INITIAL_CONF_1);
my $changes = $comp->updateConfigFile($DPM_CONF_FILE,
                                   \%config_rules_1,
                                   $dpm_options,
                                   \%parser_options);
my $fh = get_file($DPM_CONF_FILE);
ok(defined($fh), $DPM_CONF_FILE." was opened");
is("$fh", $DPM_EXPECTED_CONF_1, $DPM_CONF_FILE." has expected contents (negated keywords)");
$fh->close();

# Test removal of config line is config option is not defined
$dpm_options = {"dpm" => {"globusThreadModel" => "pthread"}};
set_file_contents($DPM_CONF_FILE,$DPM_INITIAL_CONF_1);
$changes = $comp->updateConfigFile($DPM_CONF_FILE,
                                   \%config_rules_2,
                                   $dpm_options,
                                   \%parser_options);
$fh = get_file($DPM_CONF_FILE);
ok(defined($fh), $DPM_CONF_FILE." was opened");
is("$fh", $DPM_EXPECTED_CONF_2, $DPM_CONF_FILE." has expected contents (config option not defined)");
$fh->close();

# Test removal of config line is rule condition is not met
$dpm_options = {"dpm" => {"globusThreadModel" => "pthread"}};
set_file_contents($DPM_CONF_FILE,$DPM_INITIAL_CONF_1);
$changes = $comp->updateConfigFile($DPM_CONF_FILE,
                                   \%config_rules_3,
                                   $dpm_options,
                                   \%parser_options);
$fh = get_file($DPM_CONF_FILE);
ok(defined($fh), $DPM_CONF_FILE." was opened");
is("$fh", $DPM_EXPECTED_CONF_1, $DPM_CONF_FILE." has expected contents (rule condition not met)");
$fh->close();

# Test removal of config line appearing multiple times
$dpm_options = {"dpm" => {"globusThreadModel" => "pthread"}};
set_file_contents($DPM_CONF_FILE,$DPM_INITIAL_CONF_2);
$changes = $comp->updateConfigFile($DPM_CONF_FILE,
                                   \%config_rules_1,
                                   $dpm_options,
                                   \%parser_options);
$fh = get_file($DPM_CONF_FILE);
ok(defined($fh), $DPM_CONF_FILE." was opened");
is("$fh", $DPM_EXPECTED_CONF_3, $DPM_CONF_FILE." has expected contents (repeated config line)");
$fh->close();


Test::NoWarnings::had_no_warnings();
