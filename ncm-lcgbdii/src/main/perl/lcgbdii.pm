# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::lcgbdii;

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
    my $base = "/software/components/lcgbdii";
    my $tfile = "/usr/lib/ncm/config/lcgbdii/lcgbdii.template";

    # Save the date.
    my $date = localtime();

    # The configuration file location.
    my $fname;
    if ($config->elementExists("$base/configFile")) {
        $fname = $config->getValue("$base/configFile");
    } else {
	$self->error("configuration file name not specified");
	return 1;
    }

    # Create the directory if necessary.
    my $dir = dirname($fname);
    mkpath($dir,0,0755) unless (-e $dir);
    unless (-d $dir) {
	$self->error("cannot create directory $dir");
	return 1;
    }
    
    # Fill template and get results.  Template substitution is simple
    # value replacement.  If a value doesn't exist, the line is not
    # output to the file.  
    my $contents = fill_template($config, $base, $tfile);

    # Will return undefined value on an error. 
    if (!defined($contents)) {
	$self->error("error filling template $tfile");
	return 1;
    }

    # Add the line with the list of BDII write ports.  Handled
    # specially because the simple template processor doesn't handle
    # lists. 
    if ($config->elementExists("$base/portsWrite")) {
        my @props = $config->getElement("$base/portsWrite")->getList();
        my @ports;
        foreach (@props) {
            push @ports, $_->getValue();
        }
	$contents .= 'BDII_PORTS_WRITE="' . join(' ',@ports) . '"' . "\n";
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

    # Change the owner to the one running the daemon.
    my $user = $config->getValue("$base/user");
    chmod 0600, $fname;
    chown((getpwnam($user))[2,3], glob($fname));

    # The update configuration file location.
    $fname = '';
    if ($config->elementExists("$base/dir")) {
        my $bdiiDir = $config->getValue("$base/dir");
	$fname = "$bdiiDir/etc/bdii-update.conf";
    } else {
	$self->error("BDII base directory not specified");
	return 1;
    }

    # Create the directory if necessary.
    $dir = dirname($fname);
    mkpath($dir,0,0755) unless (-e $dir);
    unless (-d $dir) {
	$self->error("cannot create directory $dir");
	return 1;
    }

    # Create the contents.
    $contents = "#\n# Created and maintained by ncm-lcgbdii. DO NOT EDIT.\n#\n";
    
    if ($config->elementExists("$base/urls")) {
	my %hash = $config->getElement("$base/urls")->getHash();
	foreach (sort keys %hash) {
	    my $url = $config->getValue("$base/urls/$_");
	    $contents .= "$_ $url\n";
	}
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

    # The file really only needs to be owned (and write-enabled) when
    # the autoModify flag is set, but does no harm in other cases. 
    chmod 0600, $fname;
    chown((getpwnam($user))[2,3], glob($fname));

    # The schema file location.
    if ($config->elementExists("$base/schemaFile")) {
        $fname = $config->getValue("$base/schemaFile");

	# Create the directory if necessary.
	my $dir = dirname($fname);
	mkpath($dir,0,0755) unless (-e $dir);
	unless (-d $dir) {	
	    $self->error("cannot create directory $dir");
	    return 1;
	}

	# Create the contents.  Just a list of the schema files.
	$contents = '';
	if ($config->elementExists("$base/schemas")) {
	    my @schemas = $config->getElement("$base/schemas")->getList();
	    foreach (@schemas) {
		$contents .= $_->getValue() . "\n";
	    }
	}

	# Now just create the new configuration file.  Be careful to save
	# a backup of the previous file if necessary. 
	my $result = LC::Check::file( $fname,
				      backup => ".old",
				      contents => $contents,
				      );
	$self->log("$fname created or updated") if $result;
    }
    
    # Restart the server.
    if (system("/sbin/service bdii stop")) {
	$self->warn("init.d lcg-bdii stop failed: ". $?);
    }
    if (system("/sbin/service bdii start")) {
	$self->error("init.d lcg-bdii start failed: ". $?);
    }
    

    return 1;
}

# Do a simple template substitution.  The following tags are recognized:
#
# <%path|default%>
# <%"path|default"%>
#
# For paths which don't exist the given default value is used.  However,
# if the path doesn't exist and the default is not specified, then the
# line is not printed at all.  The only difference between the first and
# second forms is that the second will create a double-quoted string with
# any embedded double quotes properly escaped. 
#
sub fill_template {

    my ($config, $base, $template) = @_;

    my $translation = "";

    if (-e "$template") {
	open TMP, "<$template";
	while (<TMP>) {
            my $err = 0;

            # Special form for date.
            s/<%!date!%>/localtime()/eg;

            # Need quoted result (escape embedded quotes).
            s!<%"\s*(/[\w/]+)\s*(?:\|\s*(.+?))?\s*"%>!quote(fill($config,$1,$2,\$err))!eg;
            s!<%"\s*([\w]+[\w/]*)(?:\|\s*(.+?))?\s*"%>!quote(fill($config,"$base/$1",$2,\$err))!eg;

            # Normal result OK. 
            s!<%\s*(/[\w/]+)\s*(?:\|\s*(.+?))?%>!fill($config,$1,$2,\$err)!eg;
            s!<%\s*([\w]+[\w/]*)\s*(?:\|\s*(.+?))?%>!fill($config,"$base/$1",$2,\$err)!eg;

            # Add the output line unless an error was signaled.  An
            # error occurs when an element doesn't exist.  In this
            # case it is assumed that the value is optional and the
            # line is omitted.  
            $translation .= $_ unless $err;
	}
	close TMP;
    } else {
	$translation = undef;
    }

    return $translation;
}


# Escape quotes in a string value.
sub fill {
    my ($config,$path,$default,$errorRef) = @_;

    my $value = "";

    if ($config->elementExists($path)) {
        $value = $config->getValue($path);
    } elsif (defined $default) {
        $value = $default;
    } else {
        # Flag an error and return empty string.
        $$errorRef = "1";
    }
    return $value;
}


# Escape quotes and double quote the value. 
sub quote {
    my ($value) = @_;

    $value =~ s/"/\\"/g;  # escape any embedded quotes
    $value = '"'.$value.'"';
    return $value;
}

# Change ownership by name.
sub createAndChownDir {

    my ($user, $dir) = @_;

    mkpath($dir,0,0755);
    chown((getpwnam($user))[2,3], glob($dir)) if (-d $dir);
}

1;      # Required for PERL modules
