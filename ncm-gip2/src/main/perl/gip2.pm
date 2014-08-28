# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gip2;

use strict;
use warnings;
use NCM::Component;
our @ISA = qw(NCM::Component);
our $EC=LC::Exception::Context->new->will_store_all;
use EDG::WP4::CCM::Element qw(unescape);

use CAF::Process;
use CAF::FileWriter;

use Encode qw(encode_utf8);
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
    my $user = $gip_config->{user};
    my $group = $gip_config->{group};

    # Retrieve GIP flavor (lcg or glite)
    my $flavor = $gip_config->{flavor};

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
    my $workDirs = $gip_config->{workDirs};
    if ( $flavor eq 'glite' ) {
        $etcDir = "$baseDir/etc/gip";
        $ldifDir = "$etcDir/ldif";
        $pluginDir = "$etcDir/plugin";
        $providerDir = "$etcDir/provider";
        unless ( $workDirs ) {
            $workDirs = [
                "$baseDir/tmp/gip",
                "$baseDir/lock/gip",
                "$baseDir/cache/gip",
            ];
        }
    } else {
        $workDirs = ["$baseDir/tmp"] unless $workDirs;
    }
    $etcDir = $gip_config->{etcDir} if ( exists($gip_config->{etcDir}) );
    $ldifDir = $gip_config->{ldifDir} if ( exists($gip_config->{ldifDir}) );
    $pluginDir = $gip_config->{pluginDir} if ( exists($gip_config->{pluginDir}) );
    $providerDir = $gip_config->{providerDir} if ( exists($gip_config->{providerDir}) );

    # Build a list of all files managed by this component that will be
    # used to determine if a file must be removed from GIP directories.
    my %managedFiles;
    for my $fileType ('ldif', 'plugin', 'provider', 'scripts', 'stubs', 'standardOutput', 'external') {
        $self->debug(1, "Adding $fileType files to list of managed files");
        my $filePath;
        my @fileList;
        next if ! $gip_config->{$fileType};

        # Scripts and redirects have no implicit file path, the script path is the key (escaped)
        if ( $fileType eq 'scripts' || $fileType eq 'standardOutput' ) {
            for my $efile (keys(%{$gip_config->{$fileType}})) {
                push @fileList, unescape($efile);
            }

        # LDIF files are normally located in $ldifDir. It is also possible to
        # have LDIF files at arbitrary locations using an absolute file path.
        # Do not process them specifically here, the resulting entry will never
        # match.
        # The LDIF file is in ldifFile property of each entry.
        } elsif ( $fileType eq 'ldif' ) {
            $filePath = $ldifDir;
            for my $entry (keys(%{$gip_config->{$fileType}})) {
                push @fileList, $gip_config->{$fileType}->{$entry}->{ldifFile};
            }

        # External files, the path is the escaped string
        } elsif ( $fileType eq 'external' ) {
            for my $efile (@{$gip_config->{$fileType}}) {
                push @fileList, unescape($efile);
            }

        # Other file types: the key is the file name relative to the file type directory.
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
            $self->debug(1, "Managed file : $file")
        }
    }

    # The contents of directories managed by this component must be cleared
    # out of any files not managed by this component to ensure old information
    # isn't published or that temporary files are removed from plugin and provider directories.
    foreach my $dir ($ldifDir, $pluginDir, $providerDir) {
        next if ! -d $dir;
        $self->debug(1, "Removing existing files in $dir...");
        opendir DIR, $dir;
        my @delete = grep !/^\./, readdir DIR;
        closedir DIR;
        foreach my $f (@delete) {
            my $file = "$dir/$f";
            if ( defined($managedFiles{$file}) ) {
                $self->debug(1, "File $file managed by ncm-gip2. Not removed.");
            } else {
                $self->info(1, "File $file removed (not part ncm-gip2 configuration).");
                unlink $file; 
            }
        }
    }

    # Ensure that the necessary directories exist and has the correct owner/group and perms.
    # Do this recursively.

    $rc = $self->createAndChownDir("root", "root", $etcDir, 0755, 1);
    return 1 if ($rc);

    $rc = $self->createAndChownDir("root", "root", $pluginDir, 0755);
    return 1 if ($rc);

    $rc = $self->createAndChownDir("root", "root", $providerDir, 0755);
    return 1 if ($rc);

    $rc = $self->createAndChownDir($user, $group, $ldifDir, 0755);
    return 1 if ($rc);

    for my $dir (@{$workDirs}) {
        $rc = $self->createAndChownDir($user, $group, $dir, 0775);
        return 1 if ($rc);
    }

    # Process all of the defined LDIF files.

    if ( $gip_config->{ldif} ) {

        # Retrieve the command to use for generating the static
        # LDIF information.
        my $staticInfoCmd = $gip_config->{staticInfoCmd};

        # Ensure that the command exists and is executable.
        if (! -f $staticInfoCmd) {
            $self->error("$staticInfoCmd does not exist");
            return 1;
        }
        if (! -x $staticInfoCmd) {
            $self->error("$staticInfoCmd is not executable");
            return 1;
        }

        my $files = $gip_config->{ldif};
        foreach my $file (sort keys %$files) {
            my $entry = $files->{$file};

            # Get the output LDIF file name.
            # It can be an absolute or relative path. If relative, prefix with $ldifDir.
            my $ldifFile = $entry->{ldifFile};
            if ( $ldifFile !~ /^\// ) {
                $ldifFile = $ldifDir . '/' . $ldifFile;
            }
            $self->debug(1, 'Processing entry for LDIF file ' . $ldifFile);

            # Ensure that the template file exists.
            my $template = $entry->{template};
            if (! -f $template) {
                $self->warn("$template does not exist; skipping LDIF file " . $ldifFile . "...");
                next;
            }

            # Create the configuration file with LDIF info.
            my $contents = '';

            my $ldifEntries = $entry->{entries};
            for my $dn (sort keys %$ldifEntries) {
                $contents .= unescape($dn) . "\n";
                my $attrs = $ldifEntries->{$dn};
                foreach my $key (sort keys %$attrs) {
                    foreach my $v (@{$attrs->{$key}}) {
                        my $value = $v;
                        $contents .= "$key: $value\n";
                    }
                }
                $contents .= "\n";
            }

            # Write out the configuration file.
            my $fh = CAF::FileWriter->new("$etcDir/$file", mode => 0644, log=> $self);
            print $fh encode_utf8($contents);
            my $changes = $fh->close();
            if ( $changes < 0 ) {
                $self->error("Error updadating LDIF configuration file $etcDir/$file");
            }

            # Run the command to generate the LDIF file.
            # A temporary LDIF file is produced and then the LDIF file is updated
            # with the temporary file if the content was changed.
            my $staticInfoArgs = "-c $etcDir/$file -t $template";
            $staticInfoArgs = $entry->{staticInfoArgs} if ( exists($entry->{staticInfoArgs}) );
            my $cmd = "$staticInfoCmd $staticInfoArgs";
            CAF::Process->new([$cmd], log => $self, stdout => \$contents)->execute();
            if ($?) {
                $self->error("Error generating LDIF file (command=$cmd)");
            } else {
                $fh = CAF::FileWriter->new($ldifFile, mode => 0644, log=> $self);
                print $fh encode_utf8($contents);
                $changes = $fh->close();
                if ( $changes < 0 ) {
                    $self->error("Error updadating $ldifFile");
                }
            }
        }
    }


    # Process all of the plugins.

    if ( $gip_config->{plugin} ) {
        my $files = $gip_config->{plugin};

        foreach my $file (sort keys %$files) {
            my $pluginFile = $pluginDir . "/" . $file;
            $self->debug(1, 'Processing entry for plugin ' . $pluginFile);
            my $contents = $files->{$file};

            # Write out the file.
            my $fh = CAF::FileWriter->new($pluginFile, mode => 0755, log=> $self);
            print $fh encode_utf8($contents);
            my $changes = $fh->close();
            if ( $changes < 0 ) {
                $self->error("Error updadating $pluginFile");
            }
        }
    }


    # Process all of the providers.

    if ( $gip_config->{provider} ) {
        my $files = $gip_config->{provider};

        foreach my $file (sort keys %$files) {
            my $providerFile = $providerDir . "/" . $file;
            $self->debug(1, 'Processing entry for provider ' . $providerFile);
            my $contents = $files->{$file};

            # Write out the file.
            my $fh = CAF::FileWriter->new($providerFile, mode => 0755, log=> $self);
            print $fh encode_utf8($contents);
            my $changes = $fh->close();
            if ( $changes < 0 ) {
                $self->error("Error updadating $providerFile");
            }
        }
    }


    # Process all of the scripts. Can be anywhere in filesystem.

    if ( $gip_config->{scripts} ) {
        my $files = $gip_config->{scripts};

        foreach my $efile (sort keys %$files) {

            # Extract the file name and contents from the configuration.
            my $file = unescape($efile);
            $self->debug(1, 'Processing entry for script ' . $file);
            my $contents = $files->{$efile};

            # Write out the file.
            my $fh = CAF::FileWriter->new($file, mode => 0755, log=> $self);
            print $fh encode_utf8($contents);
            my $changes = $fh->close();
            if ( $changes < 0 ) {
                $self->error("Error updadating $file");
            }
        }
    }

    # Process all of configuration files used by GIP components. Can be anywhere in filesystem.

    if ( $gip_config->{confFiles} ) {
        my $files = $gip_config->{confFiles};

        foreach my $efile (sort keys %$files) {

            # Extract the file name and contents from the configuration.
            my $file = unescape($efile);
            $self->debug(1, 'Processing entry for configuration file ' . $file);
            my $contents = $files->{$efile};

            # Write out the file.
            my $fh = CAF::FileWriter->new($file, mode => 0644, log=> $self);
            print $fh encode_utf8($contents);
            my $changes = $fh->close();
            if ( $changes < 0 ) {
                $self->error("Error updadating $file");
            }
        }
    }

    # Process standardOutput entries
    if ( $gip_config->{standardOutput} ) {
        my $files = $gip_config->{standardOutput};
        foreach my $efile (sort keys %$files) {
            # Extract the file name from the configuration
            my $targetFile = unescape($efile);
            $self->debug(1, 'Processing entry for standardOutput file ' . $targetFile);
            # Extract the command and arguments name from the configuration
            my $entry = $files->{$efile};
            my $cmd = "$entry->{command} $entry->{arguments}";
            $self->debug(2, ' ... with command: ' . $cmd);
            # Execute the command and keep the standard output
            my $contents = '';
            CAF::Process->new([$cmd], log => $self, stdout => \$contents)->execute();
            if ($?) {
                $self->error("Error while generating standardOutput file (command=$cmd)");
            } else {
                # Create/update the target file
                my $fh = CAF::FileWriter->new($targetFile, mode => 0644, log=> $self);
                print $fh encode_utf8($contents);
                my $changes = $fh->close();
                if ( $changes < 0 ) {
                    $self->error("Error updadating $targetFile");
                }
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

        foreach my $stubFile (sort keys %$files) {
            my $ldifEntries = $files->{$stubFile};
            my $file = $ldifDir . "/" . $stubFile;
            $self->debug(1, 'Processing entry for stub ' . $file);

            my $contents = '';
            for my $dn (sort keys %$ldifEntries) {
                $contents .= unescape($dn) . "\n";
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
            my $fh = CAF::FileWriter->new($file, mode => 0644, log=> $self);
            print $fh encode_utf8($contents);
            my $changes = $fh->close();
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
        if ( -x $bdii_startup) {
            CAF::Process->new(["$bdii_startup status >/dev/null"], log => $self)->run();
            if (! $?) {
                $self->info("Restarting BDII...");
                CAF::Process->new(["$bdii_startup condrestart"], log => $self)->run();
            }
        }
    }

    # Done.
    return 1;
}


# Untaint file/directory name

sub untaintFileName {
  my ($self, $filename) = @_;
  if ($filename =~ /^([-\@\w.\/]+)$/) {
    return $1;
  } else {
    $self->error("Invalid file name ($filename)");
    return;
  }
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
    mkpath($dir, 0, 0755) unless (-e $dir);
    if (! -d $dir) {
        $self->error("Error creating directory: $dir");
        return 1;
    }
    my $cnt = chown($uid, $gid, $self->untaintFileName($dir));
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
        $self->debug(2, "Processing $entry in $dir");
        my $f = "$dir/$entry";
        if ( -d $f ) {
            if ( $norecurse ) {
                $self->debug(2, "Nothing done (non recursive flag set)");
            } else {
                my $rc = $self->createAndChownDir($user, $group, $f, $mode);
                return 1 if ($rc);
            }
        } else {
            $self->debug(1, "Setting owner and group on $f");
            my $cnt = chown($uid, $gid, $self->untaintFileName($f));
            if ( $cnt == 0 ) {
                $self->warn("Error setting owner/group on $f");
            }
        }
    }

    return 0;
}

1; # Required for PERL modules
