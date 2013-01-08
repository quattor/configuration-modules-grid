# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::hydraserver;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;

## mmh. nice functions in there..
use NCM::Component::spma;

##########################################################################
# Global variables
my $mypath="/software/components/hydraserver";
my $config_file="/opt/glite/etc/glite-data-hydra-service/config.properties";

##########################################################################
sub Configure($$) {
##########################################################################
    my ($self,$config)=@_;
    my $need_to_reconfigure=0;

    open(TESTFILE,">>$config_file");
    print TESTFILE '';
    close(TESTFILE);

    if($config->elementExists($mypath."/instances")) {
        my $ret = 0;
        my $tree=$config->getElement($mypath."/instances");
        my %instances=$tree->getHash();
        my $tmp = "";
        for my $instance ( keys %instances ) {
            $tmp .= "$instance ";
        };
        chop $tmp;

        $ret = NCM::Check::lines("$config_file", linere => ".*HYDRA_INSTANCES=.*", good => "HYDRA_INSTANCES=\"$tmp\"", goodre => "^HYDRA_INSTANCES=\"$tmp\"", add => 'first', keep => 'first', backup => ".old");

        while( $tree->hasNextElement() ) {
            my $entry  = $tree->getNextElement();
            my $tag   = $entry->getName();
            $self->verbose("handling instance '$tag'");

            my $db_name = $config->getValue($mypath."/instances/$tag/db_name");
            $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_DBNAME_$tag=.*", good => "HYDRA_DBNAME_$tag=\"$db_name\"", goodre => "^HYDRA_DBNAME_$tag=\"$db_name\"", add => 'last', backup => ".old");
            my $db_user = $config->getValue($mypath."/instances/$tag/db_user");
            $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_DBUSER_$tag=.*", good => "HYDRA_DBUSER_$tag=\"$db_user\"", goodre => "^HYDRA_DBUSER_$tag=\"$db_user\"", add => 'last', backup => ".old");
            my $db_pass = $config->getValue($mypath."/instances/$tag/db_pass");
            $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_DBPASSWORD_$tag=.*", good => "HYDRA_DBPASSWORD_$tag=\"$db_pass\"", goodre => "^HYDRA_DBPASSWORD_$tag=\"$db_pass\"", add => 'last', backup => ".old");
            my $create = $config->getValue($mypath."/instances/$tag/create");
            $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_CREATE_$tag=.*", good => "HYDRA_CREATE_$tag=\"$create\"", goodre => "^HYDRA_CREATE_$tag=\"$create\"", add => 'last', backup => ".old");
            my $admin = $config->getValue($mypath."/instances/$tag/admin");
            $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_ADMIN_$tag=.*", good => "HYDRA_ADMIN_$tag=\"$admin\"", goodre => "^HYDRA_ADMIN_$tag=\"$admin\"", add => 'last', backup => ".old");
                                              
            my $peers = $config->getElement($mypath."/instances/$tag/peers");
            my $peer_counter=0;
            my $hydra_peers="";
            while ($peers->hasNextElement()) {
                $peer_counter +=1;
                $hydra_peers.="peer$peer_counter ";
                my $peer = $peers->getNextElement();
                my $peername = $peer->getValue();
                $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_ID_peer$peer_counter=.*", good => "HYDRA_ID_peer$peer_counter=\"$tag\"", goodre => "^HYDRA_ID_peer$peer_counter=\"$tag\"", add => 'last', backup => ".old" );
                $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_HOST_peer$peer_counter=.*", good => "HYDRA_HOST_peer$peer_counter=\"$peername\"", goodre => "^HYDRA_HOST_peer$peer_counter=\"$peername\"", add => 'last', backup => ".old" );
                $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_CREATE_peer$peer_counter=.*", good => "HYDRA_CREATE_peer$peer_counter=\"$create\"", goodre => "^HYDRA_CREATE_peer$peer_counter=\"$create\"", add => 'last', backup => ".old" );
            };
            chop $hydra_peers;
            $ret |= NCM::Check::lines("$config_file", linere => ".*HYDRA_PEERS=.*", good => "HYDRA_PEERS=\"$hydra_peers\"", goodre => "^HYDRA_PEERS=\"$hydra_peers\"", add => 'last', backup => ".old" );

            $self->verbose("Instance '$tag' ".($ret ? "" : "un")."changed ");
            $need_to_reconfigure = $ret;
            if ($need_to_reconfigure) {
                my $std_out;
                $self->info("Changed configuration, Hydra will be (re)configured...");
                my $adminpwd = $config->getValue($mypath."/instances/$tag/adminpwd");
                LC::Process::execute(["/opt/glite/etc/glite-data-hydra-service/configure --withpass=$adminpwd --values $config_file"], stdout=>\$std_out, stderr=>'stdout');
                my $ret_code=($? >> 8);
                if($ret_code != 0) {
                    $self->warn("Error on (re)confiration found:\n$std_out");
                } else {
                    $self->info("Reconfiguration finished successfull");
                }
            } else {
                $self->verbose("No (re)configuration is required");
            }
        }
    }
}

1; # Perl module requirement.

### Local Variables: ///
### mode: perl ///
### tab-width: 4 ///
### indent-tabs-mode: nil ///
### cperl-indent-level: 4 ///
### End: ///
