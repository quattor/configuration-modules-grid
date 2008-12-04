# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::lbconfig;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;

use EDG::WP4::CCM::Element;


local(*DTA);


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/lbconfig";
    my $edgpath = "/system/edg/config/EDG_LOCATION";
    my $edgvarpath = "/system/edg/config/EDG_LOCATION_VAR";

    # Default location for EDG software.
    my $edgloc = "/opt/edg";
    if ($config->elementExists($edgpath)) {
        $edgloc = $config->getValue($edgpath);
    }

    # Default location for EDG var area.
    my $varloc = "$edgloc/var";
    if ($config->elementExists($edgvarpath)) {
        $varloc = $config->getValue($edgvarpath); 
    }

    # Ensure that the configuration path exists.
    my $etcpath = "$varloc/etc";
    mkpath($etcpath,0,0755) unless (-d $etcpath);
    unless (-d $etcpath) {
	$self->error("$etcpath can't be created");
	return 1;
    }

    # Save the date.
    my $date = localtime();

    # Create the sqlFile configuration. 
    # Collect all of the indicies.
    my @indicies;
    if ($config->elementExists("$base/indicies")) {
	my %hash = $config->getElement("$base/indicies")->getHash();
	foreach my $type (sort keys %hash) {
	    my @names = $hash{$type}->getList();
	    foreach (@names) {
		my $name = $_->getValue();
		push @indicies, "[type = \"$type\"; name = \"$name\"]";
	    }
	}
    }

    # ClassAds doesn't appear to take any comment syntax.
    my $contents = "[\n";
    $contents .= "JobIndices = {\n";
    $contents .= join(",\n", @indicies);
    $contents .= "\n}\n";
    $contents .= "]\n";

    # Create/update the configuration file.
    my $fname = "$etcpath/" . $config->getValue("$base/configFile");
    $self->createConfig($fname, $contents);

    # Ensure that the configuration path exists.
    my $cfgpath = "$varloc/etc/profile.d";
    mkpath($cfgpath,0,0755) unless (-d $cfgpath);
    unless (-d $cfgpath) {
	$self->error("$cfgpath can't be created");
	return 1;
    }

    # Copy profile.d scripts into var area.
    my $srcfile = "$edgloc/etc/profile.d/edg-wl-lbserver-rgma-env.sh";
    my $dstfile = "$cfgpath/edg-wl-lbserver-rgma-env.sh";
    copy($srcfile, $dstfile);
    if ($?) {
	$self->error("problem copying $srcfile to $dstfile");
    }

    # Execute the configure script.
    my $cmd = "$edgloc/sbin/edg-wl-bkindex -r $fname";
    system($cmd);
    if ($?) {
	$self->error("error executing command: $cmd");
    }
    return 1;
}

sub createConfig {

    my ($self, $fname, $contents) = @_;

    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    if ( ! -e $fname ) {
        
        # Configuration file doesn't exist yet.  Create it. 
        open CONF, ">$fname";
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
};


1;      # Required for PERL modules
