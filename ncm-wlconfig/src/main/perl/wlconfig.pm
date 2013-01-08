# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::wlconfig;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;
use File::Path;
use File::Find;

use EDG::WP4::CCM::Element;

use vars qw(%wp1vars);


local(*DTA);


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/wlconfig";
    my $tfile = "/usr/lib/ncm/config/wlconfig/wlconfig.template";
    my $edgpath = "/system/edg/config/EDG_LOCATION";
    my $edgvarpath = "/system/edg/config/EDG_LOCATION_VAR";

    # Default location for EDG software.
    my $edgloc = "/opt/edg";
    if ($config->elementExists($edgpath)) {
        $edgloc = $config->getValue($edgpath);
    }

    # Look for WP1 variable definitions and "source" file if it
    # it exists.
    my $href = sourceFile("$edgloc/etc/edg-wl-vars.sh");
    %wp1vars = %$href;

    # Setup a default if the EDG_WL_TMP isn't defined. 
    if (!defined($wp1vars{EDG_WL_TMP})) {
	$wp1vars{EDG_WL_TMP} = 
	    defined($ENV{EDG_WL_TMP}) ? $ENV{EDG_WL_TMP} : "/var/edgwl";
    }

    # Set EDG_WL_USER to the value from the configuration file.
    # Only do this if it isn't defined as a variable.  Use the 
    # default otherwise. 
    my $user = $config->getValue("$base/user");
    $wp1vars{EDG_WL_USER} = $user unless ($user =~ m/^\$.*/);

    # EDG_WL_TMP is a path which must exist.  If it does not, then
    # create it.
    my $path = $wp1vars{EDG_WL_TMP};
    mkpath($path,0,0755) unless (-d $path);
    unless (-d $path) {
	$self->error("$path can't be created");
	return 1;
    }

    # Make sure mode is set to 0755.
    chmod 0755, $path;

    # Change the owner of all of the contents of this path. 
    find(\&changeOwner, ($path));
    
    # Default location for EDG var area.
    my $varloc = "$edgloc/var";
    if ($config->elementExists($edgvarpath)) {
        $varloc = $config->getValue($edgvarpath); 
    }

    # Ensure that the configuration path exists.
    my $etcpath = "$edgloc/etc";
    mkpath($etcpath,0,0755) unless (-d $etcpath);
    unless (-d $etcpath) {
	$self->error("$etcpath can't be created");
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

    # Make log, run, and profile.d area.  
    $path = "$varloc/log";
    mkpath($path,0,0755) unless (-d $path);
    unless (-d $path) {
	$self->error("$path can't be created");
    }
    $path = "$varloc/run";
    mkpath($path,0,0755) unless (-d $path);
    unless (-d $path) {
	$self->error("$path can't be created");
    }
    $path = "$varloc/etc/profile.d";
    mkpath($path,0,0755) unless (-d $path);
    unless (-d $path) {
	$self->error("$path can't be created");
    }

    # Make copy of configuration files. 
    my $name = "etc/profile.d/edg-wl-config.sh";
    copy("$edgloc/$name","$varloc/$name");
    $self->error("error copying $name") if $?;

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


# This subroutine "sources" the given file and returns the values in
# a hash reference. 
sub sourceFile {

    my ($file) = @_;

    my %hash = ();

    if (-f $file) {
	open FILE, "<$file";
	while (<FILE>) {
	    chomp;

	    if (/^\s*\#/) {
		
		# Ignore comments.
		
	    } elsif (/(\w+)=\${\w+:[-=]([^}]+)}(\s*\#.*)?/) {

		my $key = $1;
		my $value = $2;
		$hash{$key} = $value;

	    } elsif (/(\w+)=(\w+([^\#]*[^\#\s]+)?)(\s*\#.*)?/) {

		my $key = $1;
		my $value = $2;
		$hash{$key} = $value;
	    }
	}
	close FILE;
    }

    return \%hash;
}


# Change owner of a file to $wp1vars{EDG_WL_USER}; this is a global
# hash.
sub changeOwner {

    my $name = $File::Find::name;
    my $owner = $wp1vars{EDG_WL_USER};
    my $current_uid = (stat($name))[4];
    my $wluser_gid = (getpwnam($owner))[3];
    chown($current_uid, $wluser_gid, $name);
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
	my $element = $config->getElement($path);

	# WARNING: This will ignore any elements of the list which are not properties.
	if ($element->isType(EDG::WP4::CCM::Element::LIST)) {
	    my @items;
	    while ($element->hasNextElement()) {
		my $item = $element->getNextElement();
		if ($item->isType(EDG::WP4::CCM::Element::PROPERTY)) {
		    if ($item->isType(EDG::WP4::CCM::Element::STRING)) {
			push @items, '"' . $item->getValue() . '"';
		    } else {
			push @items, $item->getValue();
		    }
		}
	    }
	    $value = '{' . join(',',@items) . '}';
	} else {
	    $value = $config->getValue($path);
	}
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


1;      # Required for PERL modules
