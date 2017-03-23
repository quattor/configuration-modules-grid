# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gsissh;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use File::Path;


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    my %cfiles = ();

    # Define paths for convenience. 
    my $base = "/software/components/gsissh";

    # Get the globus_location.  Default to /opt/globus if not
    # specified. 
    my $globus_location = "/opt/globus";
    if ($config->elementExists("$base/globus_location")) {
	$globus_location = $config->getValue("$base/globus_location");
    }

    # Get the gpt_location.  Default to /opt/gpt if not
    # specified. 
    my $gpt_location = "/opt/gpt";
    if ($config->elementExists("$base/gpt_location")) {
	$gpt_location = $config->getValue("$base/gpt_location");
    }

    # Always configure the client.  Ensure that the configuration
    # directory exists.
    my $dir = "$globus_location/etc/ssh/";
    unless (-d $dir) {
	mkpath($dir, 0, 0755);
    }

    # Check that it's all ok.
    unless (-d $dir) {
	$self->error("can't create directory ($dir); aborting config....");
	return 1;
    }

    # Create the contents of the configuration file.
    my $contents = '';
    if ($config->elementExists("$base/client/options")) {
	my $elt = $config->getElement("$base/client/options");
	while ($elt->hasNextElement()) {
	    my $prop = $elt->getNextElement();
	    my $name = $prop->getName();
	    my $value = $prop->getValue();
	    $contents .= "$name $value\n";
	}
    }

    # OK, now write this out to the configuration file.
    open CONFIG, ">$dir/ssh_config";
    print CONFIG $contents;
    close CONFIG;
    $self->info("updated $dir/ssh_config");

    # The server port must exist, or we don't need to configure it.
    if ($config->elementExists("$base/server/port")) {

	# Setup environment for initialization script.
	$ENV{GLOBUS_LOCATION} = $globus_location;
	if (defined($ENV{PERLLIB})) {
	    $ENV{PERLLIB} = "$ENV{PERLLIB}:$gpt_location/lib/perl";
	} else {
	    $ENV{PERLLIB} = "$gpt_location/lib/perl";
	}

	# Run it.
	my $script = "$globus_location/setup/gsi_openssh_setup/setup-openssh";
	if (-x $script) {
	    `$script`;
	    if ($?) {
		$self->error("error running $script");
		return 1;
	    }
	} elsif (-f $script) {
	    $self->error("$script isn't executable");
	    return 1;
	}

	# Get the port number. 
	my $port = $config->getValue("$base/server/port");

	# Now hack the startup script. 
	$contents = '';
	if (-f "$globus_location/sbin/SXXsshd") {
	    open INITD, "<$globus_location/sbin/SXXsshd";
	    while (<INITD>) {
		my $line = $_;
		if ($line =~ /(.*)SSHD_ARGS="(.*?)"(.*)/) {
		    my $pre = $1;
		    my $arg = $2;
		    my $post = $3;
		    $arg =~ s/-p\s+\d+//;
		    $arg .= "-p $port";
                    $line = $pre . "SSHD_ARGS=\"$arg\"" . $post ;
		}
		$contents .= $line;
	    }
	    close INITD;
	} else {
	    $self->warn("$globus_location/sbin/SXXsshd doesn't exist");
	    return 1;
	}

	# Write out the file.
	open CONFIG, ">/etc/init.d/gsisshd";
	print CONFIG $contents;
	close CONFIG;
	chmod 0755, "/etc/init.d/gsisshd";
	$self->info("updated /etc/init.d/gsisshd");

	# Create the contents of the SERVER configuration file.
	$contents = '';
	if ($config->elementExists("$base/server/options")) {
	    my $elt = $config->getElement("$base/server/options");
	    while ($elt->hasNextElement()) {
		my $prop = $elt->getNextElement();
		my $name = $prop->getName();
		my $value = $prop->getValue();
		$contents .= "$name $value\n";
	    }
	}
	
	# OK, now write this out to the configuration file.
	open CONFIG, ">$dir/sshd_config";
	print CONFIG $contents;
	close CONFIG;
	$self->info("updated $dir/sshd_config");

	# Restart the service.
	`/sbin/service gsisshd restart`;
	if ($?) {
	    $self->error("error restarting gsisshd");
	}

    }


    return 1;
}

1;      # Required for PERL modules

