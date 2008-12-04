# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
#######################################################################
#
# NCM component for dcache
#
# ** Generated file : do not edit **
#
#######################################################################

package NCM::Component::dcache;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element;

use File::Copy;
use File::Path;
use File::Compare;
## for units etc
use MIME::Base64;
use Digest::MD5 qw(md5_hex);

##########################################################################
sub Configure {
##########################################################################
  our ($self, $config) = @_;
  our (%v,%p,$chim); 
  our $homeDir_default="/opt/d-cache";

  my ($new_base,$name,$real_exec,$serv,$sym,$link,$case_insensitive);
  my @all_names=("pnfs_config","node_config","dc_setup","pools","pnfs_setup","all_pool","links","admin");
  foreach $name (@all_names) {
  	$p{$name}{changed} = 0;
  }	
  my $base = "/software/components/dcache";
  my $fqdn = $config->getValue("/system/network/hostname").".".$config->getValue("/system/network/domainname");
  my $shortname = $config->getValue("/system/network/hostname");
  our $debug_print = "15";
  $debug_print = fetch("$base/config/debug_print",$debug_print);
  $self->info("Debug_print=$debug_print");

  ## STOP ncm-dcache
  if ( -f  "$homeDir_default/DONT_RUN_NCM_DCACHE") {
	  pd("Found $homeDir_default/DONT_RUN_NCM_DCACHE. Remove this file if you want to continue. Exiting...","i","1");
	  return 1;
  }

  ## run some checks to see if bare minimum is available. If not, stop component.
  my @checks = ("$base/config/node_config/node_type","$base/config/dCacheSetup");
  return 1 unless check_ok(@checks);
  
  # see if this is an admin node:
  my $admin = 0;
  my $slony = 0;
  my $pool = 0;
  my $door = 0;	
  
  my $node_type = $config->getValue("$base/config/node_config/node_type");
  if ($node_type eq "admin") {
  	$admin = 1 ;
  } elsif ($node_type eq "pool") {
  	## vaiable not used anywhere
  	$pool = 1;
  } elsif ($node_type eq "door") {
  	## you better know what you are configuring
  	$door = 1;
  } else {
  	pd("Node type $node_type not allowed. Exiting...","e","1");
  	return 1;	
  }	
 
  ## proposed structure
  ## first generate all config in a way that does not depend on running subsystem. 
  ## All start/stop/restart/reload of services can be flagged and dealt with later.

  ## 1. postgresql: only on admin node and slony
  ## now in ncm-postgresql
  my $postgresql_serv;
  pd("No postgresql service name set. Assuming 'postgresql'","i") if (! $config->elementExists("/software/components/dcache/postgresql"));
  $postgresql_serv=fetch("/software/components/dcache/postgresql","postgresql");

  if ($admin) {
  	if (! $config->elementExists("/software/components/postgresql")) {
  		pd("No ncm-postgresql config found. Make sure postgresql is setup properly!!","e");
  	}

  }	
  	
#########################################
#########################################
  ## the base of dcache
  ## normally this is never changed.        
  my $dc_dir = fetch("$base/config/dc_dir",$homeDir_default);
  if (! -d $dc_dir) {
    $self->error("dcache base dir $dc_dir not found. Exiting component...");
    return 1;
  }  

  ## 4. $dc_dir/etc/node_config
  $new_base = "$base/config/node_config";
  $name="node_config";
  $p{$name}{mode}="BASH_SOURCE";
  $p{$name}{filename}="$dc_dir/etc/node_config";
  $p{$name}{case_insensitive}=1;
  $p{$name}{convert_boolean}=1;
  
  slurp($name,$new_base,$dc_dir);
  
  ## since 1.8.0-12, DCACHE_HOME is used instead of DCACHE_BASE_DIR
  if (exists $v{$name}{DCACHE_HOME}) {
    $v{$name}{DCACHE_BASE_DIR}=$v{$name}{DCACHE_HOME};
  };

  if (! exists $v{$name}{SERVER_ID}) {
        $v{$name}{SERVER_ID}=$config->getValue("/system/network/domainname");
  } 
  dump_it($name);


  ## 
  ## dcacheSetup is needed for chimera 
  ##

  ## setup non-admin dconf
  ## use base path fron node_config
  ##
  if (! setup_dconf_no_admin()) {
    pd("Can't setup dConf/no-admin. Exiting.","e");
    return 1;
  };


  ## 5. $dc_dir/config/dCacheSetup
  $new_base = "$base/config/dCacheSetup";
  $name="dc_setup";
  $p{$name}{mode}="BASH_SOURCE";
  $p{$name}{filename}="$dc_dir/config/dCacheSetup";
  $p{$name}{case_insensitive}=0;
  if ($config->elementExists("$base/config/admin_passwd")) {    
    $p{dc_setup}{admin_passwd}=$config->getValue("$base/config/admin_passwd");
  } 
  ## new style
  make_config_dcachesetup($name,$new_base,$dc_dir);


  ## 2. pnfsserver/chimera, also admin mode only
  $chim = 0;
  my $pnfssetup_file_missing=0;
  if ($config->elementExists("$base/chimera")) {
    ## this is chimera
    $chim=1;
    
    ## only support /pnfs
    $v{pnfs_config}{PNFS_ROOT} = "/pnfs";
    
    $serv="chimera-nfs";
    $link="/etc/init.d/$serv";
    if ($admin) {
      ## check for the link
      if (! -f $link) {
        pd("$serv should be configured here. Modify ncm-chkconfig and/or ncm-symlink accordingly! Exiting...","e");
        return 1;
      }
      ## delay the chimera setup till after the dcacheSetup
    } else {
      ## chimera should not be running here
      pd("$serv should not be configured here. Modify ncm-chkconfig accordingly!","e") if (-f $link);
      return 1 if (! abs_stop_service($serv,"Going to stop $serv, this is not an admin node."));
    }
  } else {
    $serv="pnfs";
    $link="/etc/init.d/$serv";
	
    if ($admin) {
      $new_base = "$base/pnfs/pnfs_config";
    
      $p{pnfs_config}{pnfs_install_dir} = fetch("$new_base/pnfs_install_dir","/opt/pnfs");
      if (! -d $p{pnfs_config}{pnfs_install_dir}) {
        $self->error("PNFS_INSTALL_DIR ".$p{pnfs_config}{pnfs_install_dir}." not found. Exiting component...");
        return 1;
      }  

      ## generate $p{pnfs_config}{pnfs_install_dir}/etc/pnfs_config
	  $name="pnfs_config";
	  ## ahum, pnfs_configig is not sourced, but something is done to it (see pnfs-install.sh) 
      $p{$name}{mode}="EQUAL_SPACE";
	  $p{$name}{filename}=$p{pnfs_config}{pnfs_install_dir}."/etc/pnfs_config";
	  $p{$name}{case_insensitive}=1;
	  $p{$name}{convert_boolean}=1;
	
	  slurp($name,$new_base,$p{pnfs_config}{pnfs_install_dir});
	  dump_it($name);
	
	  ## check for existence of the logArea directory
      my $logarea=$v{$name}{PNFS_LOG};
      if (! -d $logarea) {
		pd("PNFS_LOG: Can't find $logarea. Creating it...");
		$real_exec="mkdir -p $logarea";
		if (sys2($real_exec)) {
			pd("PNFS_LOG: Can't run $real_exec: $!");
			return 1;
		}	
      }
	
	  ## check for the link
	  if (! -f $link) {
		pd("$serv should be configured here. Modify ncm-chkconfig and/or ncm-symlink accordingly! Exiting...","e");
		return 1;
	  }	

	  ## pnfs_setup	
	  $new_base= "$base/pnfs/pnfs_setup";
	  $name="pnfs_setup";
	  $p{$name}{mode}="BASH_SOURCE";
	  $p{$name}{filename}="/usr/etc/pnfsSetup";
	  $p{$name}{case_insensitive}=0;
	  if (-f $p{$name}{filename}) {
		slurp($name,$new_base,"/usr/etc");
		dump_it($name);
	  } else {
  		## wow, pnfs-install failed or probably didn't even run
	  	$pnfssetup_file_missing=1;
	  	$p{$name}{changed}=1;
		## pnfs hasn't been installed yet
		pd("/usr/etc/pnfsSetup not found: pnfs isn't installed yet?","w","1") if (! -f "/usr/etc/pnfsSetup");
	  }		
    } else {
	  ## pnfs should not be running here
	  pd("$serv should not be configured here. Modify ncm-chkconfig accordingly!","e") if (-f $link);
  	  return 1 if (! abs_stop_service($serv,"Going to stop $serv, this is not an admin node."));
    }
  }  	
  
#########################################
#########################################


  



  ## check for existence of the logArea directory
  my $logarea=$v{$name}{logArea};
  if (! -d $logarea) {
		pd("logArea: Can't find $logarea. Creating it...");
		$real_exec="mkdir -p $logarea";
		if (sys2($real_exec)) {
			pd("logArea: Can't run $real_exec: $!");
			return 1;
		}	
  }

  ## set door if node is not an explicit door
  my $tmpdoor = 0;
  $tmpdoor = 1 if ($v{node_config}{SRM} eq "yes" || 	$v{node_config}{GRIDFTP} eq "yes" || $v{node_config}{GSIDCAP} eq "yes");
  if ($door) {
		if ( ! $tmpdoor ) {
			pd("You have configured the node as a DOOR, but SRM, GRIDFTP nor GSIDCAP are configured. Please doublecheck your config. Continuing...","w");
		}
  } else {
		$door = $tmpdoor;
  };
  
  ## 3. dcache
  $serv="dcache";
  $link="/etc/init.d/$serv";
  if ($admin || $door) {
	## check for the link
	if (! -f $link) {
		pd("$serv should be configured here. Modify ncm-chkconfig and/or ncm-symlink accordingly! Exiting...","e");
		return 1;
	}	
  } else {
  	pd("$serv should not be configured here. Modify ncm-chkconfig accordingly!","e") if (-f $link);
  	return 1 if (! abs_stop_service($serv,"Going to stop $serv, this is not an admin or door node."));	
  }	

    
#########################################
#########################################
  ## collect all pool info in $v{all_pool}
  ## structure: $v{all_pool}{$pool_host_name}{$pool_name}{$el_p_name}=$el_p_val

  $new_base="$base/pool/pools";
  $name="all_pool";
  $p{$name}{filename}="$dc_dir/etc/ncm-dcache-poolinfo";
  $p{$name}{mode}="ALL_POOL";
  if ($config->elementExists("$new_base")) {
	collect_pool_info($new_base);
  } else {
	## euhm, no pools in whole dcache structure?
	pd("No configured pools were found in the dcache configuration. Exiting...");
	return 1;
  }		
  ## now there's $p{all_pool}{changed} for changed pool_info for the complete dcache pool config
  ## $p{all_pools}{ulimit_n} to set ulimit -n on startup of pools
  $p{all_pools}{ulimit_n}=fetch("$base/pool/default_ulimit_n",1024);
  
  ## a list with pgroups that will not be configured with ncm-dcache (and also not deleted)
  $new_base="$base/pool/ignore_pgroup";
  my $n=0;
  my @tmp_igr=();
  if ($config->elementExists("$new_base/$n")) {
  	while ($config->elementExists("$new_base/$n")) {
  		$tmp_igr[$n]=$config->getValue("$new_base/$n");
  		$n++;
  	}	
  }
  $p{$name}{ignore_pgroup}=\@tmp_igr;

  ## a default value for max_mover
  $p{$name}{default_mover_max} = fetch("$base/pool/default_mover_max",100);
  ## the maximum amount of diskspace in promille that will be set when using autogeneration
  $p{$name}{max_true_pool_size_prom} = fetch("$base/pool/max_true_pool_size_prom",950);
  
  ## 6. configure pools on machine
  ## do i need to run this one here?
  $serv="dcache";
  $link="/etc/init.d/$serv";
  if (exists($v{all_pool}{$shortname}{$shortname."_1"})) {
	## something pool related has been configured, run this

	## check for the link
	if (! -f $link) {
		pd("$serv should be configured here. Modify ncm-chkconfig and/or ncm-symlink accordingly! Exiting...","e");
		return 1;
	}
	
	$name="pools";
	$p{$name}{mode}="PLAIN_TEXT_NO_COMMENT";
	$p{$name}{filename}=$v{node_config}{POOL_PATH}."/pool_path";

	## the real work	
	config_pools($new_base,$shortname);
	dump_it($name);
  } else {
	## it's a bit too dangerous to let this component remove pools in this step.
	## maybe in later version
	
  	pd("$serv should not be configured here. Modify ncm-chkconfig accordingly!","e") if (-f $link);
  	return 1 if (! abs_stop_service($serv,"Going to stop $serv, this is not an pool node."));	
  } 	



  ##########################################################
  ##########################################################
  ##### make batch modifications

  $new_base="$base/batch";

  if ($config->elementExists($new_base)) {
  
  	make_config_batch($new_base)
    
  }
  

  
##################################################################################
##################################################################################
## starting part 2. dynamic config.
## includes all service checks and config changes that need running services.
  pd("Starting some additional checks.","i",15);
  ## checking/fixing some version specific problems
  return 1 if (version_config($admin));
  if ($admin) {
      ## sanity check
      if ($v{pnfs_config}{PNFS_ROOT} ne $v{node_config}{PNFS_ROOT}) {
	  	pd("sanity check: v{pnfs_config}{PNFS_ROOT} ne v{node_config}{PNFS_ROOT}: ".$v{pnfs_config}{PNFS_ROOT}." ne ".$v{node_config}{PNFS_ROOT}.". Aborting...","e");
	  return 1;
      }
      pd("sanity check: v{dc_setup}{pnfs} exists: ".exists($v{dc_setup}{pnfs}),"i",15);
      if (exists($v{dc_setup}{pnfs})) {
	  	pd("sanity check: v{dc_setup}{pnfs}=".$v{dc_setup}{pnfs},"i",15);
	  	pd("sanity check: v{node_config}{PNFS_ROOT}/fs=".$v{node_config}{PNFS_ROOT}."/fs","i",15);
       	if ($v{dc_setup}{pnfs} ne $v{node_config}{PNFS_ROOT}."/fs") {
		  	pd("sanity check: v{dc_setup}{pnfs} ne v{node_config}{PNFS_ROOT}/fs: ".$v{dc_setup}{pnfs}." ne ".$v{node_config}{PNFS_ROOT}.". Aborting...","e");
		    return 1;
		}    
      } elsif ($v{pnfs_config}{PNFS_ROOT}."/fs" ne "/pnfs/fs") {
      	pd("sanity check: v{dc_setup}{pnfs} does not exist, but the default /pnfs/fs doesn't match v{node_config}{PNFS_ROOT}/fs ".$v{node_config}{PNFS_ROOT}."/fs. Aborting...","e");
		return 1;
	  }	
  }
  ## other things that might go wrong. and need some rerunning of things:
  if ($admin && ! $chim) {  
  	## example one: postgres failed, component stopped, but everything else still needs to be run
	## for lcg-install (when ncm-dcache fails, quattor-lcg already makes the paths published in the info-system. can't have them there)
  	my $tmp_name_1=$v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID};
  	my $moved_suffix="-moved-for-pnfs-by-ncm-dcache".`date +%Y%m%d-%H%M%S`;
  	chomp($moved_suffix);
  	if (-e $tmp_name_1 && ! -l $tmp_name_1) {
  		## so it's not a link, but it will be used for dcache
  		## let's be non-destructive
  		if (move($tmp_name_1,$tmp_name_1."$moved_suffix")) {
  			pd("Moved ".$tmp_name_1." to ".$tmp_name_1."$moved_suffix.");
		} else {
			## it will never work, but next time make sure all goes well
			pd("Can't move ".$tmp_name_1." to ".$tmp_name_1."$moved_suffix. Please clean up.","e");
			return 1;
		}
  	}	
  	## ok, same check, probably never needed
  	$tmp_name_1=$v{node_config}{PNFS_ROOT}."/ftpBase";
  	if (-e $tmp_name_1 && ! -l $tmp_name_1 && ! $chim ) {
  		## so it's not a link, but it will be used for dcache
  		## let's be non-destructive
  		if (move($tmp_name_1,$tmp_name_1."$moved_suffix")) {
  			pd("Moved ".$tmp_name_1." to ".$tmp_name_1."$moved_suffix.");
		} else {
			## it will never work, but next time make sure all goes well
			pd("Can't move ".$tmp_name_1." to ".$tmp_name_1."$moved_suffix. Please clean up.","e");
			return 1;
		}
  	}
  	## another one, if there's a nfs server running on the nachine, mountd will conflict 
  	$real_exec="ps ax|grep mountd|grep -v grep";
  	if (($chim || ! check_status("pnfs")) && (! sys2($real_exec))) {
  		pd("There is already a mountd process active (maybe an nfs server is running?). This will conflict with pnfs.","e");
  		return 1;
  	}	
  	## another one, nfs filesystem not supported 
  	$real_exec="cat /proc/filesystems |grep nfs";
  	if (sys2($real_exec)) {
		pd("Filesystem nfs not supported by kernel. Trying to modprobe nfs. (This sometimes happens on a first boot after ks-install).");
		pd("Modprobing nfs failed.","w") if (sys2("modprobe nfs"));
		$real_exec="cat /proc/filesystems |grep nfs";
		if (sys2($real_exec)) {
	  		pd("Filesystem nfs not supported by kernel. Need a reboot/kernel upgrade?","e");
  			return 1;
  		}	
  	}	
  }
  pd("Starting real configuration.","i",15);
###############################################################
###############################################################
  ## remap flags to service calls
  my ($pgsql_restart,$pgsql_reload,$pnfs_restart,$pnfs_install,$core_restart,$core_install,$pool_restart,$pool_install,$chim_restart);
  if ($admin||$slony) {
	$pgsql_reload = $p{pg_hba}{changed};
  	$pgsql_restart=($p{pg_script}{changed} ||$p{pg_conf}{changed});
  }
  if ($admin) {
    if ($chim) {
        ## a restart is only needed for changed /etc/exports --> done in chimera_setup
        ## but it needs a working dcacheSetup (for the java version)
        $chim_restart=$p{dc_setup}{changed};
    } else {	
      	## $pnfs_install just does this: run the install script. no stop/start
      	$pnfs_install=($p{pnfs_config}{changed} || $pnfssetup_file_missing);
  	    $pnfs_restart=($pnfs_install || $p{pnfs_setup}{changed});
  	}  
  }
  
  if ($admin||$door) {
	$core_install=($p{node_config}{changed}||$p{dc_setup}{changed});
	$core_restart=$core_install;
	$pool_install=$p{pools}{changed};
	$pool_restart=$pool_install;
  } elsif ($slony) {
  } else {
   	$pool_install=($p{node_config}{changed}||$p{dc_setup}{changed}||$p{pools}{changed});
    $pool_restart=$pool_install;
  }

  ## 
  ## first the admin case
### postgresql
## we assume that either postgres is running correctly or is startable without any problems.
	if ($admin) {
		return 1 if (! abs_start_service($postgresql_serv,"Going to make sure postgres is running. If not, please check the postgresql installation."));
	}	
## save to assume that postgres is up and running here

#############
  if ($admin) {	
  	## pnfs
  	if ($pnfs_restart && ! $chim ) {
  		pd("Restarting pnfs.");
  		stop_service("dcache","pnfs");
  		$name="pnfs_config";	
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			pd("Config of $name changed. Writing...");
			dump_it($name,"WRITE");
		}

  		if ($pnfs_install) {
  			pd("Installing pnfs.");
  			## the directory $v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID} should not exist
  			if (-d $v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID}) {
  				pd($v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID}." found and shouldn't be here.","e");
  			}	
  			$real_exec=$p{pnfs_config}{pnfs_install_dir}."/install/pnfs-install.sh";
  			if (-x $real_exec) {
  				pd("$real_exec failed.","e") if (sys2($real_exec));
  			} else {
  				## there's no use in continuing, is there?
  				pd("$real_exec: not found or wrong permissions. Check your installation.","e");
  				return 1;
  			}
  		}
  		$name="pnfs_setup";	
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			if (-f $p{$name}{filename}) {
				if ($pnfssetup_file_missing) {
					## ok, so the first time this file was not read to collect the values
					## do it first
					pd("pnfssetup_file_missing: slurp first.","i","10");
					slurp($name,"$base/pnfs/pnfs_setup","/usr/etc");
				}	
				$self->info("Config of $name changed. Writing...");
				dump_it($name,"WRITE");
			} else {
				pd("p{$name}{changed} was set but p{$name}{filename} ".$p{$name}{filename}." was not found. Skipping this one...","e","1");
			}	
		}
  		start_service(0,"pnfs");
  	}
  	if ($chim) {
  	  ## nothing here for now. (no garantee that dcacheSetup is ok)   
  	} else {				
      return 1 if (! abs_start_service("pnfs","Going to start pnfs, probably something changed to postgres but not to pnfs."));

	  ## if pnfs is up, localhost:/fs should be mounted (it's in the start script)
	  $real_exec="df |grep \"^localhost:/fs[[:space:]]\"";
	  if (sys2($real_exec)) {
		pd("$real_exec: failed. localhost:/fs should be mounted after a succesful start of pnfs.","e");
		return 1;
	  }
	}  	
###########
  } else {
  	## this is not an admin node
  	## pnfs nor postgres should not be running. probably not even installed
  	## this is now handled elsewhere for pnfs (with the unlinking)
	## postgres 
	if (check_status($postgresql_serv)) {
		## same story, you should never get here
		pd("$postgresql_serv status returned $postgresql_serv up but this is not an admin node. Something's really wrong...","e");
		return 1;
	}	
  }	
###########################
###########################    
	## dcache-core and dcache-pool
	if ($core_restart||$pool_restart) {
		## stopping with the old values of the config files...
		pd("Restarting dcache.") if ($pool_restart||$core_restart);
		stop_service("dcache") if ($pool_restart||$core_restart);
		$name="node_config";
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			pd("Config of $name changed. Writing...");
			dump_it($name,"WRITE");
		}
		$name="dc_setup";
		$new_base="$base/config/dCacheSetup";	
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			pd("Config of $name changed. Writing...");
			#dump_it($name,"WRITE");
			make_config_dcachesetup($name,$new_base,$dc_dir,'no');
			
		}
		
		## we have a valid dcacheSetup now. (needed for first time install).
		if($admin && $chim) {
            if (chimera_setup($chim_restart)) {
                pd("Something went wrong during chimera setup. Exiting.");
                return 1;
            };
            return 1 if (! abs_start_service("chimera-nfs","Going to start chimera-nfs, probably something changed to postgres but not to chimera."));
        } 
		
		$name="pools";	
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			pd("Config of $name changed. Writing...");
			dump_it($name,"WRITE");
		}
  		if ($core_install||$pool_install) {
  			pd("Installing dcache (core).") if ($core_install);
  			pd("Installing dcache (pool).") if ($pool_install);
  			$real_exec="$dc_dir/install/install.sh";
  			if (-x $real_exec) {
  				pd("$real_exec failed.","e") if (sys2($real_exec));
  			} else {
  				pd("$real_exec: not found or wrong permissions. Check your installation.","e");
  			}
  		}
  		start_service(0,"dcache") if ($pool_restart||$core_restart);
  	}	
	if ($admin||$door) {
	    return 1 if (! abs_start_service("dcache","Going to start dcache, probably something changed to postgres or pnfs but not to dcache-core."));
	} else {
		## this is now done with the unlinking of /etc/init.d/dcache
	}	
	###########
	if (-f $v{node_config}{"POOL_PATH"}."/pool_path") {
		## pool should be running if such a file exist
	    return 1 if (! abs_start_service("dcache","Going to start dcache (pool), probably something changed to postgres or pnfs but not to dcache."));
	} else {
		## or the reverse
		return 1 if (! abs_stop_service("dcache"));
	}

    ## we have a valid dcacheSetup here
    ## do necessary pns/chimera things
    if ($admin) {
        if($chim) {
            if (chimera_setup($chim_restart)) {
                pd("Something went wrong during chimera setup. Exiting.");
                return 1;
            };
            return 1 if (! abs_start_service("chimera-nfs","Going to start chimera-nfs, probably something changed to postgres but not to chimera."));
        } else {    
            ##########################################
            ### pnfsexports
	        ## it's up, set export rules, no restart needed
	        $new_base="$base/pnfs/exports";
	        if ($admin && $config->elementExists("$new_base/0")) {
		      ## this function removes all existing ones before writing new ones
		      pnfs_exports($new_base);
	        }	

            ##########################################################
            #### pnfsdatabases
	        if ($admin) {
		          ## requires running pnfs, so everything above must be running!!
	              return 1 if (config_pnfsdatabases("$base/pnfs/databases"));
	        }
        }
    }	   
	
##########################################################
#### admin user things
	if ($admin) {
		## setup admin?
		return 1 if (config_admin_user());
	}

########################################################################
#### pool groups + mover max
	if ($admin) {
		make_conf($base);
	}
  
########################################################################
#### some words of advice
	give_advice();

  
############################################
## only subs now 
 
##########################################################################
sub pd {
##########################################################################
  my $text = shift;
  my $method = shift || "i";
  my $level = shift || "5";
  
  if ($level <= $debug_print) {
	  if ($method =~ m/^i/) { 
	  	$self->info($text);
	  } elsif ($method =~ m/^e/) {
	  	$self->error($text);
	  } elsif ($method =~ m/^w/) {
	  	$self->warn($text);
	  } else {
	  	$self->error("Unknown method $method in pd. Text was $text");
	  }
  }	  	
}

##########################################################################
sub sys2 {
##########################################################################
	## is a wrapper for system(). that's why it has these strange exitcodes
	## >0 is failure (the numeric values are not the same as in eg bash)
	## but it's the same as running with system($exec)
	my $exitcode=1;	
	my @argg=@_;

	my $exec=shift;
	my $use_system = shift || "true";
	## needs $use_system==0
	my $return_both = shift || "false"; 
	my $pd_val=5;
	if ($return_both eq "nothing") {
		$pd_val = "1000000";
	}	

	my $func = "sys2";
	pd("$func: function called with arg: @argg","i",$pd_val+5);

	my $output ="";
	
	if ($use_system eq "true") {
	    system($exec);
	    $exitcode=$?;
	    pd("$func:exec: $exec","i",$pd_val);
	    pd("$func:exitcode: $exitcode","i",$pd_val);
	} else {
	    if (! open(FILE,$exec." 2>&1 |")){
			pd("$func: exec=$exec: $!","e","i",$pd_val);
		} else {
			$output="";
			pd("$func: Processing FILE now","i",$pd_val+13);
			while(<FILE>) {
			    pd("$func: Processing FILE now: $_",,"i",$pd_val+13);
			    $output .= $_;
			}	
			close(FILE);
			$exitcode=$?;
			pd("$func:exec: $exec","i",$pd_val);
			pd("$func:output: ".$output,"i",$pd_val);
			pd("$func:exitcode: $exitcode","i",$pd_val);
	    }
	}
	if ( ($use_system ne "true") && ($return_both eq "true")) {
		return ($exitcode,$output);
	} else {		
		return $exitcode;	
	}	
}

##########################################################################
sub snr {
##########################################################################
	my $func = "snr";
	pd("$func: function called with arg: @_","i","10");
	my $tmp_file = shift;
	my $search = shift;
	my $replace = shift;
	my $backup = shift || ".backup";
	
    copy($tmp_file,$tmp_file.$backup) || pd("Can't copy $tmp_file to ".$tmp_file.$backup.": $!","e");
    open(FILE, $tmp_file.$backup) || pd("Can't open ".$tmp_file.$backup.": $!","e");
    open(FILE_NEW, "> $tmp_file") || pd("Can't open $tmp_file: $!","e");
    while (<FILE>) {
		s/$search/$replace/g;
	  	print FILE_NEW $_;
    }
    close(FILE_NEW);
    close(FILE);
    return 1;  
}

##########################################################################
sub version_config {
##########################################################################
    ## solve some verison specific problems
    my $func = "version_config";
    pd("$func: function called with arg: @_","i","10");

    my $adm = shift || 0;
    
    ## you can get the version from /software/packages/dcache_2dserver
    ## it should be installed since spma runs before ncm-dcache
    ## nah, use sys2
    my $real_exec="rpm -qa|grep dcache-server";
    my ($exitcode,$output) = sys2($real_exec,"false","true");
    if ($exitcode){
		pd("$func: dcache-server rpm not found. Is impossible.","e");
		return 1;
    } else {
    	chomp($output);
		$output =~ s/dcache-server-//;
		pd("$func: dcache-server rpm found. Version: $output.","i","10");
    }
    
    if (($output =~ m/1.8.0-/)) {
		## add a ulimit -n option to dcache-pool
		snr("/opt/d-cache/bin/dcache",'start\).*','start) ulimit -n '.$p{all_pools}{ulimit_n});

        ## admin only
        if ($adm) {
    		## fix umount behaviour on CentOS5.1
    		if (! $chim) { 
    	       	snr("/opt/pnfs/bin/pnfs","umount /pnfs/fs","umount -i /pnfs/fs") if ( -f "/sbin/umount.nfs");

                ## replace /pnfs/fs with $p{pnfs_config}{PNFS_ROOT} in /opt/pnfs/bin/pnfs
                ## should run only on admin node
    		    snr("/opt/pnfs/bin/pnfs",' /pnfs/fs'," ".$v{pnfs_config}{PNFS_ROOT}.'/fs') if (exists($v{pnfs_config}{PNFS_ROOT}));
    		} else {
    		  snr("/etc/init.d/chimera-nfs","# chkconfig:.*","# chkconfig: 345 91 9");
    		}   
    	};
#	} elsif ($output eq "x.y.z-a") {
    } else {
    	pd("$func: ncm-dcache not tested with version $output?. Stopping now...","e","1");
    	return 1;
	}
    return 0;
}

##########################################################################
sub add_pnfsdatabase {
##########################################################################
	my $func = "add_pnfsdatabase";
	pd("$func: function called with arg: @_","i","10");

	## assume checking for conflict has been done
	my ($tools_set,$pnfs_db_dir,$db_name,$db_path,$full_path)=@_;
	my $real_exec;
	$full_path =~ s/\/$//;
	my $path=$full_path;
	my $new_dir=$full_path;
	$path=~s/\/[^\/.]*$//;
	$new_dir =~ s/.*\///;
	if (-d $full_path) {
		## don't add databases when the full path already exists. This might remove everything that's already in this path
		## maybe there's a clean way to do this
		pd("$func: path $full_path already exists. Not adding this one.","e","1");
		return 1;		
	}	
	## check if path exists
	if (! -d $path) {
		pd("$func: Can't find $path. Creating it...");
		$real_exec="mkdir -p $path";
		if (sys2($real_exec)) {
			pd("$func: Can't run $real_exec: $!");
			return 1;
		}	
	}	
	$real_exec="$tools_set mdb create $db_name $db_path;touch $db_path;mdb update";
	$self->error("$func: Can't run $real_exec") if (sys2($real_exec));
	my %tmp_db=list_pnfsdatabase($tools_set,$pnfs_db_dir);
	if (exists $tmp_db{$db_name}) {
		$real_exec="$tools_set cd $path; mkdir \'.($tmp_db{$db_name}[0])($new_dir)\'";
		pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
		$real_exec="$tools_set sclient getroot \${shmkey} 0|awk \'{print \$3}\'";
		my $wormholepnfsid;
		open(TMP,"$real_exec |") || $self->error("$func: Can't run $real_exec: $!","e","1");
		while (<TMP>) {
			chomp;
			$wormholepnfsid=$_;
		}
		close TMP;
		$real_exec="$tools_set sclient getroot \${shmkey} $tmp_db{$db_name}[0] $wormholepnfsid";
		pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
		$real_exec="cd $full_path;echo \'StoreName myStore\' > \'.(tag)(OSMTemplate)\';echo \'STRING\' > \'.(tag)(sGroup)\'";
		pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
	} else {
		pd("$func: Something went wrong with the creation of $db_name / $db_path","e","1");
		return 1;
	}
	return 0;	
}

##########################################################################
sub del_pnfsdatabase {
##########################################################################

}

##########################################################################
sub list_pnfsdatabase {
##########################################################################
	my $func = "list_pnfsdatabase";
	pd("$func: function called with arg: @_","i","10");

	my ($tools_set,$pnfs_db_dir) = @_;
	my $real_exec="$tools_set mdb show|grep $pnfs_db_dir";
	open(TMP,"$real_exec |") || $self->error("$func: Can't run $real_exec: $!");
	my %pdb=();
	my @tmp=();
	while (<TMP>) {
		chomp;
		s/^\s+//;
		@tmp=split(/\s+/,$_);
		## $tmp[1] is the name
		$pdb{$tmp[1]}=\@tmp;
	}
	close TMP;		
	return %pdb;
}

##########################################################################
sub config_pnfsdatabases  {
##########################################################################
    ## is a wrapper for system(). that's why it has these strange exitcodes
    my $func = "config_pnfsdatabases";
    pd("$func: function called with arg: @_","i","10");

    ## pnfs databases need dcache running
    my $new_base= shift;
	if ($config->elementExists("$new_base/0")) {
		## databases in pnfs
    	## check maximum numbers of servers
    	## maybe add this to the config possibilities
    	my $pnfstools="source ".$p{pnfs_setup}{filename}.";PATH=".$p{pnfs_config}{pnfs_install_dir}."/tools:\$PATH;";
	    my $max_shmserv=0;
  		open(TMP,$p{pnfs_setup}{filename}) || $self->error("$func: Can't open ".$p{pnfs_setup}{filename}.": $!");
    	while (<TMP>) {
   			$max_shmserv = $1 if (m/^shmservers=(\d+)/);
    	}
	    close TMP;
	    pd("$func: Max shmservers=$max_shmserv.","i","15");
		my (%pdb,$path,$size,$opt,$max,$all,%tmp_pdb,$k,$exi);
		my $n=0;
		while ($config->elementExists("$new_base/$n")) {
    	  	$all = $config->getElement("$new_base/$n");
	      	while ( $all->hasNextElement() ) {
			  	my $el = $all->getNextElement();
			  	my $el_name = $el->getName();
			  	my $el_val = $el->getValue();
		  	  	$pdb{$el_name}=$el_val;
		  	}	  
   		  	$n++;
		  	## check if "path" if relative or not (relative to $v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID}."/".
		  	if ($pdb{"path"} !~ m/^\//) {
		   		$pdb{"path"}=$v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID}."/".$pdb{"path"};
		  	}	

     		%tmp_pdb=list_pnfsdatabase($pnfstools,$v{pnfs_config}{PNFS_DB});
	     	## current number of entries (must be <= than $max_shmserv)
			my $number_of_pnfsdb = scalar(keys(%tmp_pdb));
			if (! exists($tmp_pdb{$pdb{"name"}})) {
				if (($number_of_pnfsdb +1) > $max_shmserv) {
	    			pd("$func: Total number of pnfs databases ".($number_of_pnfsdb +1)." > number of shmservers allowed $max_shmserv if we add ".$pdb{"name"},"w","1");
   		  		} else {
					## adding pnfsdb
					if (add_pnfsdatabase($pnfstools,$v{pnfs_config}{PNFS_DB},$pdb{"name"},$v{pnfs_config}{PNFS_DB}."/pnfs/databases/".$pdb{"name"},$pdb{"path"})) {
						pd("$func: adding pnfsdb ".$pdb{"name"}." failed","e","1");
					} else {
					}	
				}	
	  		} else {
	  			## already in database
	  			pd("$func: ".$pdb{"name"}." already in database, not adding again.","i","15");
	  		}
	  		if (-d $pdb{"path"}) {
		  		## fix the permissions if any are set
				my $real_exec="";
				if (exists($pdb{"user"})) {
					## not recursive. (takes too much time with a rerun)
					$real_exec .="chown ".$pdb{"user"};
					$real_exec .= ".".$pdb{"group"} if (exists($pdb{"group"}));
					$real_exec .= " ".$pdb{"path"}.";";
				}
				if 	(exists($pdb{"perm"})) {
					$real_exec .="chmod ".$pdb{"perm"}." ".$pdb{"path"}.";";
				}	
				pd("$func: Can't run $real_exec: $!","e","1") if (sys2($real_exec));
			} else {
				pd("$func: Can't find ".$pdb{"path"},"w","1");
			}		
   		}
   	}
   	return 0;	
}	

##########################################################################
sub check_status {
##########################################################################
	my $func = "check_status";
	pd("$func: function called with arg: @_","i","10");
	
	## return: 1 is up, 0 is down
	my $service = shift;
	my $real_exec;
	if ($service eq "pnfs") {
	  $real_exec="ps ax|grep pnfsd|grep -v grep";
	} elsif ($service eq "chimera-nfs") {
      $real_exec="ps axf|grep org.dcache.chimera.nfs|grep -v grep";
    } elsif ($service eq "dcache-core") {
	  $real_exec="ps ax|grep jobs|grep start|grep -v pool|grep -v grep";
	} elsif ($service eq "dcache-pool") {
	  $real_exec="ps ax|grep jobs|grep start|grep pool|grep -v grep";
    } elsif ($service eq "dcache") {
      $real_exec="/opt/d-cache/bin/dcache status|grep stopped";
	} elsif ($service eq "POSTGRES_DUMMY_VALUE") {
	  $real_exec="ps ax|grep postmaster|grep -v grep";
	} else {
	  $real_exec="/etc/init.d/$service status";
	}  
	
	if ($service eq "dcache") {
	   ## $? = 1 is a (partially) stopped service.
       if (sys2($real_exec)) {
          return 1;
       } else {
          return 0;
       }
	} else {
	  ## $? = 0 is a running service.
       if (sys2($real_exec)) {
          return 0;
       } else {
          return 1;
       }
	
    }
}

##########################################################################
sub stop_service {
##########################################################################
	my $func = "stop_service";
	pd("$func: function called with arg: @_","i","10");

	my @services = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if not up, don't stop
		if (check_status($se)) {
			$real_exec="/etc/init.d/$se stop";
			pd("Can't stop $se using $real_exec.","e") if (sys2($real_exec));
		}
	}
	my $exitcode=1;
	## recheck if everything is down now.
	foreach $se (@services) {
		## check status, if up, flag error
		if (check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;		
}

##########################################################################
sub reload_service {
##########################################################################
	my $func = "reload_service";
	pd("$func: function called with arg: @_","i","10");

	my @services = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if not up, start
		if (check_status($se)) {
			$real_exec="/etc/init.d/$se reload";
			pd("Can't reload $se using $real_exec.","e") if (sys2($real_exec));
		} else {
			start_service(0,$se)
		}	
	}
	my $exitcode=1;
	## recheck if everything is up now.
	foreach $se (@services) {
		## check status, if down, flag error
		if (! check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;		
}

##########################################################################
sub start_service {
##########################################################################
	my $func = "start_service";
	pd("$func: function called with arg: @_","i","10");

	my ($force_restart,@services) = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if up, don't start
		if (! check_status($se)) {
			$real_exec="/etc/init.d/$se start";
			pd("Can't start $se using $real_exec.","e") if (sys2($real_exec));	
		} elsif ($force_restart) {
			pd("Can't start $se: service is running. Forcing restart","e");
			$real_exec="/etc/init.d/$se restart";
			pd("Can't start $se using $real_exec.","e") if (sys2($real_exec));
		} else {
			pd("Won't start $se: service is running.")
		}	
	}
	my $exitcode=1;
	## recheck if everything is up now.
	foreach $se (@services) {
		## check status, if down, flag error
		if (! check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;	
}

##########################################################################
sub abs_stop_service {
##########################################################################
	my $func = "abs_stop_service";
	pd("$func: function called with arg: @_","i","10");

	my $serv = shift;
	my $reason_1 = shift || "Stopping service $serv now.";
	$reason_1 .= " (ABS-mode)";
	my $reason_2 = shift || "Stopping service $serv failed. Something's really wrong. Exiting...";
	## check the status and shut it down
  	if (check_status($serv)) {
		pd($reason_1);
		stop_service($serv);
	}	
	## is $serv up?
	if (check_status($serv)) {
		## same story, you should never get here
		pd($reason_2,"e");
		return 0;
	} else {
		return 1;
	}	
}

##########################################################################
sub abs_start_service {
##########################################################################
	my $func = "abs_start_service";
	pd("$func: function called with arg: @_","i","10");

	my $serv = shift;
	my $reason_1 = shift || "Starting service $serv now.";
	$reason_1 .= " (ABS-mode)";
	my $reason_2 = shift || "Starting service $serv failed. Something's really wrong. Exiting...";
	## check the status and start it
  	if (! check_status($serv)) {
		pd($reason_1);
		start_service(0,$serv);
	}	
	## is $serv up?
	if (! check_status($serv)) {
		## same story, you should never get here
		pd($reason_2,"e");
		return 0;
	} else {
		return 1;
	}	
}

##########################################################################
sub make_service {
##########################################################################
	my $func = "make_service";
	pd("$func: function called with arg: @_","i","10");

    ## make the symlinks and set to start on all runlevels
	## currently, runs every time. shouldn't do any harm though
	## even if the link is there, regenerate it

	my $serv = shift;
	my $sym = shift;
	my $link = shift;
	
	if ($link ne $sym) {
	    pd("$func: creating link between $sym and $link");
	    unlink($link) || $self->warn("Can't unlink $link: $!");
	    symlink($sym,$link) || $self->error("Can't symlink $sym to $link: $!");
	}    
	my $real_exec="chkconfig --add $serv;chkconfig $serv on";
	pd("Can't run $real_exec.","e") if (sys2($real_exec));
}

##########################################################################
sub remove_service {
##########################################################################
	my $func = "remove_service";
	pd("$func: function called with arg: @_","i","10");
	my $serv = shift;
	my $link = shift;
  	if (-e $link) {
		unlink($link) || $self->warn("Can't unlink $link: $!");
		my $real_exec="chkconfig --del $serv;chkconfig $serv off";
		pd("Can't run $real_exec.","e") if (sys2($real_exec));
	}	
}


##########################################################################
sub fetch {
##########################################################################
  my $func = "fetch";
  pd("$func: function called with arg: @_","i","10");
  my $path = shift;
  my $default = shift || "";
  my $value;
  
  if ($config->elementExists($path)) {
  	$value = $config->getValue($path);
  } else {
  	$value = $default;
  }
  return $value;
} 

##########################################################################
sub config_admin_user {
##########################################################################
	## set priv/pub keypair for $user who can access dcache as admin
	## makes it possible run commands using sub run_as_admin
	my $func = "config_admin_user";
	pd("$func: function called with arg: @_","i","10");
	
	## do you really need to run it every time??
	## install it in $homedir as $user 
	my $user = shift || "root";
	my ($homedir,$real_exec);
	open(FILE,"/etc/passwd") || pd("$func: Can't open /etc/passwd: $!","e");
	while (<FILE>) {
		$homedir=$1 if (m/^$user:[^:]*:[^:]*:[^:]*:[^:]*:([^:]*):[^:]*/);
	}
	close(FILE);	

	my $key_name = shift || "$homedir/.ssh/dcache_admin_key";
	my $conf_file = shift || "$homedir/.ssh/dcache_admin_config";
	
	$p{dc_setup}{dcache_admin_config} = $conf_file;
	
	## check for $homedir/.ssh, if not, create
	if (! -d "$homedir/.ssh") {
		$real_exec="mkdir -p $homedir/.ssh";
		pd("$func: Can't $real_exec: $!","e") if (sys2($real_exec));
	}	

	## check the port!
	## normally you can find it with $v{dc_setup}{adminPort}, 
	## but this might contain ${portBase} which is a ref to $v{dc_setup}{portBase}
	my $port="22223";
	if ($v{dc_setup}{adminPort} =~ m/^\d+$/) {
		## there's only numbers, but maybe the wrong ones...
		$port=$v{dc_setup}{adminPort};
	} else {
		pd("$func: Non-number found	in v{dc_setup}{adminPort}: ".$v{dc_setup}{adminPort},"e",1);
		return 1;
	}	

	## make the dcache_admin_config
	open(FILE,"> $conf_file") || pd("$func: Can't open $conf_file: $!.");
	print FILE "Host *\n";
	print FILE "Protocol 1\n";
	print FILE "StrictHostKeyChecking no\n";
	print FILE "PreferredAuthentications publickey\n";
	print FILE "PasswordAuthentication no\n";
	print FILE "Cipher blowfish\n";
	print FILE "IdentityFile $key_name\n";
	print FILE "Port $port\n";
	close FILE;

	## set the values in p{admin}
	$p{admin}{key}=$key_name;
	$p{admin}{port}=$port;
	$p{admin}{user}='admin';
	$p{admin}{host}='localhost';

	if (! -f $key_name) {
		## generate key
		## creates the private/pub keys and gives them to the users key
		$real_exec="ssh-keygen -t rsa1 -N \"\" -f $key_name -C admin";
		pd("$func: Can't $real_exec: $!","e") if (sys2($real_exec));
		## fixing permissions
		$real_exec="chmod -R 700 $homedir/.ssh;chown -R $user $homedir/.ssh";
		pd("$func: Can't $real_exec: $!","e") if (sys2($real_exec));
	}	

	open(FILE,$key_name.".pub") || pd("$func: Can't open ".$key_name.".pub: $!","e");
	while (<FILE>) {
		if (m/(^\d+\s+\d+\s+(\d+)\s+admin$)/) {
			## $1 is whole file, $2 the pubkey
			## check if pubkey is in $v{node_config}{DCACHE_BASE_DIR}/config/authorized_keys
			my $exi=0;
			if (-f $v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys") {
				open(FILE2,$v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys") || pd("$func: Can't open ".$v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys: $!","e");
				while (<FILE2>) {
					$exi=1 if (m/$2/);
				}
				close FILE2;					
			}
			if (! $exi) {
				open(FILE2,">> ".$v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys") || pd("$func: Can't open ".$v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys for writing: $!","e");
				print FILE2 $1."\n";
				close FILE2;
				pd("$func: Added key $2 to ".$v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys.","i","10");
			} else {
				pd("$func: Key $2 already in ".$v{node_config}{DCACHE_BASE_DIR}."/config/authorized_keys.","i","10");	
			}	
		}
	}
	close FILE;
		
	## wait some time before you first try it. (a few minutes??)
	my $try=0;
	my $ok="false";
	while ( ($ok eq "false") && ($try < 3)) {
		pd("$func: try $try connecting as admin","i","10");
		if (test_dconf()) {
			sleep 60;
		} else {
			$ok="true";
		}	
		$try++;
	}
	if ($ok eq "false") {
		pd("$func: Trying to connect as admin failed. Stopping now","e");
		return 1;	
	} else {
		my $admin_passwd;
		## check if passwd if configured, if not scramble it
		if (exists($p{dc_setup}{admin_passwd}) && (!$p{dc_setup}{admin_passwd} ne "")) {
			$admin_passwd=$p{dc_setup}{admin_passwd};
		} else {	
			## scrambles passwd (you can always connect using the key)
			pd("$func: Setting random passwd: You can always connect using ssh -F $conf_file admin\@localhost.");
			my @chars=('a'..'z','A'..'Z','0'..'9','_');
			my $random_string;
			## 15 random characters as passwd. well, it's safer than a fat elk. 
			foreach (1..15) {
				# rand @chars will generate a random 
				# number between 0 and scalar @chars
				$random_string.=$chars[rand @chars];
			}
			$admin_passwd=$random_string;
		}	
		## "nothing" is used to make sure that the passwds don't end up in the logs
		$real_exec="cd acm\n";
		my $exi=0;
		if (-f $v{node_config}{DCACHE_BASE_DIR}."/config/passwd") {
			open(FILE,$v{node_config}{DCACHE_BASE_DIR}."/config/passwd") || pd("Can't open ".$v{node_config}{DCACHE_BASE_DIR}."/config/passwd: $!","e","1");
			while (<FILE>) {
				$exi=1 if (m/^admin:/);
			}
			close(FILE);
		}
		if (! $exi) {
			$real_exec .= "create user admin\n";
		}
		$real_exec .="set passwd -user=admin $admin_passwd $admin_passwd\n..\nlogoff";
		run_as_admin($real_exec,"nothing");
	}	
	return 0;
}

##########################################################################
sub run_as_admin {
##########################################################################
	my @argg=@_;

	my $cmd = shift;
	my $return_both = shift || "false";
	## never used at all?
	my $config_file = shift || $p{dc_setup}{dcache_admin_config};

	my $pd_val=5;
	if ($return_both eq "nothing") {
		$pd_val = "1000000";
	}	
	my $func = "run_as_admin";
	pd("$func: function called with arg: @argg","i",$pd_val);
	

	## only run from admin at this moment.
	my $host="localhost";
	my $tmp_file="/tmp/dcache_admin";
	open(FILE,"> $tmp_file") || pd("$func: Can't open $tmp_file: $!");
	print FILE $cmd."\n";
	close FILE;
	
	my $real_exec = "ssh -F $config_file admin\@$host \<$tmp_file";
	my ($exitcode,$output);
	## sys2 needs false for use_system here!
	if ($return_both eq "true") {
		($exitcode,$output) = sys2($real_exec,"false","true");
		## maybe parse the output a bit first?
		## remove the leading ^M characters (\r in perl regexp or \cM)
		$output =~ s/\r//g;
		return ($exitcode,$output);
	} elsif ($return_both eq "nothing") {
		$exitcode = sys2($real_exec,"false","nothing");
		return $exitcode;
		unlink($tmp_file) || pd("$func: Can't unlink $tmp_file: $!","e");
	} else {	
		$exitcode = sys2($real_exec,"false");
		return $exitcode;
		unlink($tmp_file) || pd("$func: Can't unlink $tmp_file: $!","e");
	}	
}

##########################################################################
sub check_ok {
##########################################################################
	my $func = "check_ok";
	pd("$func: function called with arg: @_","i","10");

  my (@checks) = @_;
  my $ok = 1;
  my $ch;
  foreach $ch (@checks) {
      if (! $config->elementExists($ch)) {
        $self->error("$ch not found.");
        $ok=0;
      }
  }
  if (! $ok) {
    $self->error("Something went wrong during initial checking. Stopping component.");
  }
  return $ok;
}  

##########################################################################
sub slurp {
##########################################################################
	my $func = "slurp";
	pd("$func: function called with arg: @_","i","10");

	my $name=shift;
	my $new_base=shift;
	my $def_dir=shift;
	my $mode=$p{$name}{mode};
	pd("$func: Start with name=$name mode=$mode","i","10");

	## check for case insensitive
	my $capit=0;
	if ((exists $p{$name}{case_insensitive}) && (1 == $p{$name}{case_insensitive})) {
		$capit = 1;
	}
	my $convert_boolean=0;
	if ((exists $p{$name}{convert_boolean}) && (1 == $p{$name}{convert_boolean})) {
		$convert_boolean = 1;
	}
    ## ok, lets see what we have here
    my @def_list=();  
    ## if $new_base is of the format file://, use that one
	if ($new_base =~ m/^file:\/\//) {
		$new_base =~ s/^file:\/\///;
		unshift @def_list, $new_base;
		$new_base=0;
	}
	
    my $n=0;
	## read all default files to be parsed BEFORE reading configured values
    while ($new_base && $config->elementExists($new_base."_def/".$n)) {
	  my $tmp = $config->getValue($new_base."_def/".$n);
      ## if $tmp doesn't start with /, add $def_dir
      if ($tmp !~ m/^\//) {
        $tmp = "$def_dir/$tmp";
      }
      if (-f $tmp) {
        unshift @def_list, $tmp;
      } else {
        $self->warn("$func: Default file $tmp from ".$new_base."_def/".$n." not found.");
      }
      $n++;
    }
    
    foreach my $tmp (@def_list) {
    	if ($mode =~ m/BASH_SOURCE/) {
			## ok, for BASH_SOURCE we need to do some more or get a real parser somewhere.
    		## we make the assumption that the files can be sourced whithout problems whithout interlinked variables
    		## also that the variables passed through quattor-config contain no other variables

			## in this run, values can be overwritten again by what's defined in the files. this is why the following needs to be run everytime
		    if ($new_base && $config->elementExists("$new_base")) {
				my $all = $config->getElement("$new_base");
				while ( $all->hasNextElement() ) {
					my $el = $all->getNextElement();
					my $el_name = $el->getName();
					$el_name =~ tr/a-z/A-Z/ if $capit;
					my $el_val;
					my $tmp_el_val=$el->getValue();
					if ($convert_boolean && ($tmp_el_val eq'true')) {
						$el_val='yes';
					} elsif($convert_boolean && ($tmp_el_val eq 'false')) {
						$el_val='no';
					} else {
						$el_val = $tmp_el_val;
					}

					## overwrite defaults or add new values
					$v{$name}{$el_name}=$el_val;
    	  		}
			} else {
		  		$self->warn("$func: Nothing set for $new_base (1).") if ($new_base);
			}
			
    		## snr all variables with values set in previous files/quattor config or leave them untouched.
    		my $tmp2=$tmp."-2";
    		open(FILE,$tmp) || pd("$func: Can't open $tmp: $!.","e",1);
    		open(OUT,"> $tmp2") || pd("$func: Can't open $tmp2 for writing: $!.","e",1);
    		while(<FILE>){
    			## shouldn't we filter out comments and whitespace here? For speed...
				 if (m/^\s*$/ || m/^\s*\#.*/) {
			        ## do nothing
			    } else {
			    	## we're replacing all usage of $x and ${x} with the values defined
	    			for my $key (keys(%{$v{$name}})) {
    					while (m/[^\\]?\$\{$key\}/) {
				            s/([^\\]?)\$\{$key\}/$1$v{$name}{$key}/;
      	  				}
        				while (m/[^\\]?\$$key\W?/) {
			        	    s/([^\\]?)\$$key(\W?)/$1$v{$name}{$key}$2/;
	        			}
    	    		}	
        			print OUT;
        		}	
			}
			close(FILE);
			close(OUT);    				
			    		
    	   	## to read config files that can be used to source the variables
	      	## here's an original approach to extract the values ;)
	      	my $exe="source $tmp2";
    	  	open(FILE, "/bin/bash 2>&1 -x -c \"$exe\" |") || $self->error("$func: /bin/bash 2>&1 -x -c \"$exe\" didn't run: $!");
	      	my $now=0;
    	  	while (<FILE>){
		  		s/\+\+ //g;
			  	s/\+ //g;
			  	if ($now) {
			      	chomp;
			      	my $i=index($_,"=");
			      	my $k = substr($_,0,$i);
			      	$k =~ tr/a-z/A-Z/ if $capit;
	    		  	$i++;
		    	  	my $va = substr($_,$i,length($_));
		    	  	## there's a difference between bash v2 and v3 when using +x and multiple lines. 
		    	  	## v3 adds single quotes (which is the correct thing todo btw)
		    	  	## they need to be removed though
		    	  	if (($va =~ m/^'/) && ($va =~ m/^'/)) {
				    	## begin and end have a single quote. they can be removed
				    	## AND later replaced by double quotes because this output contains nothing that needs single quotes
					    $va =~ s/^'//;
						$va =~ s/'$//;
					};
			      	$v{$name}{$k}=$va;
		  	  	}
	  		  	$now=1 if (m/^$exe/);
          	}
          	close FILE;
          	## small hack for export entries (as in pnfsSetup).
			## when a "export a=b" is passed through this, it will make 2 entries
			## one as "export a"="b" and one as "a"="b" and in that order. 
			## so for now, just remove the second one when we see the first one
			for my $k (keys %{$v{$name}}) {	
		      	if ($k =~ m/^export /) {
					pd("$func: export detected in key $k. trying to fix it...","i","15");
		      		$k =~ s/export //;
		      		delete $v{$name}{$k};
			  	}	
          	}
          	unlink($tmp2) || pd("Can't unlink $tmp2: $!","e",1);
       	} elsif ($mode =~ m/PLAIN_TEXT/) {
       		## just read everything in one string
       		open(FILE,$tmp)|| $self->error("$func: Can't open $tmp: $!");
       		my $now="";
		    while (<FILE>){
		    	$now .= $_;
		    }
		    close FILE;
		    $v{$name}{"PURE_TEXT"}=$now;
       } elsif ($mode =~ m/EQUAL_SPACE/) {  
       			## variables are read like "YY = ZZ"
		      open(FILE,$tmp)|| $self->error("$func: Can't open $tmp: $!");
		      while (<FILE>){
	    		  if (! m/^#/){
		    		  chomp;
				      my @all=split(/ = /,$_);
				  	  my $k = $all[0];
			    	  $k =~ tr/a-z/A-Z/ if $capit;
		    		  my $va = $all[1];
				      $v{$name}{$k}=$va;
				  }
		      }
		      close FILE;
       } elsif ($mode =~ m/MD5_HASH/) {  
       		## variables are read like "YY=ZZ"
		    open(FILE,$tmp)|| $self->error("$func: Can't open $tmp: $!");
		    while (<FILE>){
	    	  if (! m/^#/){
		    	chomp;
				my @all=split(/=/,$_);
				my $k = $all[0];
			    $k =~ tr/a-z/A-Z/ if $capit;
		    	my $va = $all[1];
				$v{$name}{$k}=$va;
			  }
		    }
		    close FILE;
       } else {
       		$self->error("$func: Using mode $mode, but doesn't match.");
       	}	   
  	}
    if ($new_base && $config->elementExists("$new_base")) {
		my $all = $config->getElement("$new_base");
		while ( $all->hasNextElement() ) {
			my $el = $all->getNextElement();
			my $el_name = $el->getName();
			$el_name =~ tr/a-z/A-Z/ if $capit;
			my $el_val;
			my $tmp_el_val=$el->getValue();
			if ($convert_boolean && ($tmp_el_val eq 'true')) {
				$el_val='yes';
			} elsif($convert_boolean && ($tmp_el_val eq 'false')) {
				$el_val='no';
			} else {
				$el_val = $tmp_el_val;
			};
			## overwrite defaults or add new values
			$v{$name}{$el_name}=$el_val;
      	}
	} else {
	  $self->warn("$func: Nothing set for $new_base (2).") if ($new_base);
	}
	pd("$func: Stop with name=$name","i","10");
}


##########################################################################
sub dump_it {
##########################################################################
	my $func = "dump_it";
	pd("$func: function called with arg: @_","i",10);
	my $name = shift;
	my $extra_mode = shift || "DUMMY_WRITE_SET";

	my $file_name=$p{$name}{filename};
	my $mode=$p{$name}{mode}."_".$extra_mode;

	my $changed = 0;
	my $suffix=".back";
	pd("$func: Start with name=$name mode=$mode filename=$file_name","i","10");
		
    my $backup_file = $file_name.$suffix;
    my $backup_file_tmp = $backup_file.$suffix;
	if (-e $file_name) {
	    copy($file_name, $backup_file_tmp) || $self->error("Can't create backup $backup_file_tmp: $!");
	} else {
		pd("Can't create backup $backup_file_tmp: no current version found");
	}
	open(FILE,"> ".$file_name) || $self->error("Can't write to $file_name: $!");
	if ($mode !~ m/NO_COMMENT/) {
	  	print FILE "## Generated by ncm-dcache\n## DO NOT EDIT\n";
	}  	
	## ok, without the sort, you are garanteed to see some strange behaviour.
	foreach my $k (sort keys(%{$v{$name}})) {
		## ok, lets inplement some special values here:
		if ((exists $p{$name}{write_empty}) && ($p{$name}{write_empty} == 0) && ( "X".$v{$name}{$k} eq "X")) {
			## do nothing, print message
			$self->warn("Nothing specified for $name and key $k. Not writing to $file_name.")
		} elsif ($mode =~ m/PLAIN_TEXT/) {	
			print FILE $v{$name}{$k};
		} elsif ($mode =~ m/BASH_SOURCE/)  {
			## if there are spaces in the value, quote the whole line
			## in principle for source it doesn't matter, but in this way individual values can be used as names etc
			if ($v{$name}{$k} =~ m/ |=/) {
				print FILE "$k=\"$v{$name}{$k}\"\n";
			} else {
				print FILE "$k=$v{$name}{$k}\n";	
			}	
		} elsif ($mode =~ m/EQUAL_SPACE/) {
			print FILE "$k = $v{$name}{$k}\n";
		} elsif ($mode =~ m/ALL_POOL/) {
			print FILE "$func:  pool_host:$k\n";
			foreach my $k2 (keys %{$v{$name}{$k}}) {
			print FILE "$func:    pool_name: $k2\n";
				foreach my $k3 (keys %{$v{$name}{$k}{$k2}}) {
					if ($k3 eq "pgroup") {
						foreach my $vall (@{$v{$name}{$k}{$k2}{$k3}}) {
							print FILE "$func:      value $k3:$vall\n";
						}
					} else {
						print FILE "$func:      value $k3:".$v{$name}{$k}{$k2}{$k3}."\n";
					}	
				}
			}
		} elsif ($mode =~ m/MD5_HASH/) {
			## what could possibly go wrong here?
			my $md5=md5_hex($v{$name}{$k});
			print FILE "$k=$md5\n";
		}  else {
       		$self->error("Dump_it: Using mode $mode, but doesn't match.");
       	}	
	}	
    close(FILE);
    ## check for differences
	## if the file doesn't exists, compare will exit with -1, so this also checks existence of file
	if (compare($file_name,$backup_file_tmp) == 0) {
		## they're equal, remove backup
		unlink($backup_file_tmp) || $self->warn("Can't unlink ".$backup_file_tmp) ;
	} else {	
		if (-e $backup_file_tmp) {
			if ($mode =~ m/DUMMY_WRITE_SET/) {
				copy($backup_file_tmp, $file_name)  || $self->error("Can't move $backup_file_tmp to $file_name in mode $mode: $!");
			} else {
				copy($backup_file_tmp, $backup_file) || $self->error("Can't create backup $backup_file: $!");
			}	
		} else {
			if ($mode =~ m/DUMMY_WRITE_SET/) {
				unlink($file_name) || $self->error("Can't unlink $file_name in mode $mode: $!");
			}
		}		
		## flag the change here, action to be taken later
		$changed = 1;
	}

	if ($changed) {
		$p{$name}{changed}=1;
	} else {
		$p{$name}{changed}=0;
	}

	pd("$func: Stop with name=$name changed=$changed","i","10");
	return $changed;
}

##########################################################################
sub pnfs_exports {
##########################################################################
	my $func = "pnfs_exports";
	pd("$func: function called with arg: @_","i","10");
	
	my $new_base = shift;
	
	my $export_dir=$v{node_config}{PNFS_ROOT}."/fs/admin/etc/exports";
	if (! -d $export_dir) {
		pd("$func: $export_dir not found. This is very strange.","e");
	}	
	## should we clean the directory first? i think so
	## move all files to some backup name
	my $backup_prefix="backup-";
	## there's a trusted dir, were only interested in files starting with an ip-address
	open(FILE,"ls $export_dir|grep ^[[:digit:]] |") || $self->error("Can't open ls $export_dir|grep ^[[:digit:]]: $!");
	while (<FILE>) {
		chomp;
		pd("$func: moving file $export_dir/$_","i",15);
		move($export_dir."/".$_,$export_dir."/".$backup_prefix.$_) || $self->error("Can't move ".$export_dir."/".$_." to ".$export_dir."/".$backup_prefix.$_.": $!");
	}	
	close FILE;

	my $n=0;	
	while ($config->elementExists("$new_base/$n")) {
      	my $filename=$config->getValue("$new_base/$n/ip");
      	if ($config->elementExists("$new_base/$n/netmask")) {
      		$filename = $config->getValue("$new_base/$n/netmask")."..".$filename;
      	}
      	pd("$func: New rules for $export_dir/$filename","i",15);
      	open(FILE,"> $export_dir/$filename") ||	$self->error("Can't open $export_dir/$filename: $!");
		my %rule=();
		my $ru=0;
		my $ru_base="$new_base/$n/rule";
		while ($config->elementExists("$ru_base/$ru")) {
			my $all = $config->getElement("$ru_base/$ru");
	      	while ( $all->hasNextElement() ) {
				my $el = $all->getNextElement();
			  	my $el_name = $el->getName();
		  		my $el_val = $el->getValue();
			  	$rule{$el_name}=$el_val;
		  	}
		  	if (! exists $rule{opt}) {
		  		## setting the default value nooptions
		  		$rule{opt}="nooptions";
		  	}
		  	print FILE $rule{mount}." ".$rule{path}." ".$rule{perm}." ".$rule{opt}."\n";
			$ru++;
		}
		close FILE;
      	$n++;
	}	 	
}	

##########################################################################
sub collect_pool_info {
##########################################################################
	my $func = "collect_pool_info";
	pd("$func: function called with arg: @_","i","10");
	
	my $new_base = shift;	
	my $name="all_pool";	
	
	my $all = $config->getElement("$new_base");
	while ( $all->hasNextElement() ) {
		my $pool_host = $all->getNextElement();
		## short_name of pool_host
		my $pool_host_name = $pool_host->getName();
		if ($config->elementExists("$new_base/$pool_host_name/0")) {
			## now we have a list of structure_dcache_pool_pools
			my $n=0;
			while ($config->elementExists("$new_base/$pool_host_name/$n")) {
				my $pool_number=$n+1;
				## this is from the install script.
				my $pool_name=$pool_host_name."_".$pool_number;
				my $all_p = $config->getElement("$new_base/$pool_host_name/$n");
				while ( $all_p->hasNextElement() ) {
					my $el_p = $all_p->getNextElement();
					my $el_p_name = $el_p->getName();
					## $el_p_name eq pgroups is actually a list
					if ($el_p_name eq "pgroup") {
						my @pgr=();
						my $m=0;
						while ( $el_p->hasNextElement() ) {
							my $tmp_pgr = $el_p->getNextElement();
							$pgr[$m] = $tmp_pgr->getValue();
		      				$m++;
		      			}	
						$v{$name}{$pool_host_name}{$pool_name}{$el_p_name}=\@pgr;				      			
					} else {	
	 					my $el_p_val = $el_p->getValue();
						$v{$name}{$pool_host_name}{$pool_name}{$el_p_name}=$el_p_val;
	 				}	
				}
   				$n++;
			}		
		}
   	}
	pd("$func: Current $name config written to ".$p{$name}{filename});
	dump_it($name,"WRITE");
}			

##########################################################################
sub config_pools {
##########################################################################
	my $func = "config_pools";
	pd("$func: function called with arg: @_","i","10");
	
	my $new_base = shift;
	my $shortname = shift;
	
	my $name="pools";
	
	my ($path,$size,$opt,$max);

	my $max_prom=$p{all_pool}{max_true_pool_size_prom};
	my $default_pool_opt="no";
	my $pool_path_text="";
	## must be sorted for the order !!!!!!!!!!!! (do the sorting myself)
	my $n=1;
	while (exists($v{all_pool}{$shortname}{$shortname."_$n"})) {
		my $pool_name=$shortname."_$n";

		## ulimit -n config
		if (exists($v{all_pool}{$shortname}{$pool_name}{"ulimit_n"})) {
			$p{all_pools}{ulimit_n}=$v{all_pool}{$shortname}{$pool_name}{"ulimit_n"};
		}	

	  	$path=$v{all_pool}{$shortname}{$pool_name}{"path"};
	  	## check if path exists.
	  	if (! -d $path) {
		  	pd("$func: Pool path $path doesn't exist. Creating...");
		  	pd("$func: Can't create $path.","e","1") if (sys2("mkdir -p $path"));
	  	}
	  	if (-d $path) {
		  	## get maximum available space	
		  	my $out;
		  	open(TMP,"df -BM $path|") || pd("$func: Something's wrong with df -BM $path : $!","e","1");
			while (<TMP>) {
			    $out.=$_;
			}
			close(TMP);
			## this is needed to be able to parse nfs-mounts
			$out =~ s/\n\s+/ /;

			my @all_t=split("\n",$out);
			foreach (@all_t) {
				## parsing for either device: '/dev' or NFS: '(FQDN/ipaddress):/'
    			if (m/^(\/dev|(\w|\.)+:\/)/) {
					s/\s+/ /g;
			        my @tmp_t=split(" ",$_);
			        $max=$tmp_t[3];
		   		  	## in SL4, df -BM prints an M after the value...
					$max =~ s/M$//;
    			}
			}
		  	## i'll do the rounding, thank you
		  	$max=int($max/1024);

		  	## see if there's alreday a pool_path file with that path
		  	## to be checked if size of pool is not defined
		  	## because the size is dynamically set, use this as an extra check
		  	my (@existing,$len);
		  	my $existing_size=0;
		  	my $existing_opt="THIS_IS_NOT_A_VALID_OPTION";
		  	if (-f $p{$name}{filename}) {
			  	open(TMP,"cat ".$p{$name}{filename}."|grep \"^$path\[\[:space:\]\]\"|") || pd("$func: Can't open ".$p{$name}{filename}." to parse existing values: $!","e","1");
			  	while(<TMP>) {
			    	chomp;
		    		@existing = split(/\s+/);
		    		$len=@existing;
					if ($len == 3) {
						$existing_size=$existing[1];
					}	 
		  		}
		  		close TMP;
		  	}

		  	if (exists $v{all_pool}{$shortname}{$pool_name}{"size"}) {
	  			## check for maximum space
	  			if ($v{all_pool}{$shortname}{$pool_name}{"size"} > $max) {
	  				pd("$func: Configured pool size for $path ".$v{all_pool}{$shortname}{$pool_name}{"size"}." > maximum available $max. Setting it to $max_prom / 1000 of maximum: ".int($max*$max_prom/1000),"w");
					$size=int($max*$max_prom/1000);
		  		} else {
		  			$size=$v{all_pool}{$shortname}{$pool_name}{"size"};
		  		}	
		  	} elsif (! $existing_size == 0) {
		  		## so there's no size defined, but there's one set in a previous file
		  		## there's a very good chance that this is a rerun. Keeping original value.
		  	    $size=$existing_size;
		  	} else {	
		  		pd("$func: No configured pool size for $path. Setting it to $max_prom / 1000 of maximum $max: ".int($max*$max_prom/1000));
		  		$size=int($max*$max_prom/1000);
	  	  	}
	      	if (exists $v{all_pool}{$shortname}{$pool_name}{"opt"}) {
	  			$opt=$v{all_pool}{$shortname}{$pool_name}{"opt"};
	      	} elsif (! $existing_opt eq "THIS_IS_NOT_A_VALID_OPTION") {
	      		$opt=$existing_opt;
	      	} else {
	      		$opt=$default_pool_opt;
	      	}
	      	## writing the values
       		$pool_path_text .= "$path $size $opt\n";	
	    }	
	    $n++;
	}
		  
	$v{$name}{"PURE_TEXT"}=$pool_path_text;
}	

##########################################################################
sub make_config_begin {
##########################################################################
    my $func = "make_config_begin";
    pd("$func: function called with arg: @_","i","10");
    my $txt="";
    
    $txt.="[SSH]\n";
    $txt.="user = ".$p{admin}{user}."\n";
    $txt.="host = ".$p{admin}{host}."\n";
    $txt.="port = ".$p{admin}{port}."\n";
    $txt.="key = ".$p{admin}{key}."\n";
    
    return $txt;
}

##########################################################################
sub make_config_pool {
##########################################################################
    my $func = "make_config_pool";
    pd("$func: function called with arg: @_","i","10");

    my $txt="";
    ## pools
    my $name="all_pool";
    $txt.="[POOL]\n";
    ## default settings
    $txt.="dconf_defaults = is_default mover_max=".$p{$name}{default_mover_max}."\n"; 
    foreach my $host (keys %{$v{$name}}) {
	foreach my $pool_name (keys %{$v{$name}{$host}}) {
	    $txt .= "$pool_name = ";
	    if (exists($v{$name}{$host}{$pool_name}{mover_max})) {
		$txt.= "max_movers=".$v{$name}{$host}{$pool_name}{mover_max}." ";
	    } 
	    if (exists($v{$name}{$host}{$pool_name}{pgroup})) {
		$txt .= "pgroups=";
		foreach my $grp (@{$v{$name}{$host}{$pool_name}{pgroup}}) {
		    $txt .= $grp.",";
		}
		$txt =~ s/,$//;
		$txt .= " ";
	    }
	    $txt.="\n";
	}
    }
    ## poolgroups
    $name="all_pool";
    $txt.="[POOLGROUP]\n";
    ## default settings
    #$txt.="dconf_defaults = "."\n"; 
    ## set the ignored pgroups
    foreach (@{$p{$name}{ignore_pgroup}}) {
	$txt .= $_." = ignore\n";
    }

    return $txt;
}

##########################################################################
sub make_config_unit {
##########################################################################
    my $func = "make_config_unit";
    pd("$func: function called with arg: @_","i","10");

    my $tmp_base = shift;
    my $txt="";
    $txt.="[UNIT]\n";
    
    my $new_base="$tmp_base/units";
    my $all = $config->getElement("$new_base");
    my $n=0;
    while ( $all->hasNextElement() ) {
	my $un = $all->getNextElement();
	## type of unit (net,store or dcache)
	my $utype = $un->getName();
	## now list of nlists of conditions and ugroups
	if ($config->elementExists("$new_base/$utype/0")) {
	    ## now we have a nlist of conditions and ugroups
	    $n=0;
	    while ($config->elementExists("$new_base/$utype/$n")) {
		my $ucond = $config->getValue("$new_base/$utype/$n/cond");
		my $tmp ="$ucond = type=$utype ";
		my $el_u = $config->getElement("$new_base/$utype/$n/ugroup");
		$tmp .= "ugroups=";
		while ( $el_u->hasNextElement() ) {
		    my $tmp_ugr = $el_u->getNextElement();
		    my $ugr = $tmp_ugr->getValue();
		    $tmp.=$ugr.",";
		    
		}
		$tmp=~s/,$//;
		$tmp.=" ";
		$txt.=$tmp."\n";
		$n++;
	    }
	}
    }

    ## ignores
    $new_base="$tmp_base/ignore_ugroup";
    $n=0;
    if ($config->elementExists("$new_base/$n")) {
	$txt .= "[UNITGROUP]\n";
	while ($config->elementExists("$new_base/$n")) {
	    $txt .= $config->getValue("$new_base/$n")." = ignore\n";
	    $n++;
	}
    }

    return $txt;
}

##########################################################################
sub make_config_link {
##########################################################################
    my $func = "make_config_link";
    pd("$func: function called with arg: @_","i","10");

	my $notfound="NNOOTTFFOOUUNNDD";

    my $txt="";
    $txt.="[LINK]\n";
    
    my $tmp_base=shift;
    my $new_base;

    my %ignore_link=();
    my $n=0;
    ## a list with links that will not be configured with ncm-dcache (and also not deleted)
    $new_base="$tmp_base/ignore_link";
    if ($config->elementExists("$new_base/$n")) {
		while ($config->elementExists("$new_base/$n")) {
	    	$ignore_link{$config->getValue("$new_base/$n")}=1;
	    	$n++;
		}
    }

    ## default preferences
	$txt.= "dconf_defaults = is_default ";
	## prefs
	my @prefs=("read","write","cache","p2p");
	## defaults
	my %pref_defs={"read","10","write","10","cache","10","p2p","-1"};
	foreach my $pref (@prefs) {
   		$txt.="$pref=".fetch("$new_base/def_preference/$pref",fetch("$new_base/def_preference/default",$pref_defs{$pref}))." ";
	}
	$txt.="\n";

    $new_base="$tmp_base/links";
    my $all = $config->getElement("$new_base");
    while ( $all->hasNextElement() ) {
		my $li = $all->getNextElement();
		## name of link
		my $link = $li->getName();
		my $tmp = "$link = ";
	
		$tmp .= "ignore " if (exists($ignore_link{$link}));

		## now we have a list of ugroups
		$n=0;
		my $tmp2="";
		$tmp2="ugroups=";
		while ($config->elementExists("$new_base/$link/ugroup/$n")) {
	    	$tmp2 .= $config->getValue("$new_base/$link/ugroup/$n").",";
	    	$n++;
		}
		$tmp2=~s/,$//;
		$tmp2.=" ";
		$tmp.=$tmp2;
		## now a list of pgroups or pools
		$tmp2="pgroups=";
		$n=0;
		while ($config->elementExists("$new_base/$link/pgroup/$n")) {
	    	$tmp2 .= $config->getValue("$new_base/$link/pgroup/$n").",";
	    	$n++;
		}
		$tmp2=~s/,$//;
		$tmp2.=" ";
		$tmp.=$tmp2;
	
		## now the linkgroup
		## can only be one
		$tmp2="lgroup=";
		if ($config->elementExists("$new_base/$link/lgroup")) {
	    	$tmp2 .= $config->getValue("$new_base/$link/lgroup");
		}
		$tmp.="$tmp2 ";

		## prefs
		foreach my $pref (@prefs) {
			my $tmp3=fetch("$new_base/$link/$pref",$notfound);
   			$tmp.="$pref=$tmp3 " if ($tmp3 ne $notfound);
		}	

		$txt .= $tmp."\n";
    }

    $txt.="[LINKGROUP]\n";
    my %ignore_linkgroup=();
    $n=0;
    ## a list with linkgroups that will not be configured with ncm-dcache (and also not deleted)
    $new_base="$tmp_base/ignore_linkgroup";
    if ($config->elementExists("$new_base/$n")) {
		while ($config->elementExists("$new_base/$n")) {
		    $ignore_linkgroup{$config->getValue("$new_base/$n")}=1;
	    	$n++;
		}
    }

    ## default policies
    $txt.="dconf_defaults = is_default";
    $new_base="$tmp_base/def_policies";
    
    my @policies=("nearline","online","custodial","output","replica");
    ## default policies.
    my %def_pols={"nearline","true","online","false","custodial","true","output","true","replica","true"};
    
	foreach my $pol (@policies) {
   		$txt.="$pol=".fetch("$new_base/$pol",fetch("$new_base/default",$def_pols{$pol}))." ";
	}
    $txt.="\n";

	## linkgroups 
    $new_base="$tmp_base/linkgroups";
    $all = $config->getElement("$new_base");
    while ( $all->hasNextElement() ) {
		my $li = $all->getNextElement();
		## name of linkgroup
		my $linkg = $li->getName();
		my $tmp = "$linkg = ";
	
		$tmp .= "ignore " if (exists($ignore_linkgroup{$linkg}));

		## now a list of links
		my $tmp2="links=";
		$n=0;
		while ($config->elementExists("$new_base/$linkg/links/$n")) {
	    	$tmp2 .= $config->getValue("$new_base/$linkg/links/$n").",";
	    	$n++;
		}
		$tmp2=~s/,$//;
		$tmp2.=" ";
		$tmp.=$tmp2;

		## policies
		foreach my $pol (@policies) {
			$tmp2 = fetch("$new_base/$linkg/$pol",$notfound);
	   		$tmp.= " $pol=$tmp2" if ($tmp2 ne $notfound);
		}
		$txt .= $tmp."\n";
		
	}    
    
    
    return $txt;
}

##########################################################################
sub make_config_dcachesetup {
##########################################################################
    my $func = "make_config_dcachesetup";
    pd("$func: function called with arg: @_","i","10");

    my $txt="";
    $txt.="[DCACHESETUP]\n";
    ## special things for ncm-dcache and dConf
    $txt.="dcachesetup_report=True\n";
    $txt.="dcachesetup_dump_style=perl\n";
    
    my $name = shift;
    my $new_base = shift;
    my $def_dir = shift;
    my $dummy_flag = shift || "yes";
	my ($tmp,$tmp2);
	
	$txt.="dcachesetup_write=".$p{$name}{filename}."\n";
	
	## read all default files to be parsed BEFORE reading configured values
	$tmp2='dcachesetup_read = ';
	my $n=0;
    while ($config->elementExists($new_base."_def/".$n)) {
	  $tmp = $config->getValue($new_base."_def/".$n);
      ## if $tmp doesn't start with /, add $def_dir
      if ($tmp !~ m/^\//) {
        $tmp = "$def_dir/$tmp";
      }
      $tmp2 .="$tmp,";
      $n++;
    }
	$txt.="$tmp2\n";
    
	## in this run, values can be overwritten again by what's defined in the files. this is why the following needs to be run everytime
    if ($config->elementExists("$new_base")) {
		my $all = $config->getElement("$new_base");
		while ( $all->hasNextElement() ) {
			my $el = $all->getNextElement();
			
			$txt.=$el->getName().'='.$el->getValue()."\n";
  		}
	} else {
  		pd("$func: Nothing set for $new_base.",'w') if ($new_base);
	};
    
    ## inject ourHome/ourHomeDir
	$txt.="ourHome=$homeDir_default\n";
	$txt.="ourHomeDir=$homeDir_default\n";
    
    
	my ($exitcode,$output)=run_dconf("NODCACHESETUP -dcachesetup -dummy $dummy_flag",$txt,1);

	my $changed = 0;
	if ($dummy_flag eq "no") {
		return $changed
	} else {
	
		## grep from $output
		## PARSETHIS FILEHASCHANGED
		## PARSETHIS DUMPERLSTYLE
		if ($output =~ m/PARSETHIS FILEHASCHANGED/) {
			pd("$func: PARSETHIS FILEHASCHANGED found","i","5");
			$changed = 1;
		};

		if ($changed) {
			$p{$name}{changed}=1;
		} else {
			$p{$name}{changed}=0;
		}

		my %dcs=();
		my $dumper_found=0;
		
		if ($output =~ m/PARSETHIS DUMPERLSTYLE\s+(.*)\n/) {
			eval('%dcs='.$1.';');
			
			my $dumper_found=1;
			pd("$func: PARSETHIS DUMPERSTYLE found ($1)","i","5");
			## parse all variables for \$ substitution (if exists)
			
			my $rep_dollar="XXDOLLARXX";
			my %new_dcs=();

			foreach my $k (keys %dcs) {
    			my $val=$dcs{$k};	
			    while ($val =~ m/(\$\{?(\w+)\}?)/) {
					my $val_found=$1;
					my $val_name=$2;
					my $rep;
					if (exists($new_dcs{$val_name})) {
	    				$rep =  $new_dcs{$val_name};
	    				$rep =~ s/\$/\$/g;
					} elsif (exists($dcs{$val_name})) {
	    				$rep =  $dcs{$val_name};
	    				$rep =~ s/\$/\$/g;
					} else {
	    				## in case it doesn't exist, do something useful
	    				pd("$func: can't find a definition for $val_found.","i","5");
					    $rep=$val_found;
	    				$rep=~s/\$/$rep_dollar/;
					}
		
					## first character should be a $
					$val_found =~ s/\$/\\\$/;
					$val =~ s/$val_found/$rep/g;
					$new_dcs{$k}=$val;
    			}
    			$val =~ s/$rep_dollar/\$/;
			    $new_dcs{$k}=$val;
			}
			my $txt='';
			foreach (keys(%new_dcs)) {
				$txt.="{$_ ".$new_dcs{$_}."} ";
				$v{$name}{$_}=$new_dcs{$_};
			};
			pd("$func: NEW dcs $txt","i","10");
		
		}
		
		return $changed
	}
	

}

##########################################################################
sub make_config_batch {
##########################################################################
    my $func = "make_config_batch";
    pd("$func: function called with arg: @_","i","10");

    my $txt="";
    $txt.="[BATCH]\n";
    
    my $tmp_base=shift;
    my $new_base;

	## the directory to find the bacth files to read in    
    $new_base="$tmp_base/batch_read";
   	$txt.="batch_read = ".fetch($new_base,$v{node_config}{DCACHE_BASE_DIR}."/config")."\n";

	## the directory to find the bacth files to write out    
    $new_base="$tmp_base/batch_write";
   	$txt.="batch_write = ".fetch($new_base,$v{node_config}{DCACHE_BASE_DIR}."/config")."\n";

	## do the batch files to read have .template forms?
    $new_base="$tmp_base/batch_template";
 	$txt.="batch_template = ".fetch($new_base,"False")."\n";

	## the create blocks to configure
	my $n=0;
	my $tmp2;
	my $all;
	while ($config->elementExists("$tmp_base/create/$n")) {
		$new_base="$tmp_base/create/$n";
		my $name=fetch("$new_base/name");
		my $cell=fetch("$new_base/cell");
		my $batchname=fetch("$new_base/batchname");
		$tmp2="create_$n = batch=$batchname cell=$cell name=$name";
				
		
		if ($config->elementExists("$new_base/context")) {
			$all = $config->getElement("$new_base/context");
			while ( $all->hasNextElement() ) {
				my $context = $all->getNextElement();
				my $context_name = $context->getName();
	    		my $context_value = $context->getValue();
	    		$tmp2.=" context=$context_name,$context_value";
	    	}
	    }

		if ($config->elementExists("$new_base/opt")) {
			$all = $config->getElement("$new_base/opt");
			while ( $all->hasNextElement() ) {
				my $opt = $all->getNextElement();
				my $opt_name = $opt->getName();
	    		my $opt_value = $opt->getValue();
	    		$tmp2.=" opt=$opt_name,$opt_value";
	    	}
	    }
		
		$txt.="$tmp2\n";
	    $n++;
	};
	
	## run it
	run_dconf("NODCACHESETUP -batch -dummy no",$txt);

}    
    


##########################################################################
sub run_dconf {
##########################################################################
    my $func = "run_dconf";
	pd("$func: function called with arg: @_","i","10");
    
    my $real_exec;
	my ($exitcode,$output);
    my $dconf_base_dir=$v{node_config}{DCACHE_BASE_DIR}."/dConf";
	my $dConf_script=$dconf_base_dir."/dConf";

	## 
	my $opt = shift;	
	my $txt = shift;
	my $out_back = shift || 0;
	my $def_filename="ncm-dcache-run.cfg.".`date +%Y%m%d-%H%M%S`;
	chomp($def_filename);
	system("mkdir -p ".$dconf_base_dir."/backup/");
	
	my $dConf_cfg = shift || $dconf_base_dir."/backup/".$def_filename;
	
	open(FILE,"> ".$dConf_cfg) || $self->error("Can't write to $dConf_cfg: $!");
	print FILE $txt;		
	close FILE;
	$real_exec = "$dConf_script $opt -cfg $dConf_cfg -debug 10";
	($exitcode,$output) = sys2($real_exec,"false","true");
	
	if ($out_back) {
		return ($exitcode,$output);	
	} else {
		return $exitcode;
	};
	    
}

##########################################################################
sub make_conf {
##########################################################################
    my $func = "make_conf";
    pd("$func: function called with arg: @_","i","10");
    
    ## get all config info, dump it in a file
    my $txt="";
    my $base=shift;
    
    $txt .= make_config_begin();
    $txt .= make_config_pool();
    $txt .= make_config_unit("$base/unit") if ($config->elementExists("$base/unit"));
    $txt .= make_config_link("$base/link") if ($config->elementExists("$base/link"));
    
    pd("$func: dump file: $txt",'i','10');
    
    ## run the dconf setup	
    return run_dconf('-commit -dummy no',$txt);
}


##########################################################################
sub setup_jython {
##########################################################################
    my $func = "setup_jython";
    pd("$func: function called with arg: @_","i","10");
    
    my $real_exec;
	my ($exitcode,$output);
    my $dconf_base_dir=$v{node_config}{DCACHE_BASE_DIR}."/dConf";
	my $jython_setup_script=$dconf_base_dir."/setup-jython-dConf.sh";
	my $dConf_script=$dconf_base_dir."/dConf";
	## run the script. it will protect itself against reinstallation
	my $jythonjavahome="";
	my $path="/software/components/dcache/config/jythonjavahome";
	if ($config->elementExists($path)) {
	    $jythonjavahome=$config->getValue($path);
    }
	$real_exec = "cd $dconf_base_dir && $jython_setup_script $jythonjavahome";
	($exitcode,$output) = sys2($real_exec,"false","true");
	
	
	## remove all class files
	$real_exec = "cd $dconf_base_dir && rm -f *class";
	($exitcode,$output) = sys2($real_exec,"false","true");

	## check if the javaversion in jython is ok
	$real_exec = "cd $dconf_base_dir && ./jython/jython --version";
	($exitcode,$output) = sys2($real_exec,"false","true");
	if ($exitcode) {
		## ok, something went wrong. lets retry the installation
		pd("$func: jython --version returns $output.","i","1");
		pd("$func: the jython setup seems not functional (new jdk?). Wiping out previous setup and retrying the install.","i","1");

		## wipe out old install.
		$real_exec = "cd $dconf_base_dir && rm -Rf jython";
		($exitcode,$output) = sys2($real_exec,"false","true");
		
		## rerun the installer
		$real_exec = "cd $dconf_base_dir && $jython_setup_script $jythonjavahome";
		($exitcode,$output) = sys2($real_exec,"false","true");
		
		## recheck the version
		$real_exec = "cd $dconf_base_dir && ./jython/jython --version";
		($exitcode,$output) = sys2($real_exec,"false","true");
		if ($exitcode) {
			pd("$func: jython --version returns $output after fresh reinstall. Exiting...","e","1");
			return 0;
		} else {
		 	return 1;
		};
	} else {
		return 1;
	}
}	


##########################################################################
sub test_dconf {
##########################################################################
    my $func = "test_dconf";
    pd("$func: function called with arg: @_","i","10");
    
	if (! setup_jython()) {
		return 0;
	};
	
	my $dconf_base_dir=$v{node_config}{DCACHE_BASE_DIR}."/dConf";
	## test the dconf setup	
	my $dConf_test_cfg=$dconf_base_dir."/ncm-dcache-test.cfg";
	my $txt="## dConf test.cfg generated by ncm-dcache\n";
    $txt .= make_config_begin();
    
    return run_dconf('-test',$txt,0,$dConf_test_cfg);
    
}        


##########################################################################
sub setup_dconf_no_admin {
##########################################################################
    my $func = "setup_dconf_no_admin";
    pd("$func: function called with arg: @_","i","10");
    
	if (! setup_jython()) {
		return 0;
	} else {
		return 1;
	};
		
}

##########################################################################
sub give_advice {
##########################################################################
    my $func = "give_advice";
    pd("$func: function called with arg: @_","i","10");
    
	pd("$func:","i","1");
	pd("$func: When you have changed the java version for dcache, make sure that the jython config is not affected. The java path is hardcoded in ".$v{node_config}{DCACHE_BASE_DIR}."/dConf/jython/jython.","i","1");
	pd("$func: When you upgrade the rpms from dcache, make sure that the dcache.kpwd is valid again. Try running ".$v{node_config}{DCACHE_BASE_DIR}."/bin/grid-mapfile2dcache-kpwd (if such a command exists).","i","1");
	pd("$func: When you have security issues with SRM/gPlazma, check the gPlazma settings and the restart both gPlazma and SRM.","i","1");
	pd("$func:","i","1");
	pd("$func:","i","1");
	pd("$func:","i","1");
		
}

##########################################################################
sub chimera_check {
##########################################################################
    my $func = "chimera_check";
    pd("$func: function called with arg: @_","i","10");
    
    my $real_exec;
    
    ## is pnfs mounted, and by whom
    my $magicfile=$v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID}."/\'.(const)(D)\'";
    $real_exec="ls $magicfile";
    if (sys2($real_exec)) {
        ## /pnfs not mounted or not existing
        if ( ! -d  $v{node_config}{PNFS_ROOT} ) {
            $real_exec="mkdir ".$v{node_config}{PNFS_ROOT};
            if (sys2($real_exec)) {
                pd("$func: Can't create /pnfs: $real_exec: $!","e");
                return 1;
            }    
        }
    } else {
        $real_exec="cat $magicfile | grep -i chimera";
        if (sys2($real_exec)) {
            ## mounted by pnfs
            pd("$func: /pnfs mounted by pnfs");
            $real_exec="umount ".$v{node_config}{PNFS_ROOT};
            if (sys2($real_exec)) {
                pd("$func: Can't umount /pnfs, but mounted by pnfs: $real_exec: $!","e");
                return 1;
            }    
        } else {
            pd("$func: /pnfs mounted by chimera");
        }
    }
    ## stop pnfs, umount /pnfs
    if (check_status("pnfs")) {
        stop_service("dcache","pnfs");
    }
    if (! stop_service("pnfs")) {
        pd("$func: Can't stop pnfs. Exiting");
        return 1;
    };
    
    ## stop portmap
    if (! stop_service("portmap")) {
        pd("$func: Can't stop portmap. Exiting");
        return 1;
    };
    
    return 0;
}

##########################################################################
sub chimera_setup {
##########################################################################
    my $func = "chimera_setup";
    pd("$func: function called with arg: @_","i","10");
    
    my ($path,$real_exec,$all,$context);
    ## restart variable
    my $rest = shift || 0;
    ## make export file
    my $backup_prefix="old";
    ## we do't expect ay other /etc/exports file
    my $exports="/etc/exports";
    if ( -e "$exports" ) {
        move("$exports","$exports.$backup_prefix") || $self->error("Can't move $exports to $exports.$backup_prefix : $!");
    }
    $path="/software/components/dcache/chimera/exports";
    my $txt="##\n## Written by ncm-dcache\n## Should only contain chimera paths\n##\n\n";
    if ($config->elementExists($path)) {
        $all = $config->getElement($path);
        while ( $all->hasNextElement() ) {
            $context = $all->getNextElement();
            my $value = $context->getValue();
            $txt.="$value\n";
        }
    }
    open(FILE,"> ".$exports) || $self->error("Can't write to $exports: $!");
    print FILE $txt; 
    close FILE;
    
    if (compare("$exports","$exports.$backup_prefix") == 0) {
        ## nothing to do?
    } else {
        $rest=1;
    }
   
    ## pnfs mounted by whom?
    if (chimera_check()) {
        return 1;
    }  
    ## start chimera-nfs
    if (! start_service(0,"chimera-nfs")) {
        pd("$func: starting chimera-nfs failed. Exiting.");
        return 1;
    };
    
    ## restart chimera-nfs is /etc/exports has changed
    ## also when java version in dcacheSetup changes
    if ($rest) {
        stop_service("chimera-nfs");
        start_service(0,"chimera-nfs");
        
        return 1 if (! abs_start_service("chimera-nfs","$func: going to start chimera-nfs"));
    }
    
    
    ## forsee an admin mount point
    my $pnfs=$v{node_config}{PNFS_ROOT}."/".$v{node_config}{SERVER_ID};
    my $mntpnfs="/mntpnfs";
    ## does the tmp directory exists?
    if (! -e "$mntpnfs" ) {
        pd("$func: Can't find $mntpnfs. Creating it...");
        $real_exec="mkdir -p $mntpnfs";
        if (sys2($real_exec)) {
            pd("$func: Can't run $real_exec: $!");
            return 1;
        }
    } 
    
    ## mount / on /mntpnfs
    
    my $umountopt="";
    if ( -f "/sbin/umount.nfs") {
      $umountopt="-i";
    };
    $real_exec="umount $umountopt $mntpnfs";
    if (sys2($real_exec)) {
            pd("$func: (Harmless if not mounted) Can't run $real_exec: $!");
    }
    
    $real_exec="sleep 15 && mount localhost:/ $mntpnfs";
    if (sys2($real_exec)) {
            pd("$func: Can't run $real_exec: $!");
            return 1;
    }
    ## make domain path
    ## make directory tags on /mnt/pnfs/ or on /pnfs (if already mounted with chimera)
    my $chim_cli="/opt/d-cache/libexec/chimera/chimera-cli.sh";
    my $makedir="$chim_cli Mkdir";
    
    if (! -e "$mntpnfs/$pnfs" ) {
        pd("$func: Can't find $mntpnfs$pnfs. Creating it...");
        $real_exec="$makedir ".$v{node_config}{PNFS_ROOT};
        if (sys2($real_exec)) {
            pd("$func: Can't run $real_exec: $!");
            return 1;
        }
        $real_exec="$makedir $pnfs";
        if (sys2($real_exec)) {
            pd("$func: Can't run $real_exec: $!");
            return 1;
        }
    }
    
    $path="/software/components/dcache/chimera/paths";
    if ($config->elementExists($path)) {
        $all = $config->getElement($path);
        while ( $all->hasNextElement() ) {
            $context = $all->getNextElement();
            my $value = $context->getValue();
            if (! -d "$mntpnfs$pnfs/$value") {
                $real_exec="$makedir $pnfs/$value && sleep 5";
                pd("$func: Can't create directory $pnfs/$value: cmd used: $real_exec: $!") if (sys2($real_exec));

                ## set the tags
                ## ls is needed to triger the fs properly
                $real_exec="ls -l $mntpnfs$pnfs/ && cd $mntpnfs$pnfs/$value && echo \'StoreName sql\' > \'.(tag)(OSMTemplate)\' && echo \'chimera\' > \'.(tag)(sGroup)\'";
                if (sys2($real_exec)) {
                    pd("$func: Can't run $real_exec","e","1");
                    return 1;
                }

            }
        }
    }
    
    ## setup default dcap door
    $path="/software/components/dcache/chimera/default_dcap";
    if ($config->elementExists($path)) {
        my $default_dcap=$config->getValue($path);
        my $default_dcap_port = "22125";
        if ($config->elementExists($path."_port")) {
            $default_dcap_port=$config->getValue($path."_port");
        }
        ## assign default dcap door when using "dccp /pnfs/kkk/lll/mmm ."
        if (! -d "$mntpnfs/admin/etc/config/dCache" ) {
            $real_exec="mkdir $mntpnfs/admin/etc/config/dCache";
            pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
        }
        $real_exec="touch $mntpnfs/admin/etc/config/dCache/dcache.conf";
        pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
        $real_exec="touch $mntpnfs/admin/etc/config/dCache/\'.(fset)(dcache.conf)(io)(on)\'";
        pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
        $real_exec="echo \'$default_dcap:$default_dcap_port\' > $mntpnfs/admin/etc/config/dCache/dcache.conf";    
        pd("$func: Can't run $real_exec","e","1") if (sys2($real_exec));
    };
    
    ## umount /mntpnfs
    $real_exec="umount $umountopt $mntpnfs";
    if (sys2($real_exec)) {
            pd("$func: Can't run $real_exec: $!","e");
            return 1;
    }
    
    ## check if /pnfs is mounted
    ## should be in /etc/fstab
    $real_exec="mount ".$v{node_config}{PNFS_ROOT};
    if (sys2($real_exec)) {
        pd("$func: Can't run $real_exec: $! (either real problem (eg missing from /etc/fstab or chimera stuck) or already mounted");
    }    
    $real_exec="mount | grep ".$v{node_config}{PNFS_ROOT};
    if (sys2($real_exec)) {
        ## mount failed
        pd("$func: can't mount /pnfs","e");
        return 1;
    } else {
        pd("$func: ".$v{node_config}{PNFS_ROOT}." mounted.");
    }    
    return 0;
}



### real end of configure
  return 1;
}

