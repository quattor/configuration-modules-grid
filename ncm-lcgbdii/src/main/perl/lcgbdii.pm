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

    # Initializations
    my $date = localtime();
    my $changes = 0;

    # Retrieve configuration in a hash
    my $lcgbdii_config = $config->getElement($base)->getTree();


    #################################
    # Build BDII configuration file #
    #################################

    # The configuration file location.
    unless ( defined($lcgbdii_config->{configFile}) ) {
       $self->error("configuration file name not specified");
       return 1;
    }

    # Create the directory if necessary.
    my $dir = dirname($lcgbdii_config->{configFile});
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

    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    # Already exists. Make backup and create new file. 
    my $result = LC::Check::file($lcgbdii_config->{configFile},
                                 backup => ".old",
                                 contents => $contents,
                                );
    if ( $result > 0 ) {
        $self->log($lcgbdii_config->{configFile}." updated");
        $changes += $result;
    } elsif ( $result < 0 ) {
        $self->error("Failed to update ".$lcgbdii_config->{configFile})
    }

    # Change the owner to the one running the daemon.
    my $user = $lcgbdii_config->{user};
    chmod 0600, $lcgbdii_config->{configFile};
    chown((getpwnam($user))[2,3], glob($lcgbdii_config->{configFile}));


    ############################################
    # Build the BDII update configuration file #
    ############################################
    
    # The update configuration file location.
    unless ( defined($lcgbdii_config->{dir}) ) {
        $self->error("BDII base directory not specified");
        return 1;
    }
    my $bdiiDir = $lcgbdii_config->{dir};
    my $fname = "$bdiiDir/etc/bdii-update.conf";

    # Create the directory if necessary.
    $dir = dirname($fname);
    mkpath($dir,0,0755) unless (-e $dir);
    unless (-d $dir) {
        $self->error("cannot create directory $dir");
        return 1;
    }

    # Create the contents.
    $contents = "#\n# Created and maintained by ncm-lcgbdii. DO NOT EDIT.\n#\n";
    
    if ( defined($lcgbdii_config->{urls}) ) {
        foreach (sort keys %{$lcgbdii_config->{urls}}) {
            $contents .= $_ . " " . $lcgbdii_config->{urls}->{$_} . "\n";
        }
    }
    
    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    my $result = LC::Check::file($fname,
                                 backup => ".old",
                                 contents => $contents,
                                );
    if ( $result > 0 ) {
        $self->log($fname." updated");
        $changes += $result;
    } elsif ( $result < 0 ) {
        $self->error("Failed to update ".$fname)
    }

    # The file really only needs to be owned (and write-enabled) when
    # the autoModify flag is set, but does no harm in other cases. 
    chmod 0600, $fname;
    chown((getpwnam($user))[2,3], glob($fname));


    #########################
    # Build the schema file #
    #########################
    
    # The schema file location.
    unless ( defined($lcgbdii_config->{schemaFile}) && defined($lcgbdii_config->{schemas})  ) {
        $self->error("BDII schema specification missing");
        return 1;
    }

    # Create the directory if necessary.
    $dir = dirname($lcgbdii_config->{schemaFile});
    mkpath($dir,0,0755) unless (-e $dir);
    unless (-d $dir) {
        $self->error("cannot create directory $dir");
        return 1;
    }

    # Create the contents.  Just a list of the schema files.
    $contents = '';
    foreach (@{$lcgbdii_config->{schemas}}) {
        $contents .= $_ . "\n";
    }

    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    my $result = LC::Check::file($lcgbdii_config->{schemaFile},
                                 backup => ".old",
                                 contents => $contents,
                                );
    if ( $result > 0 ) {
        $self->log($lcgbdii_config->{schemaFile}." updated");
        $changes += $result;
    } elsif ( $result < 0 ) {
        $self->error("Failed to update ".$lcgbdii_config->{schemaFile})
    }
    
    # Restart the server if needed
    if ( $changes ) {
      if (system("/sbin/service bdii stop")) {
          $self->warn("init.d lcg-bdii stop failed: ". $?);
      }
      if (system("/sbin/service bdii start")) {
          $self->error("init.d lcg-bdii start failed: ". $?);
      }
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
        if ( $self->isType($self->LIST) ) {
            $value = join '"', @{$config->getElement($path)->getList()};          
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

# Change ownership by name.
sub createAndChownDir {

    my ($user, $dir) = @_;

    mkpath($dir,0,0755);
    chown((getpwnam($user))[2,3], glob($dir)) if (-d $dir);
}

1;      # Required for PERL modules
