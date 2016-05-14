# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::lcgmonjob;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element;

use File::Copy;
use File::Path;


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/lcgmonjob";

    # Get the EDG and LCG locations.
    my $edgpath = "$base/EDG_LOCATION";
    my $lcgpath = "$base/LCG_LOCATION";
    my $edgloc = $config->getValue($edgpath);
    my $lcgloc = $config->getValue($lcgpath);

    # Define the source and destinations.
    my $src = "$lcgloc/etc/init.d/lcg-mon-job-status";
    my $dst = "/etc/rc.d/init.d/lcg-mon-job-status";

    # Check that the source file exists.
    if (! -f $src) {
	$self->error("init.d script ($src) doesn't exist");
	return 1;
    }

    # Remove the symbolic link if it exists. 
    unlink $dst if (-l $dst);

    # Create the new symbolic link.
    my $rc = symlink $src, $dst;
    if (! $rc) {
	$self->error("symlink ($src, $dst) returned error");
	return 1;
    }

    # Restart the daemon.  The restart method doesn't work so manually
    # do a stop and start.
    if (system($dst)) {
	$self->error("$dst restart failed: ". $?);
    }

    return 1;
}

1;      # Required for PERL modules
