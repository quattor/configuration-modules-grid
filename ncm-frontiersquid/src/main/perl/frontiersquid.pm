# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::frontiersquid;
#
# a few standard statements, mandatory for all components
#

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;

use EDG::WP4::CCM::Element;

use LC::Check;

use Encode qw(encode_utf8);

local(*DTA);


use EDG::WP4::CCM::Element;

##########################################################################
sub Configure($$) {
##########################################################################
  my ($self,$config)=@_;
  my $base     = "/software/components/frontiersquid/";
  my $rpm_home = "/home/dbfrontier";
  my $response_file = "/tmp/response_file.ncm-frontiersquid";

  my $frontier_config = $config->getElement($base)->getTree();

  my $home      = $frontier_config->{home};
  my $username  = $frontier_config->{username};
  my $group     = $frontier_config->{group};
  my $networks  = $frontier_config->{networks};
  my $servers   = $frontier_config->{servers};
  my $cache_mem = $frontier_config->{cache_mem};
  my $cache_dir = $frontier_config->{cache_dir};

  my $squid_file = $home."/etc/squid.conf";

  my $contents  = $home."\n";
  $contents  .= $username . "\n";
  $contents  .= $group . "\n";
  for my $net (@{$networks}) {
	$contents .= EDG::WP4::CCM::Element::unescape($net).",";
  }
  $contents = substr($contents, 0, - 1); 
  $contents  .= "\n";
  for my $serv (@{$servers}) {
        $contents .= EDG::WP4::CCM::Element::unescape($serv).",";
  }
  $contents = substr($contents, 0, - 1); 
  $contents  .= "\n";
  $contents  .= $servers_string . "\n";
  $contents  .= $cache_mem . "\n";
  $contents  .= $cache_dir . "\n"; 

  my $changes = LC::Check::file("$response_file",
                                contents => encode_utf8($contents),
                                mode => 0644,
                               );
  if ( $changes < 0 ) {
	$self->warn("Error creating $response_file");
  }

  system($rpm_home."/etc/post_install <".$response_file);

  return; # return code is not checked.

}

1; # Perl module requirement.
