# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::gridmapdir;

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
use LC::Check;

local(*DTA);


##########################################################################
sub Configure($$@) {
##########################################################################
    
    my ($self, $config) = @_;

    # Load configuration in a perl hash
    my $gridmapdir_config = $config->getElement('/software/components/gridmapdir')->getTree();
    my $user_config = $config->getElement('/software/components/accounts/users')->getTree();

    # Retrieve gridmapdir location and attributes and check if it is shared
    my $gridmapdir = $gridmapdir_config->{gridmapdir};
    my $gridmapdir_owner = $gridmapdir_config->{owner};
    my $gridmapdir_group = $gridmapdir_config->{group};
    my $gridmapdir_perms = $gridmapdir_config->{perms};
    my $sharedGridmapdirPath = $gridmapdir_config->{sharedGridmapdir};

    # Check if gridmapdir exists and has the appropriate type.
    # The type must be a directory if not shared or a symlink if shared.
    # When shared, this component requires that the shared gridmapdir path already exists
    # and will not create it.
    # If shared and the existing gridmapdir type is a directory, rename it before creating the symlink.
    # If the existing gridmapdir path is a symlink but gridmapdir is not shared remove symlink and create
    # a new directory.
    
    my $restoreOnFailure = 0;
    my $gridmadir_bck = $gridmapdir.'.unshared';
    if ( -e $gridmapdir ) {
      if ( -d $gridmapdir ) {
        if ( $sharedGridmapdirPath ) {
          $self->debug(1,"gridmapdir configured to be shared: renaming existing gridmapdir");
          my $status = move($gridmapdir, $gridmadir_bck);
          if ( $status ) {
            $restoreOnFailure = 1;
          } else {
            $self->error("Failed to rename existing gridmapdir before configuring shared gridmapdir: $_");
            return 1;
          }
        } else {
          my $status = LC::Check::status($gridmapdir,
                                         'owner' => $gridmapdir_owner,
                                         'group' => $gridmapdir_group,
                                         'mode' => $gridmapdir_perms,
                                        );
        }
      } elsif ( -l $gridmapdir ) {
        if ( ! $sharedGridmapdirPath ) {
          $self->debug(1,"gridmapdir not shared: removing existing gridmapdir symlink");
          unlink $gridmapdir;
        };
      };
    }
    
    unless ( -e $gridmapdir ) {
      if ( $sharedGridmapdirPath ) {
        if ( -d $sharedGridmapdirPath ) {
          $self->info("gridmapdir configured as shared ($sharedGridmapdirPath)");
          my $status = symlink $sharedGridmapdirPath, $gridmapdir;
          if ( ! $status ) {
            $self->error("Failed to configure shared gridmapdir");
            return 1;
          }
        } else {
          $self->error("Failed to configure shared gridmapdir ($sharedGridmapdirPath doesn't exist)");
          if ( $restoreOnFailure ) {
          my $status = move($gridmapdir_bck, $gridmadir);
            if ( ! $status ) {
              $self->error("Failed to restore original gridmapdir: $_");
              return 1;
            }
          }
        }
      } else {
        mkpath($gridmapdir,0,0755) unless (-e $gridmapdir);
        unless (-d $gridmapdir) {
          $self->error("Failed to create $gridmapdir directory");
          return 1;
        }
      }
    }
              
    # Read all of the files in that directory except the hidden
    # files. 
    opendir DIR, "$gridmapdir";
    my @files = map {"$gridmapdir/$_"} grep {!/^\./} readdir DIR;
    closedir DIR;

    # Create two hashes, one which hashes the inode number to a list
    # of file names and the second one which hashes just the file
    # names. 
    my %inodes = ();
    my %existing = ();
    $self->debug(1,"Collecting existing gridmapdir entries...");

    foreach (@files) {
    
      # Inode map.
      my $inode = (stat($_))[1];
      if (defined($inodes{$inode})) {
          my $lref = $inodes{$inode};
          push @$lref, $_;
      } else {
          my @a;
          push @a, $_;
          $inodes{$inode} = \@a;
      };
          
      # Existing files.
      $existing{$_} = $inode;
    }
    
    $self->debug(1,"Found ".scalar(keys(%existing))." entries (".scalar(keys(%inodes))." inodes)");

    # Now create a hash of all of the desired files.
    my %desired = ();
    foreach my $prefix (keys(%{$gridmapdir_config->{poolaccounts}})) {
      # Base configuration for  these pool accounts from accounts component
      my $poolStart = $user_config->{$prefix}->{poolStart};
      unless ( defined($poolStart) ) {
        $poolStart = 0;
        $self->debug(2,"poolStart not defined for $prefix: use default value ($poolStart)");
      }
      # If poolSize undefined in accounts configuration, use the size from ncm-gridmapdir component.
      # This is considered as dangerous and deprecated, normally this is required to be 0 in the schema.
      my $poolSize = $user_config->{$prefix}->{poolSize};
      unless ( defined($poolSize) ) {
        $poolSize = $gridmapdir_config->{poolaccounts}->{$prefix};
        $self->debug(2,"poolSize not defined for $prefix: use default value ($poolSize)");
      }
      my $poolEnd = $poolStart + $poolSize - 1;
      my $poolDigits = $user_config->{$prefix}->{poolDigits};
      unless ( defined($poolDigits) ) {
        $poolDigits = length("$poolEnd");
        $self->debug(2,"poolDigits not defined for $prefix: use default value ($poolDigits)");
      }

      # Set up sprintf format specifier
      my $field = "%0" . $poolDigits . "d";

      $self->debug(1,"Adding pool accounts $prefix to desired entries (start=$poolStart, end=$poolEnd)...");

      foreach my $i ($poolStart .. $poolEnd) {
        my $fname=sprintf($prefix.$field, $i);
        $desired{"$gridmapdir/$fname"} = 1;
      }
    }

    $self->debug(1,"Total number of desired entries: ".scalar(keys(%desired))." (some may already exist)");

    # Remove duplicates between the hashes.  These already exist and
    # are needed in the configuration, so nothing needs to be done. 
    foreach (keys %desired) {
      if (defined($existing{$_})) {
        my $inode = $existing{$_};
        foreach (@{$inodes{$inode}}) {
          delete($desired{$_}) if (exists($desired{$_}));
          delete($existing{$_}) if (exists($existing{$_}));
        }
      }
    }

    # Any files which remain in the 'existing' hash are not wanted.
    # Make sure that they are deleted.
    if ( %existing ) {
      $self->info("Deleting no longer needed entries (".scalar(keys(%existing)).")...");
      foreach (keys %existing) {
        unlink $_;
      }
    }

    # Now touch the files in the 'desired' hash to make sure everything
    # exists.
    if ( %desired ) { 
      $self->info("Adding new entries (".scalar(keys(%desired)).")...");
      foreach (keys %desired) {
        open FILE, ">$_";
        close FILE;
        if ( $? ) {
          $self->warn("Error creating file: $_");
        }
      }
    }

    return 1;
}

1;      # Required for PERL modules
