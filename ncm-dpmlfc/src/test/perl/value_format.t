# -*- mode: cperl -*-
# ${license-info}
# ${author-info}
# ${build-info}

use strict;
use warnings;
use Test::More tests => 18;
use Test::NoWarnings;
use Test::Quattor;
use NCM::Component::DPMLFC::RuleBasedEditor qw(:rule_constants);
use Readonly;
use CAF::Object;
Test::NoWarnings::clear_warnings();


=pod

=head1 SYNOPSIS

Basic test for rule-based editor (value formatting)

=cut


# LINE_VALUE_HOST_LIST
Readonly my $HOST_LIST_OK => 'host1.example.com host2 host3.example.com';
Readonly my $HOST_LIST_DUPLICATES => 'host1.example.com host2 host1.example.com   host3.example.com host2  ';
Readonly my $HOST_LIST_QUOTED => '"host1.example.com host2 host3.example.com"';
my $formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($HOST_LIST_OK,
                                                                                     LINE_FORMAT_XRDCFG,
                                                                                     LINE_VALUE_HOST_LIST);
is($formatted_value, $HOST_LIST_OK, "Simple host list correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($HOST_LIST_OK,
                                                                                  LINE_FORMAT_PARAM,
                                                                                  LINE_VALUE_HOST_LIST);
is($formatted_value, $HOST_LIST_QUOTED, "Qoted host list correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($HOST_LIST_DUPLICATES,
                                                                                  LINE_FORMAT_PARAM,
                                                                                  LINE_VALUE_HOST_LIST);
is($formatted_value, $HOST_LIST_QUOTED, "Qoted list with duplicates correctly formatted");


# LINE_VALUE_BOOLEAN
Readonly my $FALSE => 'no';
Readonly my $TRUE => 'yes';
Readonly my $TRUE_QUOTED => '"yes"';
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(0,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_BOOLEAN);
is($formatted_value, $FALSE, "Boolean (false) correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(1,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_BOOLEAN);
is($formatted_value, $TRUE, "Boolean (true) correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(1,
                                                                                  LINE_FORMAT_PARAM,
                                                                                  LINE_VALUE_BOOLEAN);
is($formatted_value, $TRUE_QUOTED, "Boolean (true, quoted) correctly formatted");


# LINE_VALUE_AS_IS
Readonly my $AS_IS_VALUE => 'This is a Test';
Readonly my $AS_IS_VALUE_QUOTED => '"This is a Test"';
Readonly my $EMPTY_VALUE => '';
Readonly my $EMPTY_VALUE_QUOTED => '""';
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($AS_IS_VALUE,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_AS_IS);
is($formatted_value, $AS_IS_VALUE, "Literal value correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($AS_IS_VALUE,
                                                                                  LINE_FORMAT_ENVVAR,
                                                                                  LINE_VALUE_AS_IS);
is($formatted_value, $AS_IS_VALUE_QUOTED, "Literal value (quoted) correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($AS_IS_VALUE_QUOTED,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_AS_IS);
is($formatted_value, $AS_IS_VALUE_QUOTED, "Quoted literal value correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($AS_IS_VALUE_QUOTED,
                                                                                  LINE_FORMAT_ENVVAR,
                                                                                  LINE_VALUE_AS_IS);
is($formatted_value, $AS_IS_VALUE_QUOTED, "Already quoted literal value correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($EMPTY_VALUE,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_AS_IS);
is($formatted_value, $EMPTY_VALUE, "Empty value correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue($EMPTY_VALUE,
                                                                                  LINE_FORMAT_PARAM,
                                                                                  LINE_VALUE_AS_IS);
is($formatted_value, $EMPTY_VALUE_QUOTED, "Empty value (quoted) correctly formatted");


# LINE_VALUE_INSTANCE_PARAMS
# configFile intentionally misspelled confFile for testing
Readonly my %INSTANCE_PARAMS => (logFile => '/test/instance.log',
                                 confFile => '/test/instance.conf',
                                 logKeep => 60,
                                 unused => 'dummy',
                                );
Readonly my $FORMATTED_INSTANCE_PARAMS => ' -l /test/instance.log -k 60';
Readonly my $FORMATTED_INSTANCE_PARAMS_QUOTED => '" -l /test/instance.log -k 60"';
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(\%INSTANCE_PARAMS,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_INSTANCE_PARAMS);
is($formatted_value, $FORMATTED_INSTANCE_PARAMS, "Instance params correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(\%INSTANCE_PARAMS,
                                                                                  LINE_FORMAT_PARAM,
                                                                                  LINE_VALUE_INSTANCE_PARAMS);
is($formatted_value, $FORMATTED_INSTANCE_PARAMS_QUOTED, "Instance params (quoted) correctly formatted");


# LINE_VALUE_ARRAY
Readonly my @TEST_ARRAY => sort keys %INSTANCE_PARAMS;
Readonly my $FORMATTED_ARRAY => 'confFile logFile logKeep unused';
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(\@TEST_ARRAY,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_ARRAY);
is($formatted_value, $FORMATTED_ARRAY, "Array values correctly formatted");


# LINE_VALUE_HASH_KEYS
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->_formatAttributeValue(\%INSTANCE_PARAMS,
                                                                                  LINE_FORMAT_XRDCFG,
                                                                                  LINE_VALUE_HASH_KEYS);
is($formatted_value, $FORMATTED_ARRAY, "Hash keys correctly formatted");


Test::NoWarnings::had_no_warnings();
