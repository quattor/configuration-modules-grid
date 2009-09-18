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

# List of directories invalid for BDII working directories.
# Value is useless
my %forbiddenDirs = ('/' => '',
                     '/opt' => '',
                     '/tmp' => '',
                     '/usr' => '',
                     '/var' => '',
                     '/var/log' => '',
                    );

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
    my $result;

    # Retrieve configuration in a hash
    my $lcgbdii_config = $config->getElement($base)->getTree();

    # Retrieve user running BDII
    my $user = $lcgbdii_config->{user};

    # Retrieve BDII working directory and create/update owner
    # Create the directory if necessary.
    my $varDir = $lcgbdii_config->{varDir};
    unless ( $self->createAndChownDir($user,$varDir) ) {
      return 1;
    };
    
    # Retrieve BDII logging directory and create/update owner
    # Create the directory if necessary.
    my $logFile = $lcgbdii_config->{logFile};
    if ( $logFile ) {
      unless ( $self->createAndChownDir($user,dirname($logFile)) ) {
        return 1;
      };      
    }
    

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
    unless ( $self->createAndChownDir($user,$dir) ) {
      return 1;
    };
    
    # Fill template and get results.  Template substitution is simple
    # value replacement.  If a value doesn't exist, the line is not
    # output to the file.  
    my $contents = $self->fill_template($config, $base, $tfile);

    # Will return undefined value on an error. 
    if (!defined($contents)) {
        $self->error("error filling template $tfile");
        return 1;
    }

    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    # Already exists. Make backup and create new file. 
    $result = LC::Check::file($lcgbdii_config->{configFile},
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
    my $bdiiConfDir = $lcgbdii_config->{dir}.'/etc';
    unless ( $self->createAndChownDir($user,$bdiiConfDir) ) {
      return 1;
    };
    my $fname = "$bdiiConfDir/etc/bdii-update.conf";

    # Create the contents.
    $contents = "#\n# Created and maintained by ncm-lcgbdii. DO NOT EDIT.\n#\n";
    
    if ( defined($lcgbdii_config->{urls}) ) {
        foreach (sort keys %{$lcgbdii_config->{urls}}) {
            $contents .= $_ . " " . $lcgbdii_config->{urls}->{$_} . "\n";
        }
    }
    
    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    $result = LC::Check::file($fname,
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
    $self->createDir($dir);

    # Create the contents.  Just a list of the schema files.
    $contents = '';
    foreach (@{$lcgbdii_config->{schemas}}) {
        $contents .= $_ . "\n";
    }

    # Now just create the new configuration file.  Be careful to save
    # a backup of the previous file if necessary. 
    $result = LC::Check::file($lcgbdii_config->{schemaFile},
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

    my ($self,$config, $base, $template) = @_;

    my $translation = "";

    if (-e "$template") {
    open TMP, "<$template";
    while (<TMP>) {
            my $err = 0;

            # Special form for date.
            s/<%!date!%>/localtime()/eg;

            # Need quoted result (escape embedded quotes).
            s!<%"\s*(/[\w/]+)\s*(?:\|\s*(.+?))?\s*"%>!quote($self->fill($config,$1,$2,\$err))!eg;
            s!<%"\s*([\w]+[\w/]*)(?:\|\s*(.+?))?\s*"%>!quote($self->fill($config,"$base/$1",$2,\$err))!eg;

            # Normal result OK. 
            s!<%\s*(/[\w/]+)\s*(?:\|\s*(.+?))?%>!$self->fill($config,$1,$2,\$err)!eg;
            s!<%\s*([\w]+[\w/]*)\s*(?:\|\s*(.+?))?%>!$self->fill($config,"$base/$1",$2,\$err)!eg;

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


# Return the value to use.
# If no value is defined, use the default value if it exists or return an error.
# Escape quotes in a string value.
# Return list as a quoted space-separated string.
sub fill {
    my ($self,$config,$path,$default,$errorRef) = @_;

    my $value = "";

    if ($config->elementExists($path)) {
        if ( $config->getElement($path)->isType($config->getElement($path)->LIST) ) {
            $self->debug(2,"$path is a list. Converting to a space-separated string");
            $value = '"' . join(' ', @{$config->getElement($path)->getTree()}) . '"';
            $self->debug(2,"$path value converted to string $value");
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

# Create a directory if it doesn't exist and change ownership
# of its contents recursively.
# This method also checks that the directory is dedicated to BDII and is
# not one of the standard directories.
# Returns 1 in case of success, else 0
sub createAndChownDir {
    my ($self, $user, $dir) = @_;
    
    if ( defined($forbiddenDirs{$dir}) ) {
      $self->error("$dir is a system directory and cannot be used as a BDII-specific directory."); 
      return 0;      
    }

    unless ( $self->createDir($dir) ) {
      return 0;
    };
  
    my ($uid,$gid) = (getpwnam($user))[2,3];
    unless ( defined($uid) ) {
      $self->error("Failed to retrieved uid for user $user");
      return 0;
    }
    unless ( defined($gid) ) {
      $self->error("Failed to retrieved gid for user $user");
      return 0;
    }
    
    unless ( $self->chownDirAndChildren($uid,$gid,$dir) ) {
      return 0;
    };
    
    return 1;
}

# Create a directory.
# Returns 1 in case of success, else 0
sub createDir {
    my ($self, $dir) = @_;

    mkpath($dir,0,0755);
    # If a file with the same name already existed, throw an error.
    if ( !-d $dir ) {
      if ( -e $dir ) {
        $self->error("$dir exists but is not a directory");
      } else {
        $self->error("Failed to create directory $dir");
      }
      return 0;
    }
    
    return 1;
}

# Change ownership of a directory and its contents, recursively
# This method also checks that the directory/file is not one of the standard directories.
# Returns 1 in case of success, else 0.
sub chownDirAndChildren {
  my ($self, $uid, $gid, $file) = @_;
  if ( @_ != 4 ) {
    $self->error('chownDirAndChildren method requires 3 argments');
    return 0;
  }
  unless ( defined($file) && (length($file) > 0) ) {
    $self->error('directory/file name not specified');
    return 0;
  }
 
  if ( defined($forbiddenDirs{$file}) ) {
    $self->error("$file is a system directory: its permission cannot be changed to a BDII-specific one."); 
    return 0;      
  }

  $self->debug(1,"Updating $file owner to uid=$uid, gid=$gid");
  chown($uid,$gid,$file);

  # If $file is a directory, process its contents recursively (files and directories only)
  if ( -d $file ) {
    my @children = glob("$file/*");
    for my $child (@children) {
      if ( (-f $child || -d $child) && !-l $child && ($child ne $file) ) {
        unless ($self->chownDirAndChildren ($uid,$gid,$child) ) {
          return 0;
        }
      } else {
        $self->debug(2,"$child is neither a directory nor a file. Ignoring...");
      }
    }
  }
  
  return 1;
}

1;      # Required for PERL modules
