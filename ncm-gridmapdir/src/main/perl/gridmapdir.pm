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
    my $gridmapdir_owner = $gridmapdir_config->{gridmapdir_owner};
    my $gridmapdir_group = $gridmapdir_config->{gridmapdir_group};
    my $gridmapdir_perms = $gridmapdir_config->{gridmapdir_perms};
    my $sharedGridmapdirPath = $gridmapdir_config->{sharedGridmapdir};

    # Check if gridmapdir exists and has the appropriate type.
    # The type must be a directory if not shared or a symlink if shared.
    # When shared, this component requires that the shared gridmapdir path already exists
    # and will not create it.
    # If shared and the existing gridmapdir type is a directory, rename it before creating the symlink.
    # If the existing gridmapdir path is a symlink but gridmapdir is not shared remove symlink and create
    # a new directory.

    if ( -e $gridmapdir ) {
      if ( -d $gridmapdir ) {
        if ( $sharedGridmapdirPath ) {
          $self->debug(1,"gridmapdir configured to be shared: renaming existing gridmapdir");
          mv ($gridmapdir, $gridmapdir.'.unshared');
        } else {
          my $status = LC::Check::status($gridmapdir,
                                         'owner' => 'root',
                                         'mode' => '0755',
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
          symlink $sharedGridmapdirPath, $gridmapdir;
        } else {
          $self->error("Failed to configure shared gridmapdir ($sharedGridmapdirPath doesn't exist)");
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
    
    $self->debug(1,"Found ".scalar(keys($existing))." entries (".scalar(keys($inodes))." inodes)");

    # Now create a hash of all of the desired files.
    my %desired = ();
    foreach my $prefix (keys(%{$gridmapdir_config->{poolaccounts}})) {
      my $pool_config = $gridmapdir_config->{poolaccounts}->{$prefix};
      
      # Base configuration for  these pool accounts from accounts component
      my $poolStart = $user_config->{prefix}->{poolStart};
      unless ( defined($poolStart) ) {
        $poolStart = 0;
      }
      my $poolSize = $user_config->{prefix}->{poolSize};
      unless ( defined($poolSize) ) {
        $poolSize = 0;
      }
      my $poolEnd = $poolStart + $poolSize - 1;
      my $poolDigits = $user_config->{prefix}->{poolDigits};
      unless ( defined($poolDigits) ) {
        $poolDigits = length("$poolEnd");
      }

      # Set up sprintf format specifier
      my $field = "%0" . $poolDigits . "d";

      foreach my $i ($poolStart .. $poolEnd) {
        my $fname=sprintf($prefix.$field, $i);
        $desired{"$gridmapdir/$fname"} = 1;
      }
    }

    $self->debug(1,"Total number of desired entries: ".scalar(keys($desired))." (some may already exist)");

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
      $self->info("Deleting no longer needed entries (".scalar(keys($existing)).")...");
      foreach (keys %existing) {
        unlink $_;
      }
    }

    # Now touch the files in the 'desired' hash to make sure everything
    # exists.
    if ( %desired ) { 
      $self->info("Adding new entries (".scalar(keys($desired)).")...");
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
