# -*- mode: cperl -*-
# ${license-info}
# ${author-info}
# ${build-info}

use strict;
use warnings;
use Test::More tests => 5;
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
my $formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->formatAttributeValue($HOST_LIST_OK,
                                                                                    LINE_FORMAT_XRDCFG,
                                                                                    LINE_VALUE_HOST_LIST,
                                                                                   );
is($formatted_value, $HOST_LIST_OK, "Simple host list correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->formatAttributeValue($HOST_LIST_OK,
                                                                                 LINE_FORMAT_PARAM,
                                                                                 LINE_VALUE_HOST_LIST,
                                                                                );
is($formatted_value, $HOST_LIST_QUOTED, "Qoted host list correctly formatted");
$formatted_value = NCM::Component::DPMLFC::RuleBasedEditor->formatAttributeValue($HOST_LIST_DUPLICATES,
                                                                                 LINE_FORMAT_PARAM,
                                                                                 LINE_VALUE_HOST_LIST,
                                                                                );
is($formatted_value, $HOST_LIST_QUOTED, "Qoted list with duplicates correctly formatted");


Test::NoWarnings::had_no_warnings();

