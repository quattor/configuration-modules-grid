# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::condorconfig;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;

use File::Path;
use File::Basename;


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Define paths for convenience. 
    my $base = "/software/components/condorconfig";
    my $tfile = "/usr/lib/ncm/config/condorconfig/condorconfig.template";

    # The condor username. 
    my $user;
    if ($config->elementExists("$base/user")) {
        $user = $config->getValue("$base/user");
    } else {
	$self->error("condor username not specified");
	return 1;
    }

    # The LOCAL_DIR value.
    my $local_dir = "/var/local/condor";
    if ($config->elementExists("$base/LOCAL_DIR")) {
        $local_dir = $config->getValue("$base/LOCAL_DIR");
    }

    # Make the local_dir and change ownership.
    createAndChownDir($user,$local_dir);
    unless (-d $local_dir) {
	$self->error("cannot create $local_dir");
	return 1;
    }

    # The LOG value.
    my $log_dir = "$local_dir/log";
    if ($config->elementExists("$base/LOG")) {
        $log_dir = $config->getValue("$base/LOG");
    }

    # Make the log_dir and change ownership.
    createAndChownDir($user,$log_dir);
    unless (-d $log_dir) {
	$self->error("cannot create $log_dir");
	return 1;
    }

    # The SPOOL value.
    my $spool_dir = "$local_dir/spool";
    if ($config->elementExists("$base/SPOOL")) {
        $spool_dir = $config->getValue("$base/SPOOL");
    }

    # Make the spool_dir and change ownership.
    createAndChownDir($user,$spool_dir);
    unless (-d $spool_dir) {
	$self->error("cannot create $spool_dir");
	return 1;
    }

    # The EXECUTE value.
    my $execute_dir = "$local_dir/execute";
    if ($config->elementExists("$base/EXECUTE")) {
        $execute_dir = $config->getValue("$base/EXECUTE");
    }

    # Make the execute_dir and change ownership.
    createAndChownDir($user,$execute_dir);
    unless (-d $execute_dir) {
	$self->error("cannot create $execute_dir");
	return 1;
    }

    # The GRIDLOG value.
    my $gridlog_dir = "$local_dir/GridLogs";
    if ($config->elementExists("$base/GRIDMANAGER_LOG")) {
        $gridlog_dir = $config->getValue("$base/GRIDMANAGER_LOG");
	$gridlog_dir = dirname($gridlog_dir);
    }

    # Make the gridlog_dir and change ownership.
    createAndChownDir($user,$gridlog_dir);
    unless (-d $gridlog_dir) {
	$self->error("cannot create $gridlog_dir");
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

    # Use the default name if one has not been given.  Make it an 
    # absolute path if necessary.
    my $configFile;
    if ($config->elementExists("$base/configFile")) {
        $configFile = $config->getValue("$base/configFile");
    } else {
	$self->error("Configuration file name not specified");
	return 1;
    }

    # Use the default name if one has not been given.  Make it an 
    # absolute path if necessary.
    my $fname;
    if ($config->elementExists("$base/localConfigFile")) {
        $fname = $config->getValue("$base/localConfigFile");
    } else {
	$self->error("local configuration file name not specified");
	return 1;
    }

    # The LOCALCONF value.
    my $localconf_dir = dirname($fname);
    createAndChownDir($user,$localconf_dir);
    unless (-d $localconf_dir) {
	$self->error("cannot create $localconf_dir");
	return 1;
    }

    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    my $result = LC::Check::file( $fname,
                                  backup => ".old",
                                  contents => $contents,
                                );
    $self->log("$fname updated") if $result;

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
