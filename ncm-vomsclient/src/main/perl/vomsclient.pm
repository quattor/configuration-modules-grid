# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::vomsclient;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC  = LC::Exception::Context->new->will_store_all;
use NCM::Check;
use Encode qw(encode_utf8);

use File::Path;

use EDG::WP4::CCM::Element;

##########################################################################
sub Configure($$@) {
##########################################################################

  my ( $self, $config ) = @_;

  # Define paths for convenience.
  my $base = "/software/components/vomsclient";

  my $lscfile_support = 0;

  if ( $config->elementExists("$base/lscfile") ) {
    if ( $config->getValue("$base/lscfile") eq 'true' ) {
      $lscfile_support = 1;
    }
   }

   if ( ! $lscfile_support ) {
     certificate_configuration($self, $config);
   } else {
     lscfile_configuration($self, $config);
   };

   return 1;
}


#############################
sub lscfile_configuration($$@) {
##############################
 my ($self, $config ) = @_;

 my $base = "/software/components/vomsclient";

  my $vomscertsdir = "/etc/grid-security/vomsdir";
  if ( $config->elementExists("$base/vomsCertsDir") ) {
    $vomscertsdir = $config->getValue("$base/vomsCertsDir");
  }

  # Ensure that this directory exists.
  unless ( -d $vomscertsdir ) {
    mkpath( $vomscertsdir, 0, 0755 );
  }
  unless ( -d $vomscertsdir ) {
    $self->error("can't create directory ($vomscertsdir); aborting...");
  }

  # Get the location for the voms configuration files.  Default to
  # /opt/edg/etc/vomses.
  my $vomsserversdir = "/opt/edg/etc/vomses";
  if ( $config->elementExists("$base/vomsServersDir") ) {
    $vomsserversdir = $config->getValue("$base/vomsServersDir");
  }

  # Ensure that this directory exists.
  unless ( -d $vomsserversdir ) {
    mkpath( $vomsserversdir, 0, 0755 );
  }
  unless ( -d $vomsserversdir ) {
    $self->error("can't create directory ($vomsserversdir); aborting...");
  }

  # Loop over all of the defined VOs and collect information.
  my %fileinfo;
  if ( $config->elementExists("$base/vos") ) {
    my $elt = $config->getElement("$base/vos");
    while ( $elt->hasNextElement() ) {
      my $voname = $elt->getNextElement()->getName();

       my $vodir = $vomscertsdir. "/" . $voname;
       unless ( -d $vodir ) {
         mkpath( $vodir, 0, 0755 );
        }
        unless ( -d $vodir ) {
          $self->error("can't create directory ($vodir); aborting...");
        }

      # $vobase contains a list of servers : each server is described as a nlist.
      # In legacy schema (v1), $vobase contained 1 server only (nlist) instead of a list of servers.
      # TODO : remove support for v1 schema after v2.1.
      my $vobase       = "$base/vos/$voname";
      my $voms_servers = $config->getElement("$vobase");
      my $first        = 1;
      while ( ($voms_servers->isType($voms_servers->LIST) && $voms_servers->hasNextElement()) ||
              ($voms_servers->isType( $voms_servers->NLIST ) && $first) ) {
        my %server;
        if ( $voms_servers->isType( $voms_servers->LIST ) ) {
          %server = $voms_servers->getNextElement()->getHash();
        } else {
          %server = $voms_servers->getHash();
        }

        # In old schema, $voname is a VO alias (short form) and $name is the actual VO name.
        # In new schema, $voname is considered the actual name, except if $name is present.
        my $name = $voname;
        if ( exists($server{'name'}) ) {
          $name = $server{'name'}->getValue();
        }
        my $host    = $server{'host'}->getValue();
        my $port    = $server{'port'}->getValue();
        my $cert    = $server{'cert'}->getValue();
        $self->debug(1,"Processing VO ".$name." server ".$host);
        my $dn = $self->getCertSubject($cert);
        unless ($dn) {
          $self->error("Failed to retrieve certificate subject for $name/$host");
          next;
        }
        my $issuer = $self->getIssuer($cert);
        unless ($dn) {
          $self->error("Failed to retrieve certificate subject for $name/$host");
          next;
        }
        $self->debug(1," Host $host / port $port / cert / dn $dn / issuer $issuer");
        my $fname;
        my $contents;
        $fname = "$vodir/$host.lsc";
        $fileinfo{$fname} = $dn . "\n" . $issuer;

        $contents =
            '"' . $name . '" ' . '"' . $host . '" ' . '"' . $port . '" ' . '"'
          . $dn . '" ' . '"'
          . $name . '" ' . "\n";
        $fname = "$vomsserversdir/$name-$host.vo.ncm-vomsclient";
        $fileinfo{$fname} = $contents;

        # For backward compatibility handling
        $first = 0;
      }
    }
   }

   # Collect the current entries.
  my %oldfiles;
  opendir DIR, $vomscertsdir;
  my @files = grep /\.ncm-vomsclient$/, map "$vomscertsdir/$_", readdir DIR;
  foreach (@files) {
    $oldfiles{$_} = 1;
  }
  closedir DIR;

  opendir DIR, $vomsserversdir;
  @files = grep /\.ncm-vomsclient$/, map "$vomsserversdir/$_", readdir DIR;
  foreach (@files) {
    $oldfiles{$_} = 1;
  }
  closedir DIR;

  # Actually delete them.  Always do this.  The configuration must
  # correspond exactly to that given in the pan configuration.
  foreach ( sort keys %oldfiles ) {
    unlink $_;
    $self->log("error ($?) deleting file $_") if $?;
  }

  # Write the new configuration files.
  foreach ( sort keys %fileinfo ) {
    open CONFIG, ">$_";
    print CONFIG encode_utf8($fileinfo{$_});
    close CONFIG;
    if ($?) {
      $self->error("error creating $_");
    }
  }

 return 1;
}


sub certificate_configuration($$@) {
  my ( $self, $config ) = @_;


  # Define paths for convenience.
  my $base = "/software/components/vomsclient";



  # Get the location for the voms certificates.  Default to
  # /etc/grid-security/vomsdir.
  my $vomscertsdir = "/etc/grid-security/vomsdir";
  if ( $config->elementExists("$base/vomsCertsDir") ) {
    $vomscertsdir = $config->getValue("$base/vomsCertsDir");
  }

  # Ensure that this directory exists.
  unless ( -d $vomscertsdir ) {
    mkpath( $vomscertsdir, 0, 0755 );
  }
  unless ( -d $vomscertsdir ) {
    $self->error("can't create directory ($vomscertsdir); aborting...");
  }

  # Get the location for the voms configuration files.  Default to
  # /opt/edg/etc/vomses.
  my $vomsserversdir = "/opt/edg/etc/vomses";
  if ( $config->elementExists("$base/vomsServersDir") ) {
    $vomsserversdir = $config->getValue("$base/vomsServersDir");
  }

  # Ensure that this directory exists.
  unless ( -d $vomsserversdir ) {
    mkpath( $vomsserversdir, 0, 0755 );
  }
  unless ( -d $vomsserversdir ) {
    $self->error("can't create directory ($vomsserversdir); aborting...");
  }

  # Loop over all of the defined VOs and collect information.
  my %fileinfo;
  if ( $config->elementExists("$base/vos") ) {
    my $elt = $config->getElement("$base/vos");
    while ( $elt->hasNextElement() ) {
      my $voname = $elt->getNextElement()->getName();

      # $vobase contains a list of servers : each server is described as a nlist.
      # In legacy schema (v1), $vobase contained 1 server only (nlist) instead of a list of servers.
      # TODO : remove support for v1 schema after v2.1.
      my $vobase       = "$base/vos/$voname";
      my $voms_servers = $config->getElement("$vobase");
      my $first        = 1;
      while ( ($voms_servers->isType($voms_servers->LIST) && $voms_servers->hasNextElement()) ||
              ($voms_servers->isType( $voms_servers->NLIST ) && $first) ) {
        my %server;
        if ( $voms_servers->isType( $voms_servers->LIST ) ) {
          %server = $voms_servers->getNextElement()->getHash();
        } else {
          %server = $voms_servers->getHash();
        }
        
        # In old schema, $voname is a VO alias (short form) and $name is the actual VO name.
        # In new schema, $voname is considered the actual name, except if $name is present.
        my $name = $voname;
        if ( exists($server{'name'}) ) {
          $name = $server{'name'}->getValue();
        }
        my $host    = $server{'host'}->getValue();
        my $port    = $server{'port'}->getValue();
        my $cert    = $server{'cert'}->getValue();
        $self->debug(1,"Processing VO ".$name." server ".$host);

        my $fname;
        my $contents;
        my $subject = $self->getCertSubject($cert);
        unless ($subject) {
          $self->error("Failed to retrieve certificate subject for $name/$host");
          next;
        }     
        $fname = "$vomscertsdir/$host.cert.ncm-vomsclient";
        $fileinfo{$fname} = $cert . "\n";
        
        $contents =
            '"' . $name . '" ' . '"' . $host . '" ' . '"' . $port . '" ' . '"'
          . $subject . '" ' . '"'
          . $name . '" ' . "\n";
        $fname = "$vomsserversdir/$name-$host.vo.ncm-vomsclient";
        $fileinfo{$fname} = $contents;

        if ( exists($server{'oldcert'}) ) {
          my $oldcert = $server{'oldcert'}->getValue();
          $self->debug(1,"Old certificate found for $name/$host");
          my $oldSubject = $self->getCertSubject($oldcert);
          unless ($oldSubject) {
            $self->error("Failed to retrieve old certificate subject for $name/$host");
          }
          $fname = "$vomscertsdir/$host.oldcert.ncm-vomsclient";
          $fileinfo{$fname} = $oldcert . "\n";
          
          if ( $oldSubject ne $subject ) {
            $contents =
                '"' . $name . '" ' . '"' . $host . '" ' . '"' . $port . '" ' . '"'
              . $oldSubject . '" ' . '"'
              . $name . '" ' . "\n";
            $fname = "$vomsserversdir/$name-$host.vo.oldsubject.ncm-vomsclient";
            $fileinfo{$fname} = $contents;
          }
        }

        # For backward compatibility handling
        $first = 0;
      }
    }
  }

  # Collect the current entries.
  my %oldfiles;
  opendir DIR, $vomscertsdir;
  my @files = grep /\.ncm-vomsclient$/, map "$vomscertsdir/$_", readdir DIR;
  foreach (@files) {
    $oldfiles{$_} = 1;
  }
  closedir DIR;

  opendir DIR, $vomsserversdir;
  @files = grep /\.ncm-vomsclient$/, map "$vomsserversdir/$_", readdir DIR;
  foreach (@files) {
    $oldfiles{$_} = 1;
  }
  closedir DIR;

  # Actually delete them.  Always do this.  The configuration must
  # correspond exactly to that given in the pan configuration.
  foreach ( sort keys %oldfiles ) {
    unlink $_;
    $self->log("error ($?) deleting file $_") if $?;
  }

  # Write the new configuration files.
  foreach ( sort keys %fileinfo ) {
    open CONFIG, ">$_";
    print CONFIG encode_utf8($fileinfo{$_});
    close CONFIG;
    if ($?) {
      $self->error("error creating $_");
    }
  }

  return 1;
}


# Method retrieving certificate subject from X509 certificate and returning it
# in a format suitable for VOMS.

sub getCertSubject () {
  my $self = shift;
  my $cert = shift;
  unless ( $cert ) {
    $self->error('Invalid certificate');
    return;
  }
  
  # Extract the subject name using OpenSSL to help avoid
  # typos.
  my $subject = `echo "$cert" | openssl x509 -noout -subject`;
  if ($?) {
    $self->error("cannot extract subject name for certificate");
    return(undef);
  }

  # Remove the subject label at the beginning of the line.
  if ( $subject =~ m/\w+=\s*(.*)$/ ) {
    $subject = $1;
  } else {
    $self->error("Invalid subject name in certificate");
    return(undef);
  }

  # Fix up the email address part (emailAddress -> Email).
  $subject =~ s/emailAddress/Email/g;
  
  return($subject);
}


sub getIssuer () {
 my $self = shift;
 my $cert = shift;
 unless ( $cert ) {
  $self->error('Invalid certificate');
  return;
 }

 my $issuer = `echo "$cert" | openssl x509 -noout -issuer`;
 if ($?) {
  $self->error('cannot extract issuer name from certificate');
  return(undef);
 }


 if ( $issuer =~m/\w+=\s*(.*)$/ ) {
    $issuer = $1;
  } else {
    $self->error("Invalid issuer name in certificate");
    return(undef);
  }


 return($issuer);
}


1;    # Required for PERL modules

