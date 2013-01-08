# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::pbsknownhosts;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;

use EDG::WP4::CCM::Element;

use File::Path;
use File::Basename;

local(*DTA);

# Define paths for convenience. 
my $base = "/software/components/pbsknownhosts";

my $pbsbin_def = "/usr/bin";


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # what files need to be generated?
    # by default generate pbs_known_hosts and leave shosts.equiv alone
    my @targets;
    if ($config->elementExists("$base/targets")) {
	my @t = $config->getElement("$base/targets")->getList();
	foreach my $tval ( @t ) {
	    push @targets, $tval->getValue();
	}
    } else {
	@targets = ( "pbsknownhosts" );
    }

    foreach ( @targets ) {
      my $filename;
      if (/knownhosts/) {
          $filename = "pbs_known_hosts";
          $self->debug(1,"Generating pbs-knownhosts config file for ssh_known_hosts generation");
	    } elsif (/shosts/) {
          $filename = "shosts.equiv";
          $self->debug(1,"Generating pbs-shostsequiv config file for shosts.equiv generation");
      };
      if ( !$self->make_sshfile($config,$_) ) {
          $self->error("cannot create $filename file");
          return 1;
      } 
    }

    return 1;
}

    
sub make_sshfile($$@) {

    my ($self, $config,$target ) = @_;

    my $contents = "# File genererated by ncm-pbsknownhosts on " . localtime() .
 ".\n#\n";

    my $filenameResource;
    my $scriptResource;
    my $scriptDefault;
    if ( $target =~ /shosts/ ) {
      $filenameResource = "shostsConfigFile";
      $scriptResource = "shostsscript";
      $scriptDefault = "/opt/edg/sbin/edg-pbs-shostsequiv";
      $contents = $contents . "SHOSTSEQUIV = /etc/ssh/shosts.equiv\n";
    } else {
      $filenameResource = "configFile";
      $scriptResource = "knownhostsscript";
      $scriptDefault = "/opt/edg/sbin/edg-pbs-knownhosts";
      $contents = $contents . "KNOWNHOSTS = /etc/ssh/ssh_known_hosts\n";
    }

    # Get the configuration file name.
    my $fname;
    if ($config->elementExists("$base/$filenameResource")) {
        $fname = $config->getValue("$base/$filenameResource");
    } else {
        $self->error("configuration file name not specified");
        return 1;
    }

    # Get the script name.
    my $script;
    if ($config->elementExists("$base/$scriptResource")) {
        $script = $config->getValue("$base/$scriptResource");
    } else {
        $script = $scriptDefault;
    }

    # Get configuration parameters
    
    if ($config->elementExists("$base/nodes")) {
      my $nodes = $config->getValue("$base/nodes");
      $nodes =~ s/\s+/ /g;
      $contents =  $contents . "NODES = $nodes\n";
    }

    my $pbsbin;
    if ($config->elementExists("$base/pbsbin")) {
      $pbsbin = $config->getValue("$base/pbsbin");
    } else {
      $pbsbin = $pbsbin_def;
    }
    $contents =  $contents . "PBSBIN = $pbsbin\n";

    if ($config->elementExists("$base/keytypes")) {
      my $keytypes = $config->getValue("$base/keytypes");
      $contents =  $contents . "KEYTYPES = $keytypes\n";
    } else {
      $self->error("Missing keytypes");
    }

     # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    if ( ! -e $fname ) {
        
        # Configuration file doesn't exist yet.  Create it. 
        open ( CONF,">$fname" );
        print CONF $contents;
        close (CONF);
        $self->log("$fname created");
        
    } else {
        
        # Already exists. Make backup and create new file. 
        my $result = LC::Check::file( $fname,
                                      backup => ".old",
                                      contents => $contents,
                                      );
        $self->log("$fname updated") if $result;
    }
    
    # Do a run of the script to generate the initial known hosts file.
    if ( ( ! -f "$fname.old" ) or cdiffer($fname,"$fname.old") ) {
        $self->log("$fname modified, running $script");
        if (-x $script) {
            system($script);
            $self->warn("$script failed: $?") if $?;
        } else {
            $self->warn("$script is not executable");
        }
    }

    return 1;
}

# do a content-only comparison between two files. This is needed as
# LC::File::differ will trigger on differences in comments (like the
# generation time). Both must exist.
sub cdiffer($$) {
    my ($f1,$f2) = @_;
    my $c1 = LC::File::file_contents($f1);
    my $c2 = LC::File::file_contents($f2);

    if ( $c1 and $c2 ) {
        $c1=~s/#[^\n]*\n//sg;
        $c2=~s/#[^\n]*\n//sg;
        return 0 if ( $c1 eq $c2 );
    } else {
        return 1;
    }
    return 1;
}


# Change ownership by name.
sub createAndChownDir {

    my ($user, $dir) = @_;

    mkpath($dir,0,0755);
    chown((getpwnam($user))[2,3], glob($dir)) if (-d $dir);
}

1;      # Required for PERL modules
