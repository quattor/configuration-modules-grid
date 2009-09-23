# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gip2;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use LC::Check;

use Encode qw(encode_utf8);

use EDG::WP4::CCM::Element qw(unescape);

use File::Path;
use File::Basename;

local(*DTA);


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    my $rc;
    my $restartBDII = 0;
    
    # Define paths for convenience. 
    my $base = "/software/components/gip2";

    # Retrieve configuration
    my $gip_config = $config->getElement($base)->getTree();
    
    my $bdiiRestartAllowed = 0;
    if ( exists($gip_config->{bdiiRestartAllowed}) ) {
      $bdiiRestartAllowed = $gip_config->{bdiiRestartAllowed};
    }
    # Retrieve the user and group for running gip scripts.
    my $user =  $gip_config->{user};
    my $group =  $gip_config->{group};

    # Retrieve GIP flavor (lcg or glite)
    my $flavor =  $gip_config->{flavor};

    # Determine the base directory for the gip configuration.
    # Ensure that this directory exists. 
    my $baseDir = $gip_config->{basedir};
    if ( ! -d $baseDir ) {
      return 1;
    }
    
    # Define the required subdirectories according to flavor.
    my $etcDir = "$baseDir/etc";
    my $ldifDir = "$baseDir/ldif";
    my $pluginDir = "$baseDir/plugin";
    my $providerDir = "$baseDir/provider";
    my @workDirs = $gip_config->{workDirs};
    if ( $flavor eq 'glite' ) {
      $etcDir = "$baseDir/etc/gip";
      $ldifDir = "$etcDir/ldif";
      $pluginDir = "$etcDir/plugin";
      $providerDir = "$etcDir/provider";
      unless ( @workDirs ) {
        @workDirs = ("varDir/tmp/gip",
                     "varDir/lock/gip",
                     "varDir/cache/gip",
                    );        
      }
    } else {
      @workDirs = ("baseDir/tmp") unless @workDirs;
    }

    # Build a list of all files managed by this component
    my %managedFiles;
    for my $fileType ('ldif','plugin','provider','scripts','stubs') {
      $self->debug(1,"Adding $fileType files to list of managed files");
      my $filePath;
      my @fileList;
      next if ! $gip_config->{$fileType};
      
      if ( $fileType eq 'scripts' ) {
        for my $efile (keys(%{$gip_config->{$fileType}})) {
          push @fileList, unescape($efile);
        } 
      } elsif ( $fileType eq 'ldif' ) {
        $filePath = $ldifDir;
        for my $entry (keys(%{$gip_config->{$fileType}})) {
          push @fileList, $gip_config->{$fileType}->{$entry}->{ldifFile};
        }
      } else {
        @fileList = keys %{$gip_config->{$fileType}};
        if ( $fileType eq 'plugin' ) {
          $filePath = $pluginDir;
        } elsif ( $fileType eq 'provider' ) {
          $filePath = $providerDir;
        } elsif ( $fileType eq 'stubs' ) {
          $filePath = $ldifDir;
        }
      }
      
      for my $file (@fileList) {
        if ( defined($filePath) ) {
          $file = $filePath . "/" . $file;
        }
        $managedFiles{$file} = '';
      }
      
    }

    if ( %managedFiles ) {
      for my $file (keys(%managedFiles)) {
        $self->debug(1,"Managed file : $file")
      }      
    }
    
    # The contents of directories managed by this component must be cleared
    # out of any files not managed by this component to ensure old information
    # isn't published or that temporary files are removed from plugin and provider directories.
    foreach my $dir ($ldifDir,$pluginDir,$providerDir) {
      next if ! -d $dir;
      $self->debug(1,"Removing existing files in $dir...");
      opendir DIR, $dir;
      my @delete = grep !/^\./, readdir DIR;
      closedir DIR;
      foreach my $f (@delete) {
        my $file = "$dir/$f";
        if ( defined($managedFiles{$file}) ) {
          $self->debug(1,"File $file managed by this component. Not removed.");
        } else {
          unlink $file;          
        }
      }
    }

    # Ensure that the necessary directories exist and has the correct owner/group and perms.
    # Do this recursively.

    $rc = $self->createAndChownDir("root","root",$etcDir,0755,1);
    return 1 if ($rc);

    $rc = $self->createAndChownDir("root","root",$pluginDir,0755);
    return 1 if ($rc);

    $rc = $self->createAndChownDir("root","root",$providerDir,0755);
    return 1 if ($rc);

    $rc = $self->createAndChownDir($user,$group,$ldifDir,0755);
    return 1 if ($rc);

    for my $dir (@workDirs) {
      $rc = $self->createAndChownDir($user,$group,$dir,0775);
      return 1 if ($rc);
    }

    # Retrieve the command to use for generating the static
    # LDIF information. 
    my $staticInfoCmd =  $gip_config->{staticInfoCmd};

    # Ensure that the command exists and is executable.
    if (! -f $staticInfoCmd) {
      $self->error("$staticInfoCmd does not exist");
	    return 1;
    }
    if (! -x $staticInfoCmd) {
	    $self->error("$staticInfoCmd is not executable");
	    return 1;
    }


    # Process all of the defined LDIF files.

    if ( $gip_config->{ldif} ) {
      my $files = $gip_config->{ldif};

      foreach my $file (sort keys %$files) {
        my $entry = $files->{$file};
        my $template = $entry->{template};

        # Ensure that the template file exists.
        if (! -f $template) {
          $self->warn("$template does not exist; skipping...");
          next;
        }

        # Create the configuration file with LDIF info.
        my $contents = '';

        my $ldifEntries = $entry->{entries};
        for my $dn (sort keys %$ldifEntries) {
          $contents .= unescape($dn) ."\n";
          my $attrs = $ldifEntries->{$dn};
          foreach my $key (sort keys %$attrs) {
            foreach my $v (@{$attrs->{$key}}) {
              my $value = $v;
              $contents .= "$key: $value\n";
            }
          }
          $contents .= "\n";
        }

        # Get the output LDIF file name.
        my $ldifFile = $entry->{ldifFile};

        # Write out the file.
        my $changes = LC::Check::file(
                                      "$etcDir/$file",
                                      contents => encode_utf8($contents),
                                      mode => 0644,
                                     );
        if ( $changes < 0 ) {
          $self->error("Error updadating $etcDir/$file");
        }

        # Run the command to generate the LDIF file.
        my $cmd = "$staticInfoCmd -c $etcDir/$file -t $template > $ldifDir/$ldifFile";
        `$cmd`;
        if ($?) {
          $self->error("error running command: $cmd");
        } else {
          $self->info("updated file $ldifDir/$ldifFile");
        }
      }
    }


    # Process all of the plugins.

    if ( $gip_config->{plugin} ) {
      my $files = $gip_config->{plugin};

      foreach my $file (sort keys %$files) {
        my $contents = $files->{$file};

        # Write out the file.
        my $changes = LC::Check::file(
                                      "$pluginDir/$file",
                                      contents => encode_utf8($contents),
                                      mode => 0755,
                                     );
        if ( $changes < 0 ) {
          $self->error("Error updadating $pluginDir/$file");
        }
      }  
    }
    

    # Process all of the providers.

    if ( $gip_config->{provider} ) {
      my $files = $gip_config->{provider};

      foreach my $file (sort keys %$files) {
        my $contents = $files->{$file};

        # Write out the file.
        my $changes = LC::Check::file(
                                      "$providerDir/$file",
                                      contents => encode_utf8($contents),
                                      mode => 0755,
                                     );
        if ( $changes < 0 ) {
          $self->error("Error updadating $providerDir/$file");
        }
      }
    }


    # Process all of the scripts.  Can be anywhere in filesystem.

    if ( $gip_config->{scripts} ) {
      my $files = $gip_config->{scripts};

      foreach my $efile (sort keys %$files) {

       # Extract the file name and contents from the configuration.
        my $file = unescape($efile);
        my $contents = $files->{$efile};
 
        # Write out the file.
        my $changes = LC::Check::file(
                                      "$file",
                                      contents => encode_utf8($contents),
                                      mode => 0755,
                                     );
        if ( $changes < 0 ) {
          $self->error("Error updadating $file");
        }
      }
    }

    # Process all of configuration files used by GIP components.  Can be anywhere in filesystem.

    if ( $gip_config->{confFiles} ) {
      my $files = $gip_config->{confFiles};

      foreach my $efile (sort keys %$files) {

        # Extract the file name and contents from the configuration.
        my $file = unescape($efile);
        my $contents = $files->{$efile};

        # Write out the file.
        my $changes = LC::Check::file(
                                      "$file",
                                      contents => encode_utf8($contents),
                                      mode => 0644,
                                     );
        if ( $changes < 0 ) {
          $self->error("Error updadating $file");
        }
      }
    }

    # Process all LDIF stubs.
    # LDIF stubs are used to define additional LDIF entries not generated from Glue templates.
    # They are mainly used to add entries to get subtree searches to work.
    # If these entries are updated and BDII is running on the current node, it must be restarted
    # for the modification to take effect.

    if ( $gip_config->{stubs} ) {
      my $files = $gip_config->{stubs};

      foreach my $ldifFile (sort keys %$files) {
        my $contents = '';
        
        my $ldifEntries = $files->{$ldifFile};
        for my $dn (sort keys %$ldifEntries) {
          $contents .= unescape($dn) ."\n";
          my $attrs = $ldifEntries->{$dn};
          foreach my $key (sort keys %$attrs) {
            my $values = $attrs->{$key};
            foreach my $v (@$values) {
              $contents .= "$key: $v\n";
            }
          }
          $contents .= "\n";
        }

        # Write out the file.
        my $file = "$ldifDir/$ldifFile";
        my $changes = LC::Check::file(
                                      "$file",
                                      contents => encode_utf8($contents),
                                      mode => 0644,
                                     );
        if ( $changes < 0 ) {
          $self->error("Error updadating $file");
        } elsif ( $changes > 0 ) {
          $restartBDII = 1;
        }
      }
    }

    # Restart BDII if already running
    if ( $restartBDII && $bdiiRestartAllowed ) {
      my $bdii_startup = '/etc/init.d/bdii';
      if ( -x $bdii_startup && !system("$bdii_startup status >/dev/null") ) {
        $self->info("Restarting BDII...");
        system("$bdii_startup condrestart");        
      }
    }

    # Done. 
    return 1; 
}


# Change owner/group and set permissions on a directory and its contents
# Do it recursively, except if $norecurse is true

sub createAndChownDir {

    my ($self, $user, $group, $dir, $mode, $norecurse) = @_;
    my $uid = getpwnam($user);
    my $gid = getgrnam($group);

    unless ( defined($norecurse) ) {
      $norecurse = 0;
    }
    my $recurse_msg = '';
    if ( ! $norecurse ) {
      $recurse_msg = '(recursive)';
    }
    
    $self->info("Setting owner, group and permissions on directory $dir and its contents $recurse_msg");
    mkpath($dir,0,0755) unless (-e $dir);
    if (! -d $dir) {
      $self->error("Error creating directory: $dir");
      return 1;
    }
    my $cnt = chown($uid, $gid, $dir);
    if ( $cnt == 0 ) {
      $self->error("Error setting owner/group on directory: $dir");
      return 1;        
    }
    if ( defined($mode) ) {
      $cnt = chmod($mode, $dir);
      if ( $cnt == 0 ) {
        $self->error("Error setting permissions on directory: $dir");
        return 1;        
      }
    }

    # Set owner/group on existing files to fix inconsistencies, if any.
    # Recursively process sub-directories in current directory, except if $norecurse=1
    # (in this case sub-directories are ignored).
    opendir DIR, $dir;
    my @entries = grep !/^\./, readdir DIR;
    closedir DIR;
    foreach my $entry (@entries) {
      $self->debug(2,"Processing $entry in $dir");
      my $f = "$dir/$entry";
      if ( -d $f ) {
        if ( $norecurse ) {
          $self->debug(2,"Nothing done (non recursive flag set)");
        } else {
          my $rc = $self->createAndChownDir($user,$group,$f,$mode);
          return 1 if ($rc);
        }
      } else {
        $self->debug(1,"Setting owner and group on $f");
        my $cnt = chown($uid, $gid, glob($f));
        if ( $cnt == 0 ) {
          $self->warn("Error setting owner/group on $f");
        }
      }
    }
    
    return 0;
}

1;      # Required for PERL modules
