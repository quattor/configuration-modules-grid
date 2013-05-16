# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
# Coding style: emulate <TAB> characters with 4 spaces, thanks!
################################################################################


package NCM::Component::globuscfg;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element;

use File::Copy;
use LC::Check;

##########################################################################
sub Configure($$@) {
##########################################################################

	my ($self, $config) = @_;
	
	# This location should not be changed!  All of the Globus configuration
	# relies on having this file in this place.
	my $sysconfglobus = "/etc/sysconfig/globus";
	
	# The init.d area to be used.
	my $sbinserv = "/sbin/service";

  # Get gLite installation path
  my $glite_location = '/opt/glite';
  if ( $config->elementExists('/system/glite/config/GLITE_LOCATION') ) {
    $glite_location = $config->getElement('/system/glite/config/GLITE_LOCATION')->getValue();
  }
  
  # Load globuscfg config into a hash
  my $globus_config = $config->getElement('/software/components/globuscfg/')->getTree();
  
  # For convenience
  my $mds = $globus_config->{mds};
  my $gris = $mds->{gris}; 
  my $giis = $mds->{giis}; 
  my $gridftp = $globus_config->{gridftp}; 
  my $gatekeeper = $globus_config->{gatekeeper}; 
  my $paths = $globus_config->{paths}; 
  my $services = $globus_config->{services}; 
  
  
	# Check the necessary values (location and configuration file name).
	unless ( $globus_config->{'GLOBUS_LOCATION'} ) { 
		$self->error( "Couldn't determine Globus location" ) ; 
		return;
	}

  unless ( $globus_config->{'GPT_LOCATION'} ) {
    $self->error( "Couldn't determine GPT location" ) ;
    return;
  }
  
  unless ( $globus_config->{'GLOBUS_CONFIG'} ) { 
		$self->error( "Couldn't determine Globus configuration file" );
		return;
	}	

	unless ( $globus_config->{'globus_flavor_name'} ) {
		$self->error( "Couldn't determine Globus flavor" ) ; 
		return;
	}
	
  my $globus_config_flavor;
  my $globus_init_script = "$globus_config->{'GLOBUS_LOCATION'}/sbin/globus-initialization.sh";
  if ( -f $globus_init_script ) {
    $self->info("Using EDG flavor of Globus configuration");
    $globus_config_flavor = 'edg';
  } else {
    $self->info("Using gLite flavor of Globus configuration");
    $globus_config_flavor = 'glite';
  }


	# Generating the sysconfig file
	# Skipped if sysconfigUpdate = false

  my $contents = "";
  if ( ! $globus_config->{'sysconfigUpdate'} ) {
    $self->info("$sysconfglobus update disabled");

  } else {
    $contents .= "GLOBUS_LOCATION=$globus_config->{'GLOBUS_LOCATION'}\n";
    $contents .= "GLOBUS_CONFIG=$globus_config->{'GLOBUS_CONFIG'}\n";
    $contents .= "GLOBUS_TCP_PORT_RANGE=$globus_config->{'GLOBUS_TCP_PORT_RANGE'}\n"
                                                  if $globus_config->{'GLOBUS_TCP_PORT_RANGE'};
    $contents .= "GLOBUS_UDP_PORT_RANGE=$globus_config->{'GLOBUS_UDP_PORT_RANGE'}\n"
                                                  if $globus_config->{'GLOBUS_UDP_PORT_RANGE'};

    # This is really a hack to get perl working correctly.  System
    # configuration files should really NOT be source-able.
    $contents .= "export LANG=C\n";

    my $result = LC::Check::file($sysconfglobus,
                                 backup => ".old",
                                 contents => $contents
                                );
    unless ( $result >= 0 ) {
      $self->error("Error updating system configuration file $sysconfglobus");
    }
  }


  # Components execute (at boot time) with the system default path and
  # not the one built up from the profile.d scripts.  Consequently,
  # the locations of the batch system binaries may need to be added to
  # the path.

  if ( $paths ) {
    my @newpaths;
    for my $path (@{$paths}) {
      push ( @newpaths, $path );      
    }

    # Split the current path.
    my @pathelements = split(':',$ENV{PATH});
    
    # Get "paths" if it exists and add paths to array.
    foreach (@newpaths) {
      push @pathelements, $_;
    }

    # Make new path and setup the environment. 
    my $newpath = join(':',@pathelements);
    $ENV{PATH} = $newpath;
  }

  $ENV{'GLOBUS_LOCATION'} = $globus_config->{'GLOBUS_LOCATION'};    # Required by Globus scripts
  $ENV{'GPT_LOCATION'} = $globus_config->{'GPT_LOCATION'};          # Required by Globus scripts
  

	# Configure Globus with standard Globus script if gLite flavor of Globus configuration
  # gLite flavor is used mainly to configure Globus gatekeeper. This includes LCAS/LCMAPS
  # integration and job managers configuration.
  # Remark : many Globus initialization script require current directory to be $GLOBUS_LOCATION/setup/globus
  
  if ( $globus_config_flavor eq "glite" ) {
    my $output = '';
    my $globus_version;
    my $globus_version_bin = $globus_config->{'GLOBUS_LOCATION'}.'/bin/globus-version';
    if ( -x $globus_version_bin ) {
      $globus_version = qx/$globus_version_bin/;
    } else {
      $globus_version = '4.0';
      $self->warn("Unable to determine Globus version: check your configuration, assuming $globus_version.");
    };
    
    # Globus base environment
    my $globus_config_script = "(cd $globus_config->{'GLOBUS_LOCATION'}/setup/globus; ./setup-tmpdirs)";
    $self->info("Initializing Globus configuration tools ($globus_config_script)...");
    $output = qx%$globus_config_script 2>&1%;
    unless ( $? ) {
      $globus_config_script = "(cd $globus_config->{'GLOBUS_LOCATION'}/setup/globus; ./setup-globus-common)";
      $self->info("Initializing Globus environment ($globus_config_script)...");
      $output .= "\n" . qx%$globus_config_script 2>&1%;      
    }
    $self->verbose("$output");
    if ( $? ) {
      $self->error("Failed to initialize Globus base environment. Return value: ". $? .
                   ". Script output:");
      $self->info("$output");
      return 1;
    }

    # LCAS/LCMAPS integration    
    if ( $gatekeeper || $gridftp ) {
      my $lcas_integration_script = $glite_location . "/sbin/gt4-interface-install.sh";
      if ( -x $lcas_integration_script ) {
        $self->info("Configuring Globus/LCAS-LCMAPS integration ($lcas_integration_script)...");
        $output = qx%$lcas_integration_script install 2>&1%;
        $self->verbose("$output") if $output;
        if ( $? ) {
          $self->error("Failed to configure LCAS/LCMAPS integration with Globus. Return value: ". $? .
                         ". Script output:");
          $self->info("$output") if $output;     # There should be some output in case of failure...
          return 1;
        }
      } else {  
        $self->error("LCAS/LCMAPS integration script ($lcas_integration_script) not found or not exectuable");
      }
    }
    
    # Create gridftp configuration file
    if ( $gridftp ) {
      my $gridftp_conf_file = $globus_config->{GLOBUS_LOCATION} . '/etc/gridftp.conf';
      my $contents;
      if ( $globus_config->{gridftp}->{log} ) {
        my $logfile_opt;
        if ( $globus_version >= '4.0' ) {
          $logfile_opt = 'log_single';
        } else {
          $logfile_opt = 'logfile';
        }
        $contents = $logfile_opt. ' ' . $globus_config->{gridftp}->{log} ."\n";
      }
      if ( $globus_config->{gridftp}->{maxConnections} ) {
        if ( $globus_version >= '4.0' ) {
          $contents .= "connections_max " . $globus_config->{gridftp}->{maxConnections}
        } else {
          $self->warn('Globus < 4.0: maximum number of gridftp connections cannot be configured.');
        }
      }
      if ( length($contents) > 0 ) {
        $self->info("Checking Globus gridftp configuration ($gridftp_conf_file)...");
        my $result = LC::Check::file($gridftp_conf_file,
                                     backup => ".old",
                                     contents => $contents
                                    );
        unless ( $result >= 0 ) {
          $self->error("Error updating gridftp configuration file ($gridftp_conf_file)");
        }      
      }
    }
      
    # Gatekeeper
    if ( $gatekeeper ) {
      # Create globus-gatekeeper.conf (standard script to do it doesn't allow to redefine log directory).
      # Copied from YAIM.
      my $gatekeeper_conf_file = $globus_config->{GLOBUS_LOCATION} . '/etc/globus-gatekeeper.conf';
      $self->info("Checking Globus gatekeeper configuration ($gatekeeper_conf_file)...");
      $contents = "-x509_cert_dir $globus_config->{x509_cert_dir}\n" .
                  "-x509_user_cert $globus_config->{x509_user_cert}\n" .
                  "-x509_user_key $globus_config->{x509_user_key}\n" .
                  "-gridmap $globus_config->{gridmap}\n" .
                  "-home $globus_config->{GLOBUS_LOCATION}\n" .
                  "-e libexec\n" .
                  "-port 2119\n" .
                  "-grid_services $globus_config->{GLOBUS_LOCATION}/etc/grid-services\n" .
                  "-logfile /var/log/globus-gatekeeper.log\n";
      my $result = LC::Check::file($gatekeeper_conf_file,
                                   backup => ".old",
                                   contents => $contents
                                  );
      unless ( $result >= 0 ) {
        $self->error("Error updating gatekeeper configuration file ($gatekeeper_conf_file)");
      }
      
      # Configure job managers
      if ( $gatekeeper->{'jobmanagers'} ) { 
        my $gk_config_script = "(cd $globus_config->{'GLOBUS_LOCATION'}/setup/globus; ./setup-globus-gram-job-manager)";
        $self->info("Configuring GRAM job manager ($gk_config_script)...");
        $output = qx%$gk_config_script 2>&1%;
        $self->verbose("$output");
        if ( $? ) {
          $self->error("Failed to configure Globus gatekeeper job manager. Return value: ". $? .
                       ". Script output:");
          $self->info("$output");
          return 1;
        }
        
        foreach my $jobman (@{$gatekeeper->{'jobmanagers'}} ) {
          my $type;
          if ( $jobman->{'type'} ) {
            $type = $jobman->{'type'}; 
          } else {
            $type = $jobman->{'recordname'}; 
          }

          my $gk_config_script = "(cd $globus_config->{'GLOBUS_LOCATION'}/setup/globus; ./setup-globus-job-manager-$type)";
          $self->info("Configuring job manager $type ($gk_config_script)...");
          $output = qx%$gk_config_script 2>&1%;
          $self->verbose("$output");
          if ( $? ) {
            $self->error("Failed to configure Globus gatekeeper job manager $type. Return value: ". $? .
                         ". Script output:");
            $self->info("$output");
            return 1;
          }
        
        }

      } else {
        $self->warn("No job managers defined in configuration");
      }      
    }


  # Generating Globus config file if EDG flavor of Globus configuration.
  # EDG flavor relies on EDG specific scripts distributed as part of edg-xxx RPMS.
  
  } else {
  	$contents = "";
  	
  	# [common]
  	$contents .= "[common]\n";
  	$contents .= "GLOBUS_LOCATION=$globus_config->{'GLOBUS_LOCATION'}\n";
  	$contents .= "globus_flavor_name=$globus_config->{'globus_flavor_name'}\n";
  	$contents .= "x509_user_cert=$globus_config->{'x509_user_cert'}\n" 
  													if $globus_config->{'x509_user_cert'};
  	$contents .= "x509_user_key=$globus_config->{'x509_user_key'}\n" if $globus_config->{'x509_user_key'};
  	$contents .= "gridmap=$globus_config->{'gridmap'}\n" if $globus_config->{'gridmap'};
  	$contents .= "gridmapdir=$globus_config->{'gridmapdir'}\n" if $globus_config->{'gridmapdir'};
  	$contents .= "\n";
  
  	# [mds]
  	if ( $mds ) {
      $contents .= "[mds]\n";
      $contents .= "globus_flavor_name=$mds->{'globus_flavor_name'}\n"  if $mds->{'globus_flavor_name'};
      $contents .= "user=$mds->{'user'}\n" if $mds->{'user'};
      $contents .= "\n";
      $contents .= "x509_user_cert=$mds->{'x509_user_cert'}\n" if $mds->{'x509_user_cert'};
      $contents .= "x509_user_key=$mds->{'x509_user_key'}\n" if $mds->{'x509_user_key'};
      $contents .= "";
      
      # [mds/gris]
      if ( $gris) {
        $contents .= "[mds/gris]\n";
        $contents .= "suffix=$gris->{'suffix'}\n" if $gris->{'suffix'};
        $contents .= "\n";
        
        # [mds/gris/provider/*]
        my $prov;
        foreach $prov ( keys %{$gris->{'provider'}} ) {
          $contents .= "[mds/gris/provider/$prov]\n"; 
          $contents .= "provider=$gris->{'provider'}->{$prov}\n" if $gris->{'provider'}->{$prov};
          $contents .= "\n";
        }
      
        # [mds/gris/registration/*]
        foreach my $regno ( keys %{$gris->{'registration'}} ) {
          $contents .= "[mds/gris/registration/". $gris->{'registration'}->{$regno}->{'recordname'} . "]\n";  
          $contents .= "regname=$gris->{'registration'}->{$regno}->{'regname'}\n" 
                if $gris->{'registration'}->{$regno}->{'regname'};
          $contents .= "reghn=$gris->{'registration'}->{$regno}->{'reghn'}\n" 
                if $gris->{'registration'}->{$regno}->{'reghn'};
          $contents .= "regport=$gris->{'registration'}->{$regno}->{'regport'}\n" 
                if $gris->{'registration'}->{$regno}->{'regport'};
          $contents .= "regperiod=$gris->{'registration'}->{$regno}->{'regperiod'}\n" 
                if $gris->{'registration'}->{$regno}->{'regperiod'};
          $contents .= "ttl=$gris->{'registration'}->{$regno}->{'ttl'}\n" 
                if $gris->{'registration'}->{$regno}->{'ttl'};
          $contents .= "\n";
        }
      }
    
  	}
  
  	# Structure for that was not literally taken from template
  	# [mds/giis/*]
  	foreach my $allowno ( keys %{$giis->{allowedregs}} ) {
  		$contents .= "[mds/giis/" . $giis->{allowedregs}->{$allowno}->{'recordname'} . "]\n";	
  		if ( $giis->{allowedregs}->{$allowno}->{'name'} ) {
  			$contents .= "name=$giis->{allowedregs}->{$allowno}->{'name'}\n";
  		} else {
  			$contents .= "name=$giis->{allowedregs}->{$allowno}->{'recordname'}\n";
  		}	
  		if ( @{ $giis->{allowedregs}->{$allowno}->{'allowreg'} } ) {
  			my $perm;
  			foreach ( @{ $giis->{allowedregs}->{$allowno}->{'allowreg'} } ) {
  				$contents .= "allowreg=\"$_\"\n";
  			}
  		}
  		$contents .= "\n";
  	}
  	
  	# Structure for that was not literally taken from template
  	# [mds/giis/*]
  	foreach my $reg ( keys %{$giis->{registration}} ) {
  		if ( $giis->{registration}->{$reg}->{'regname'} && $giis->{registration}->{$reg}->{'reghn'} ) {
  			$contents .= "[mds/giis/$reg/registration/" . $giis->{registration}->{$reg}->{'regname'} . "]\n";	
  			if ( $giis->{registration}->{$reg}->{'name'} ) {
  				$contents .= "name=$giis->{registration}->{$reg}->{'name'}\n";
  			} else {
  				$contents .= "name=$reg\n";
  			}	
  			$contents .= "regname=$giis->{registration}->{$reg}->{'regname'}\n" ;
  			$contents .= "reghn=$giis->{registration}->{$reg}->{'reghn'}\n";
  			$contents .= "regport=$giis->{registration}->{$reg}->{'regport'}\n" 
  													if $giis->{registration}->{$reg}->{'regport'};
  			$contents .= "regperiod=$giis->{registration}->{$reg}->{'regperiod'}\n" 
  													if $giis->{registration}->{$reg}->{'regperiod'};
  			$contents .= "ttl=$giis->{registration}->{$reg}->{'ttl'}\n" if $giis->{registration}->{$reg}->{'ttl'};
  			$contents .= "\n";
  		}
  	}
  
  	# [gridftp]
  	if ( $gridftp ) {
    	$contents .= "[gridftp]\n";
    	$contents .= "globus_flavor_name=$gridftp->{'globus_flavor_name'}\n" if $gridftp->{'globus_flavor_name'};
    	$contents .= "X509_USER_CERT=$gridftp->{'X509_USER_CERT'}\n" if $gridftp->{'X509_USER_CERT'};
    	$contents .= "X509_USER_KEY=$gridftp->{'X509_USER_KEY'}\n" if $gridftp->{'X509_USER_KEY'};
    	$contents .= "ftpd=$gridftp->{'ftpd'}\n" if $gridftp->{'ftpd'};
    	$contents .= "port=$gridftp->{'port'}\n" if $gridftp->{'port'};
    	$contents .= "umask=$gridftp->{'umask'}\n" if $gridftp->{'umask'};
    	$contents .= "log=$gridftp->{'log'}\n" if $gridftp->{'log'};
    	$contents .= "user=$gridftp->{'user'}\n" if $gridftp->{'user'};
    	$contents .= "options=$gridftp->{'options'}\n" if $gridftp->{'options'};
    	$contents .= "\n";
  	}
  	
  	# [gatekeeper]
  	if ( $gatekeeper ) {
    	$contents .= "[gatekeeper]\n";
    	$contents .= "globus_flavor_name=$gatekeeper->{'globus_flavor_name'}\n" 
    													if $gatekeeper->{'globus_flavor_name'};
    	$contents .= "default_jobmanager=". $gatekeeper->{'jobmanagers'}->[0]->{'recordname'} . "\n"		
    	                        if $gatekeeper->{'jobmanagers'}->[0]->{'recordname'};
    	if ( $gatekeeper->{'job_manager_path'} ) {
    		my @job_manager_path = split ( /s+/,  ); 
    		my $jmp;
    		foreach $jmp (@{ $gatekeeper->{'job_manager_path'} } ) {
    			$contents .= "job_manager_path=\$GLOBUS_LOCATION/libexec/$jmp\n";
    		}	
    	} else {
    			$contents .= "job_manager_path=\$GLOBUS_LOCATION/libexec/\n";
    	}	
    	$contents .= "extra_options=$gatekeeper->{'extra_options'}\n" 
    													if $gatekeeper->{'extra_options'};
    	$contents .= "globus_gatekeeper=$gatekeeper->{'globus_gatekeeper'}\n" if $gatekeeper->{'globus_gatekeeper'};
    	$contents .= "user=$gatekeeper->{'user'}\n" if $gatekeeper->{'user'};
    	$contents .= "port=$gatekeeper->{'port'}\n" if $gatekeeper->{'port'};
    	$contents .= "logfile=$gatekeeper->{'logfile'}\n" if $gatekeeper->{'logfile'};
    	$contents .= "\n";
    
    	# [gatekeeper/*]
    	if ( $gatekeeper->{'jobmanagers'} ) {	
    		$contents .= "jobmanagers=\"";
     		foreach my $jobman (@{$gatekeeper->{'jobmanagers'}} ) {
    			$contents .= $jobman->{'recordname'}. " ";
    		}	
    		$contents .= "\"\n\n";
    	}	
      foreach my $jobman (@{$gatekeeper->{'jobmanagers'}} ) {
     		$contents .= "[gatekeeper/" . $jobman->{'recordname'} . "]\n";
     		if ( $jobman->{'type'} ) {
     			$contents .= "type=$jobman->{'type'}\n"; 
     		} else {
     			$contents .= "type=$jobman->{'recordname'}\n"; 
     		}	
     		$contents .= 	
     			"job_manager=$jobman->{'job_manager'}\n" 
     							if $jobman->{'job_manager'};
     		$contents .=
     			"extra_config=$jobman->{'extra_config'}\n" 
     							if $jobman->{'extra_config'};
     		$contents .= "\n";
     	}
  	}
  	
  	# Update Globus config file
  							
  	my $result = LC::Check::file( $globus_config->{'GLOBUS_CONFIG'},
  			backup => ".old",
  			contents => $contents
  		);
  	unless ( $result >= 0 ) {
  		$self->error("Error updating configuration file $globus_config->{'GLOBUS_CONFIG'}");
  	}

    # Actually configure Globus
  
    my $globus_init_script = "$globus_config->{'GLOBUS_LOCATION'}/sbin/globus-initialization.sh";
    $self->info("$globus_init_script found. Executing it...");
    my $output = qx%$globus_init_script 2>&1%;
    $self->verbose("$output");
    if ( $? ) {
      $self->error("Unable to initialize Globus. Return value: ". $? . 
                   ". Script output:");
      $self->info("$output");
      return;
    }

  }


	# Stop the daemons with the old files in place.  We'll stop
	# the wrong daemon if the executable has changed
	# in the configuration (e.g. gatekeeper)


	if ($services ) {
		foreach my $service (@{$services}) {
			# Only stop the daemon if it is already running.  This depends
			# on the status directive returning a reasonable value (i.e.
			# 0 if running).
			if (! system("$sbinserv $service status")) {
				if (system("$sbinserv $service stop")) {
					$self->warn("init.d $service stop failed: ". $?);
				}
			}
		}
		# Start the daemons.
		foreach my $service (@{$services}) {
			if (system("$sbinserv $service start")) {
				$self->error("init.d $service start failed: ". $?);
			}
		}

	}	

	return 1; #OK
}

1 # Required for Perl modules
