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


##########################################################################
sub Configure($$@) {
##########################################################################
  my ($self,$config)=@_;
  my $base     = "/software/components/frontiersquid/";

  my $frontier_config = $config->getElement($base)->getTree();

  # Check that networks is really defined.
  #my $networks = $frontier_config->{networks};
  #if (!defined($networks)) {
  #   $self->error("entry with undefined networks");
  #   return 0;
  #}

  # Pull out the other values
  my $rpmhome = $frontier_config->{rpmhome};
  if (!defined($rpmhome)) {
     my $rpmhome = "/data/squid";
  }
  my $postinstall = $frontier_config->{postinstall};
  if (!defined($postinstall)) {
       my $postinstall = "/etc/post_install";
  }
  my $response_file = $frontier_config->{squidconf};
  if (!defined($response_file)) {
     my $response_file = "/data/squid/squidconf";
  }
  my $username = $frontier_config->{username};
  my $group = $frontier_config->{group};
  my $cache_mem = $frontier_config->{cache_mem};
  my $cache_dir = $frontier_config->{cache_dir};

  my $contents  = "export FRONTIER_USER=".$username."\n";
  $contents  .= "export FRONTIER_GROUP=".$group . "\n";
  $contents  .= "export FRONTIER_NET_LOCAL='".$networks."'\n"; 
  $contents  .= "export FRONTIER_CACHE_MEM=".$cache_mem . "\n";
  $contents  .= "export FRONTIER_CACHE_DIR_SIZE=".$cache_dir . "\n"; 

  my $changes = LC::Check::file("$response_file",
                                contents => encode_utf8($contents),
                                mode => 0644,
                                );
  if ( $changes < 0 ) {
	$self->warn("Error creating $response_file");
        return 0;
  }

  system("export SCFILE=".$response_file.";".$rpmhome.$postinstall");

  return 1; # return code is not checked.
}

1; # Perl module requirement.
