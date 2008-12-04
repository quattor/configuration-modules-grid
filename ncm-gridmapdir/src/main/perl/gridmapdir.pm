# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gridmapdir;

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


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/gridmapdir";

    # Ensure that the gridmapdir is really a directory and that it
    # exists. 
    my $gridmapdir = $config->getValue("$base/gridmapdir");
    if ($gridmapdir =~ m%(.*)/$%) {
	$gridmapdir = $1;
    }
    mkpath($gridmapdir,0,0755) unless (-e $gridmapdir);
    unless (-d $gridmapdir) {
	$self->error("problem creating $gridmapdir directory");
	return 1;
    }

    # Read all of the files in that directory except the hidden
    # files. 
    opendir DIR, "$gridmapdir";
    my @files = map {"$gridmapdir/$_"} grep {!/^\./} readdir DIR;
    closedir DIR;

    # Create two hashes, one which hashes the inode number to a list
    # of file names and the second one which hashes just the file
    # names. 
    my %inodes = ();
    my %existing = ();
    foreach (@files) {
    
	# Inode map.
	my $inode = (stat($_))[1];
	if (defined($inodes{$inode})) {
	    my $lref = $inodes{$inode};
	    push @$lref, $_;
	} else {
	    my @a;
	    push @a, $_;
	    $inodes{$inode} = \@a;
	};
	    
	# Existing files.
	$existing{$_} = $inode;
    }

    # Now create a hash of all of the desired files.
    my %desired = ();
    if ($config->elementExists("$base/poolaccounts")) {
	my %pools = $config->getElement("$base/poolaccounts")->getHash();
	foreach my $prefix (sort keys %pools) {

	    # Base configuration for pool account in accounts component
	    my $poolAccountBase = "/software/components/accounts/users/$prefix";

	    # Default value if not defined in configuration
	    my $poolStart = 0;

	    # Read poolStart from accounts configuration.
	    if ($config->elementExists("$poolAccountBase/poolStart")) {
		$poolStart = $config->getValue("$poolAccountBase/poolStart");
	    }

	    # Read poolSize from accounts configuration.  If poolSize isn't
	    # specified, assume zero (and do nothing).
	    my $poolSize = 0;
	    if ($config->elementExists("$poolAccountBase/poolSize")) {
		$poolSize = $config->getValue("$poolAccountBase/poolSize");
	    }

	    my $poolEnd = $poolStart+$poolSize-1;

	    # Read the number of digits to pad pool accounts to
	    my $poolDigits = length("$poolEnd");
	    if ($config->elementExists("$poolAccountBase/poolDigits")) {
		$poolDigits = $config->getValue("$poolAccountBase/poolDigits");
	    }
	    
	    # Set up sprintf format specifier
	    my $field = "%0" . $poolDigits . "d";

	    foreach my $i ($poolStart .. $poolEnd) {
		my $fname=sprintf($prefix.$field, $i);
		$desired{"$gridmapdir/$fname"} = 1;
	    }
	}
    }

    # Remove duplicates between the hashes.  These already exist and
    # are needed in the configuration, so nothing needs to be done. 
    foreach (keys %desired) {
	if (defined($existing{$_})) {
	    my $inode = $existing{$_};
	    my $aref = $inodes{$inode};
	    foreach (@$aref) {
		delete($desired{$_}) if (exists($desired{$_}));
		delete($existing{$_}) if (exists($existing{$_}));
	    }
	}
    }

    # Any files which remain in the existing hash are not wanted.
    # Make sure that they are deleted.
    foreach (keys %existing) {
	unlink $_;
    }

    # Now touch the files in the desired hash to make sure everything
    # exists. 
    foreach (keys %desired) {
	open FILE, ">$_";
	close FILE;
	$self->warn("Error creating file: $_") if ($?);
    }

    return 1;
}

1;      # Required for PERL modules
