# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gacl;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element;

use LC::File qw(copy);
use LC::Check;
use LC::Process qw(run);

use Encode qw(encode_utf8);

local(*DTA);

# Define paths for convenience. 
my $base = "/software/components/gacl";

my $true = "true";
my $false = "false";

##########################################################################
sub Configure {
##########################################################################
  my ($self,$config)=@_;

  my $confighash = $config->getElement($base)->getTree();
  my $voconfig = $config->getElement('/system/vo')->getTree();

  my $gacl_content = "<gacl>\n";

  # Loop over all VOs and add an entry in grid ACL file corresponding to each VO FQAN
  
  for my $vo (sort(keys(%$voconfig))) {
    $self->debug(1,"Processing VO $vo FQANs...");
    
    my $vo_fqans = $voconfig->{$vo}->{voms};
    for my $fqanhash (@$vo_fqans) {
      my $fqan = $fqanhash->{fqan};
      $self->debug(1,"Adding FQAN $fqan");
      $gacl_content .= "  <entry>\n";
      $gacl_content .= "    <voms>\n";
      $gacl_content .= "      <fqan>$fqan</fqan>\n";
      $gacl_content .= "    </voms>\n";
      $gacl_content .= "    <allow>\n";
      $gacl_content .= "      <exec/>\n";
      $gacl_content .= "    </allow>\n";
      $gacl_content .= "  </entry>\n";
    }
  }
  
  $gacl_content .= "</gacl>\n";

  # Update grid ACL file
  
  my $status = LC::Check::file ($confighash->{aclFile},
                                'backup' => '.old',
                                'contents' => encode_utf8($gacl_content),
                                'owner' => 'root',
                                'group' => 'root',
                                'mode' => '0644',
                               );


  return;
}


1; #required for Perl modules

