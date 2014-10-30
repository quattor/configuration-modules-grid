#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 7;
use Test::NoWarnings;
use Test::Quattor;
use NCM::Component::mkgridmap;
use Readonly;
use CAF::Object;
Test::NoWarnings::clear_warnings();

Readonly my $CMD_VERB => '/usr/sbin//edg-mkgridmap';
Readonly my $CMD_PARAM1 => '--conf=/etc/edg-mkgridmap.conf';
Readonly my $CMD_PARAM2 => '--output /etc/grid-security/grid-mapfile';
Readonly my $CMD_PARAM3 => '--safe';
Readonly my $TEST_CMD => "$CMD_VERB $CMD_PARAM1 $CMD_PARAM2 $CMD_PARAM3";
Readonly my $EXPECTED_TOK_NUM => 5;

$CAF::Object::NoAction = 1;

=pod

=head1 SYNOPSIS

This is a test suite for ncm-mkgridmap tokenize_cmd() method.

=cut

my $cmp = NCM::Component::mkgridmap->new('mkgridmap');

my @cmd_tokens = $cmp->tokenize_cmd($TEST_CMD);
is(scalar(@cmd_tokens), $EXPECTED_TOK_NUM, "Expected number of command tokens");
is($cmd_tokens[0], $CMD_VERB, "Expected command verb");
is($cmd_tokens[1], $CMD_PARAM1, "Expected first parameter");
is("$cmd_tokens[2] $cmd_tokens[3]", $CMD_PARAM2, "Expected second parameter");
is($cmd_tokens[4], $CMD_PARAM3, "Expected third parameter");

Test::NoWarnings::had_no_warnings();
