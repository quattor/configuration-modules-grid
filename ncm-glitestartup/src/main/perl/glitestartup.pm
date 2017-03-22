# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

package NCM::Component::glitestartup;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Template;
@ISA= qw(NCM::Component NCM::Template);

use LC::Check;
use CAF::FileEditor;
use CAF::FileReader;
use CAF::FileWriter;
use CAF::Process;

use Encode qw(encode_utf8);

# Define paths for convenience. 
my $base = "/software/components/glitestartup";
my $glite_config_base = "/system/glite/config";
my $globus_config_base = "/software/components/globuscfg"; 

my $true = "true";
my $false = "false";

# Default directories for gLite services startup driver (normally defined in configuration)
my $glite_startup_service = 'gLite';
my $glite_startup_driver = '/etc/init.d/'.$glite_startup_service;
my $glite_startup_driver_template = 'gLite.template';
my $glite_startup_scripts_paths = [ '/opt/glite/etc/init.d' ];

# Directories and files related to GSI
my $glite_cert_name = 'hostcert.pem';
my $glite_key_name = 'hostkey.pem';
my $grid_security_dir = '/etc/grid-security';
my $proxy_validity = '24:00';


##########################################################################
sub Configure {
##########################################################################
  my ($self,$config)=@_;
  
  # Startup driver configuration file must contain only a list of script to execute.
  # Comments are not supported.
  my $startup_config = '';
  
  # Retrieve component configuration
  my $confighash = $config->getElement($base)->getTree();
  my $glite_config = $config->getElement($glite_config_base)->getTree();
  my $globus_config = $config->getElement($globus_config_base)->getTree();
  my $grid_proxy_init = $globus_config->{GLOBUS_LOCATION} . "/bin/grid-proxy-init";

  # Other initializations
  my $template_dir = "/usr/lib/ncm/config/glitestartup";
  my $changes = 0;

  # Retrieve glitestartup environment
  if ( defined($confighash->{initScript}) ) {
    $glite_startup_driver = $confighash->{initScript};
  }
  if ( defined($confighash->{scriptPaths}) ) {
    $glite_startup_scripts_paths = $confighash->{scriptPaths};
  }
  
  # Loop over all services to start
  for my $service_name (sort(keys(%{$confighash->{'services'}}))) {
    my $service = $confighash->{'services'}->{$service_name};
    # Find where the startup script is located
    my $script;
    for my $path (@{$glite_startup_scripts_paths}) {
      $self->debug(1,"Looking for $service_name startup script in $path...");
      if ( -f "$path/$service_name" ) {
        $self->debug(1,"Startup script for service $service_name found in $path");
        $script = "$path/$service_name";
        last;
      }
    }
    unless ( defined($script) ) {
      $self->warn("Startup script not found for gLite service $service_name");
      next;
    }
    
    # Check that startup script is executable
    unless ( -x $script ) {
      $self->warn("Startup script for gLite service $service_name is not executable");
      next;      
    }

    
    my $service_args = '';
    if ( defined($service->{'args'}) ) {
      $service_args = $service->{'args'};
    }
    $startup_config .= "$script $service_args\n";
  }

  
  # Create/update gLite startup driver (not provided by any RPM)

  $glite_startup_driver_template = $template_dir . "/" . $glite_startup_driver_template; 
  my $driver_changes = $self->Substitute($config,
                                         $glite_startup_driver,
                                         'glitestartup',
                                         $glite_startup_driver_template);
  unless ( defined($driver_changes) ) {
    $self->error("Error creating/updating gLite startup driver ($glite_startup_driver)");
    return(2);
  }
  
  # Ensure startup driver is executable
  my $fh = CAF::FileEditor->new($glite_startup_driver,
                                log => $self,
                                mode => 0755,
                                owner => 'root',
                                group => 'root',
                               );
  my $perm_changes = $fh->close();
  unless (defined($perm_changes)) {
    $self->error("Error setting owner/permissions on $glite_startup_driver");
    return 1;
  }
  
  $changes += $driver_changes + $perm_changes;
  
  # Configure startup file for gLite
  my $proc = CAF::Process->new(["/sbin/chkconfig", "$glite_startup_service"], log => $self);
  $proc->run();
  if ( $? ) {
    $self->info("Enabling gLite services startup...");
    $proc = CAF::Process->new(["/sbin/chkconfig", "--add", "$glite_startup_service"], log => $self);
    $proc->run();
    if ( $? ) {
      $self->warn("Error enabling gLite services startup");
    }
  }
 
  # Create a grid proxy for GLITE_USER

  if ( $confighash->{createProxy} ) {
    my $config_error = 0;
    unless ( defined($glite_config->{GLITE_USER}) ) {
      $self->error("GLITE_USER undefined : cannot configure proxy and start services");
      $config_error = 1;
    }
    unless ( defined($glite_config->{GLITE_GROUP}) ) {
      $self->error("GLITE_GROUP undefined : cannot configure proxy and start services");
      $config_error = 1;
    }
    unless ( defined($glite_config->{GLITE_X509_PROXY}) ) {
      $self->error("GLITE_X509_PROXY undefined : cannot configure proxy and start services");
      $config_error = 1;
    }
    if ( $config_error ) {
      return(4);
    }

    my ($username,$passwd,$uid,$gid,$quota,$comment,$gcos,$glite_homedir,$shell,$expire) = getpwnam($glite_config->{GLITE_USER});
    if ( !defined($glite_homedir) || (length($glite_homedir)==0) ) {
      $self->error("Error retrieving ".$glite_config->{GLITE_USER}." home directory");
      return(4);
    }
    my $glite_cert_dir = $glite_homedir . '/.certs';
    $self->debug(1,"Checking certificate in $glite_cert_dir...");
    my $glite_x509_proxy = $glite_config->{GLITE_X509_PROXY};
    my $cert_status;
    $cert_status = LC::Check::directory($glite_cert_dir);
    if ( $cert_status < 0 ) {
      $self->error("Error creating $glite_cert_dir");
      return(4);
    }
    $cert_status = LC::Check::status($glite_cert_dir,
                                     mode => 0500,
                                     owner => $glite_config->{GLITE_USER},
                                     group => $glite_config->{GLITE_GROUP},
                                    );
    if ( $cert_status < 0 ) {
      $self->error("Error setting owner/group and permissions on $glite_cert_dir");
      return(4);
    }
    
    for my $certfile ($glite_cert_name,$glite_key_name) {
      my $certfile_src = $grid_security_dir . '/' . $certfile;
      my $certfile_glite = $glite_cert_dir . '/' . $certfile;
      my $cert_src_fh = CAF::FileReader->new($certfile_src, log => $self);
      unless ( $cert_src_fh ) {
        $self->error("Error reading $certfile_src: cannot define gLite service certificate");
        next;
      };
      my $cert_fh = CAF::FileWriter->new($certfile_glite,
                                         log => $self,
                                         mode => 0400,
                                         owner => $glite_config->{GLITE_USER},
                                         group => $glite_config->{GLITE_GROUP},
                                        );
      print $cert_fh "$cert_src_fh";
      $cert_src_fh->close();
      $cert_status = $cert_fh->close();
      if ( $cert_status < 0 ) {
        $self->error("Error updating  $certfile_glite from $certfile_src");
        return(4);
      }      
    }
    
    $self->info("Initializing proxy for user ".$glite_config->{GLITE_USER}." ($glite_x509_proxy)");
    my @proxy_init_cmd = ('/bin/su',
                          '-',
                          $glite_config->{GLITE_USER},
                         '-c',
                         "$grid_proxy_init -cert $glite_cert_dir/$glite_cert_name -key $glite_cert_dir/$glite_key_name -valid $proxy_validity -out $glite_x509_proxy"
                         );
    $proc = CAF::Process->new(\@proxy_init_cmd, log => $self);
    $proc->run();
    if ( $? ) {
        $self->error("Error creating grid proxy for user ".$glite_config->{GLITE_USER}." ($glite_x509_proxy)");
        return(4);
    }
  }
  
  # Update startup driver configuration file and restart services if needed.
  # Services are restarted if one of the following conditions is true :
  #   - restartServices is true
  #   - restartServices is undefined and some changes were applied to the driver configuration file
  
  $fh = CAF::FileWriter->new($confighash->{'configFile'},
                             log => $self,
                             backup   => ".old",
                            );
  print $fh encode_utf8($startup_config);
  my $config_changes = $fh->close();
  if ( $config_changes < 0 ) {
    $self->error("Error updating startup driver configuration file (".$confighash->{'configFile'}.")");
    return(3);
  }
  $changes += $config_changes;
  if ( $confighash->{'restartServices'} ||
       (($changes > 0) && !defined($confighash->{'restartServices'})) ) {
    $self->info("Restarting gLite services...");
    $ENV{'GLITE_LOCATION'} = $glite_config->{'GLITE_LOCATION'};
    my $initCmd = '';
    if ( $confighash->{'restartEnv'} ) {
      for my $script (@{$confighash->{'restartEnv'}} ) {
        $initCmd .= '. ' . $script . '; ';        
      }
    }
    $initCmd .= $confighash->{'initScript'} . ' restart';
    if ( $confighash->{'disableOutput'} ) {
      $initCmd .= ' > /dev/null';
    }
    if ( $confighash->{'disableError'} ) {
      $initCmd .= ' 2> /dev/null';
    }
    $self->debug(1,"Executing '$initCmd'...");
    # We need a subshell to honour restartEnv...
    my $output;
    $proc = CAF::Process->new([ $initCmd ], 
                              log => $self,
                              shell => 1,
                              stdout => \$output,
                              stderr => 'stdout',
                             );
    $proc->execute();
    if ( $? == 0 ) {
      $self->verbose(1,$output) if defined($output) && length($output);
    } else {
      $self->error("Error restarting gLite services\n");
      if ( defined($output) && length($output) ) {
        $self->info($output);
      }
      return(3);          
    }
    
    # Execute postRestart commands if any (postRestart is a list of command to execute)
    
    if ( $confighash->{postRestart} ) {
      for my $commandConfig (@{$confighash->{postRestart}}) {
        my $command = $commandConfig->{cmd};
        next if length($command) == 0;
        $self->info("Executing command: '$command'...");
        $proc = CAF::Process->new([ $command ], log => $self);
        my $output = $proc->output();
        if ( defined($commandConfig->{expectedStatus}) && ($? != $commandConfig->{expectedStatus}) ) {
          $self->warning("Error executing command '$command' (status=$?)\n");
          if ( defined($output) && length($output) ) {
            $self->info($output);
          }          
        } else {
          $self->verbose(1,$output) if defined($output) && length($output);
        }
      }  
    }
  }

  return;
}


1; #required for Perl modules

