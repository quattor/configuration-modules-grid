# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
#######################################################################
#
# NCM component for yaim
#
#
# ** Generated file : do not edit **
#
#######################################################################

package NCM::Component::yaim;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;


use LC::File qw(file_contents);
use LC::Process;

use File::Basename;

#
# run a given command and recover stdout and stderr.
#
sub run_command($) {
  my ($self,$command)=@_;

  my $error=0;
  if ($NoAction) {
    $self->info('(noaction mode) would run command: '.$command);
    return 0;
  } else {
    $self->info('running command: '.$command);
    my ($stdout,$stderr);
    my $execute_status = LC::Process::execute([$command],
                                              timeout => 90*60,
                                              stdout => \$stdout,
                                              stderr => \$stderr
                                             );
    my $ret=$?;
    unless (defined $execute_status) {
      $self->error("could not execute '$command'");
      return 1;
    }

    if ($stdout) {
      $self->info("'$command' STDOUT output produced:");
      $self->report($stdout);
    }
    if ($stderr) {
      $self->warn("'$command' STDERR output produced:");
      $self->report($stderr);
    }
    if ($ret) {
      $self->error("'$command' failed with non-zero exit status: $ret");
      $error=1;
    } else {
      $self->info("'$command' run succesfully");
    }
    return $error;
  }
}

#
# check if a configuration file already exists and if its contents have changed
# if the there are changes, make a backup of the file and write the new contents
#
# parameters:   
#   cfgfilename: name of the configuration file
#   cfgcontents: contents of the configuration file
#
# return:
#   0   no changes
#   1   are changes
#   -1  error
#
sub write_cfg_file($$$) {
  my ($self, $cfgfilename, $cfgfile) = @_;

  my $update = 1;
  if (-e $cfgfilename) {
    # compare the contents with the old config file
    my $oldcfg=LC::File::file_contents($cfgfilename);
    if ($oldcfg ne $cfgfile) {
      unless (LC::File::copy($cfgfilename,$cfgfilename.'.old')) {
        $self->error("copying $cfgfilename to $cfgfilename.old:".
                     $EC->error->text);
        return(-1);
      }
      $update = 1;
    }
    else {
      $update = 0;
    }
  }
  if ($update) {
    # write contents to file
    unless (LC::File::file_contents($cfgfilename,$cfgfile)) {
      $self->error("writing new configuration to $cfgfilename:".
                   $EC->error->text);
      return(-1);
    }
    $self->info ("updated $cfgfilename");
  }
  return($update);
}

#
# Take a VO, and convert it into a form suitable for a environment variable.
# We assume it's a DNS Name, so convert '.' and '-' appropriately
sub vo_for_env($) {
  my $vo = shift @_;
  $vo =~ tr/[a-z].-/[A-Z]__/;
  return $vo;
}




#
# getQueueConfig:   Configure the Yaim variables that are related to queues,
#                   such as QUEUES and <QUEUE>_GROUP_ENABLE.
#                   The information that is the source for the values of these
#                   variables is scattered over the schema. This function
#                   collects that information and returns a string that represents
#                   a separate section in the eventual output file.
#
# parameters:       1. Reference to self
#                   2. Reference to the configuration root
#                   2. Base path
#                   3. Base path for the VO information
#
# return:           Text that contains the Yaim variable definitions related to
#                   the queue configuration.
#
sub getQueueConfig {
    my ($self, $config, $base, $vobase) = @_;

    # Gather the input for the variable QUEUES.
    # The input can be found in various sources:
    # 1. conf/QUEUES
    #    Optionally specifies which queues are defined. 
    #    May be used in combination with directly setting <Q>_GROUP_ENABLE,
    #    for example via the free configuration part.
    # 2. <vobase>/<vo>/services/QUEUES
    #    Optionally defines which queues can be used by a certain VO
    # 3. <vobase>/<vo>/services/groupsroles
    #    May add to 2. which VOMS roles and groups are defined for the VO
    #
    # Approach: build an internal table, index by queue name,
    # containing all VOs and VOMS roles/groups that are allow to use this queue
    my %queues;           # hash with key=queue-name and value=list of supported VOs and roles/groups

    # Gather input from conf/QUEUES
    my $qbase = "$base/conf/QUEUES";
    if ($config->elementExists($qbase)) {
        my $val=$config->getValue($qbase);
       
        foreach my $queue ( split(/\s+/, $val) ) {
            if ( ! defined $queues{$queue} ) {
                $queues{$queue} = "";
            }
        }
    }

    # Collect input from VO-specific settings
    # Although the queues are in the (unspecified) schema of this component 
    # connected to a VO, they are no longer part of the VO config in Yaim.
    if ($config->elementExists($vobase)) {
        my %hash = $config->getElement($vobase)->getHash();
        foreach my $key (sort keys %hash) {
            if($config->elementExists("$vobase/$key/services/QUEUES")){
                my $list = $config->getValue("$vobase/$key/services/QUEUES");
                my $vo = $config->getValue("$vobase/$key/name");

                $self->verbose("list of queues for VO $vo = $list\n");

                my @vals = split('\s',$list);
                foreach my $val (@vals){
                    $queues{$val} .= "$vo ";        # add VO name to the queue
                  
                    # If defined, the specific VOMS groups and roles
                    if($config->elementExists("$vobase/$key/services/groupsroles")){
                        my $groupsroles = $config->getValue("$vobase/$key/services/groupsroles");
                        chomp $groupsroles;
                        $queues{$val} .= "$groupsroles ";
                    }
                }
            }
        }
    }

    # Construct the output for the variables QUEUES and <QUEUE>_GROUP_ENABLE
    my $cfg = "\n\n# Queue configuration\n";
    if ( scalar %queues ) {
        $cfg .="QUEUES=\"".join(' ', keys %queues)."\"\n";
        foreach my $qvar ( sort keys %queues ) {
            my $varname = uc($qvar)."_GROUP_ENABLE";
            $cfg .= "${varname}=\"".$queues{$qvar}."\"\n";
        }
    }
    return($cfg);
}


##########################################################################
sub Configure($$@) {
##########################################################################

  my ($self, $config) = @_;

  my (%hash,$subkey,$found,$entry,$val);

  # Define base paths
  my $base = "/software/components/yaim";

  my $ceinfobase =$base."/CE";
  my $ftasinfobase=$base."/FTA";

  my $vobase=$base."/vo";
  # for backwards compatibility:
  my $vobasealt="/system/vo";
  # use 'classic' vobase path if component-specific one does not exist
  unless ($config->elementExists($vobase)) {
    $self->warn("no VO info found under $vobase, using $vobasealt");
    $vobase = $vobasealt;
  }
  # default language setting (work around for Savannah bug #27577)
  my $LANG="en_US.UTF-8";



  # yaim config file name
  #

  my $cfgfilename='/etc/lcg-quattor-site-info.def';

  if ($config->elementExists($base."/SITE_INFO_DEF_FILE")){
     $cfgfilename=$config->getValue($base."/SITE_INFO_DEF_FILE");
  } 
  
  # yaim secrets file
  my $sec_file_name="/etc/yaim.secretpasswords";

  if ($config->elementExists($base."/SECRET_PASSWORDS")){
     $sec_file_name=$config->getValue($base."/SECRET_PASSWORDS");
  } 

  #
  # get the yaim version
  #
  my $yaimversion; # no default for compatibility
  if ($config->elementExists($base."/conf/YAIM_VERSION")) {
      $yaimversion=$config->getValue($base."/conf/YAIM_VERSION");
      $yaimversion=$1 if ($yaimversion =~ /^(\d\.\d)/);
  }

  # yaim directory
  #
  my $yaimhome= ($yaimversion>=3.1)?'/opt/glite/yaim':'/opt/lcg/yaim'; # defaults to the LCG-2.7 value for compatibility

  if ($config->elementExists($base."/conf/YAIM_HOME")){
    $yaimhome=$config->getValue($base."/conf/YAIM_HOME");
  }

  #
  #
  my $yaimscriptdir=$yaimhome.'/scripts/';
  my $yaimbindir=$yaimhome.'/bin/';
  my $yaimexampledir=$yaimhome.'/examples/';

  # User.conf
  #
  my $usersconf='$yaimhome/users.conf'; # defaults to the LCG-2.7 value
  if ($config->elementExists($base."/conf/USERS_CONF")){
    $usersconf=$config->getValue($base."/conf/USERS_CONF");
  }

  # Group.conf
  #
  my $groupsconf='$yaimhome/groups.conf'; # defaults to the LCG-2.7 value
  if ($config->elementExists($base."/conf/GROUPS_CONF")){
    $groupsconf=$config->getValue($base."/conf/GROUPS_CONF");
  }

  # list of node types
  #
  my @nodetypes=('BDII',
                 'BDII_site',
                 'BDII_top',
                 'CE',
                 'CE_torque',
                 'lcg-RB',
                 'lcg-CE',
                 'lcg-CE_torque',
                 'glite-CE',
                 'glite-LB',
                 'glite-WMSLB',
                 'glite-WMS',
                 'glite-FTS',
                 'glite-FTA',
                 'glite-FTS2',
                 'glite-FTA2',
                 'glite-FTM2',
                 'LFC_mysql',
                 'LFC_oracle',
                 'MON',
                 'PX',
                 'RB',
                 'SE_classic',
                 'SE_castor',
                 'SE_dcache',
                 'SE_dpm_disk',
                 'SE_dpm_mysql',
                 'SE_dpm_oracle',
                 'SE_gridftpd',
                 'TAR',
                 'TORQUE_server',
                 'UI',
                 'VOBOX',
                 'VOMS',
                 'VOMS_oracle',
                 'WN',
                 'glite-WN',
                 'glite-UI',
                 'glite-NAGIOS',
                 'WN_torque',
                 'TORQUE_utils',
                 'MSG_publish_gridftp'
                );


  #
  # build up config file in mem, using pre-defined template
  #
  my $cfgfile=LC::File::file_contents("/usr/lib/ncm/config/yaim/site-info.def.template");

  #
  # switch indicating where VO-specific configuration goes
  # false: keep all in the site-info.def file
  # true:  create one file per VO in the vo.d directory under the directory
  #        containing site-info.def
  #
  my $use_vo_d = 0;
  if ($config->elementExists($base."/USE_VO_D")){
      $use_vo_d = $config->getValue($base."/USE_VO_D");
  }
  

  # first, normal key-value entries
  #
  # this is a hack. Should be refined into:
  # - host info
  # - bdii info
  # - miscellaneous
  # Locations to be discussed with Cal
  #

  unless ($config->elementExists("$base/conf")) {
      $self->error("$base/conf not found");
      return;
  }
  $found=0;
  
  foreach $entry qw(LCG_REPOSITORY CA_REPOSITORY REPOSITORY_TYPE
                    CE_HOST CLASSIC_HOST RB_HOST PX_HOST BDII_HOST MON_HOST
                    REG_HOST 
                    GRID_TRUSTED_BROKERS GRID_ACCEPTED_CREDENTIALS 
                    GRID_AUTHORIZED_RENEWERS GRID_DEFAULT_RENEWERS 
                    GRID_AUTHORIZED_RETRIEVERS GRID_DEFAULT_RETRIEVERS
                    GRID_AUTHORIZED_KEY_RETRIEVERS GRID_DEFAULT_KEY_RETRIEVERS
                    GRID_TRUSTED_RETRIEVERS GRID_DEFAULT_TRUSTED_RETRIEVERS
                    WN_LIST USERS_CONF
                    FUNCTIONS_DIR
                    MYSQL_PASSWORD GRIDICE_SERVER_HOST SITE_EMAIL SITE_SUPPORT_EMAIL
                    SITE_BDII_HOST
                    SITE_NAME SITE_VERSION SITE_HTTP_PROXY INSTALL_DATE INSTALL_ROOT OUTPUT_STORAGE
                    BDII_HTTP_URL BDII_REGIONS BDII_CE_URL BDII_SE_URL
                    BDII_RB_URL BDII_PX_URL
                    DCACHE_ADMIN DCACHE_POOLS DCACHE_PORT_RANGE RESET_DCACHE_CONFIGURATION
                    MY_DOMAIN
                    DPMCONFIG DPMDATA DPMDB_PWD DPMFSIZE DPM_HOST DPMLOGS
                    DPMPOOL DPM_POOLS DPM_PORT_RANGE DPMUSER_PWD DPMMGR DPM_FILESYSTEMS
                    DPM_DB_HOST DPM_DB_USER DPM_DB DPNS_DB DPM_DB_PASSWORD
                    DPM_INFO_USER DPM_INFO_PASS
                    FTS_SERVER_URL
                    GLOBUS_TCP_PORT_RANGE GRIDMAP_AUTH JAVA_LOCATION JOB_MANAGER
                    LFC_HOST SE_TYPE LFC_DB_PASSWORD LFC_DB LFC_DB_HOST
                    LFC_LOCAL LFC_CENTRAL
                    CRON_DIR
                    SITE_LOC SITE_LAT SITE_LONG SITE_WEB SITE_TIER SITE_SUPPORT_SITE
                    APEL_DB_PASSWORD
                    VOBOX_HOST VOBOX_PORT
                    GSSKLOG GSSKLOG_SERVER
                    LFC_TYPE LFC_HOST_ALIAS TORQUE_SERVER BATCH_SERVER EDG_WL_SCRATCH
                    BATCH_LOG_DIR BDII_FCR CE_DATADIR CLASSIC_STORAGE_DIR DPMPOOL_NODES
                    GROUPS_CONF RB_RLS SE_ARCH
                    YAIM_VERSION
                    VOMS_HOST
                    BATCH_BIN_DIR BATCH_VERSION
                    RFIO_PORT_RANGE VO_SW_DIR WMS_HOST ORACLE_LOCATION LB_HOST 
                    GRIDVIEW_WSDL GLITE_LOCATION USERS_DN_WMS
                    SITE_DESC SITE_SECURITY_EMAIL
                    SITE_OTHER_GRID SITE_OTHER_EGEE_ROC SITE_OTHER_EGEE_SERVICE
                    SITE_OTHER_WLCG_TIER
                    MYSQL_ADMIN
                    NAGIOS_ADMIN_DNS
                    NAGIOS_CGI_ENABLE_CONFIG
                    NAGIOS_HOST
                    NAGIOS_HTTPD_ENABLE_CONFIG
                    NAGIOS_NAGIOS_ENABLE_CONFIG
                    NAGIOS_NCG_ENABLE_CONFIG
                    NAGIOS_NSCA_PASS
                    NAGIOS_ROLE
                    NCG_GOCDB_COUNTRY_NAME
                    NCG_GOCDB_ROC_NAME
                    NCG_LDAP_FILTER
                    NCG_NRPE_UI
                    NCG_PROBES_TYPE
                      ) {
      
      if ($config->elementExists("$base/conf/$entry")) {
          $val=$config->getValue("$base/conf/$entry");
      } else {
          next;
      }
      $cfgfile .= uc($entry).'="'.$val."\"\n";
      $found++;
      #
      # Loop on BDII REGIONS
      #
      if($entry eq "BDII_REGIONS"){
          $self->verbose("LIST of BDII REGIONS = \"$val\"\n");
          my @region_list = split('\s+',$val);
          foreach my $region (@region_list){
              $self->verbose("Region \"$region\"\n");
              if ($region =~ /-/){
                  $self->error("Character \"-\" not allowed in the region tag \"$region\". Yaim will break");
              }
              my $region_tag = "BDII_". uc($region)."_URL";
              $self->verbose("Region tag \"$region_tag\"\n");
              if ($config->elementExists("$base/conf/$region_tag")) {
                  my $url = $config->getValue("$base/conf/$region_tag");
                  $self->verbose("URL for $region_tag found to be \"$url\"\n");
                  $cfgfile .= $region_tag.'="'.$url."\"\n";
              }
              else{
                  $self->error("No URL specified for region $region_tag");
              }
          }
      }
      #
      # End loop on BDII REGIONS
      #
  }
  unless ($found) {
      $self->error("no known configuration keys found under $base/conf, no configuration was applied");
      return;
  }
  
  #
  # loop over FTA specific info
  # The possible keys are not specified. Therefore no predefined list of KEYs.
  #
  
  $cfgfile.="\n#\n# FTA specific part:\n#\n";
  my $ftabase=$base."/FTA";
  my %ftahash;
  my $ftakey;
  my $ftaval;
  if ($config->elementExists($ftabase)) {
      %ftahash = $config->getElement($ftabase)->getHash();
      foreach $ftakey (sort keys %ftahash) {
          $ftaval = $config->getValue($ftabase."/".uc($ftakey));
          $cfgfile .= 'FTA_'.uc($ftakey).'="'.$ftaval."\"\n";
      }
  }
  
  
  #
  # loop over FTM specific info
  # The possible keys are not specified. Therefore no predefined list of KEYs.
  #
  
  $cfgfile.="\n#\n# FTM specific part:\n#\n";
  my $ftmbase=$base."/FTM";
  my %ftmhash;
  my $ftmkey;
  my $ftmval;
  if ($config->elementExists($ftmbase)) {
      %ftmhash = $config->getElement($ftmbase)->getHash();
      foreach $ftmkey (sort keys %ftmhash) {
          $ftmval = $config->getValue($ftmbase."/".uc($ftmkey));
          $cfgfile .= 'FTM_'.uc($ftmkey).'="'.$ftmval."\"\n";
      }
  }
  
  
  #
  # loop over FTS specific info
  #
  $cfgfile.="\n#\n# FTS specific part:\n#\n";
  my $ftsbase=$base."/FTS";
  my $ftsval;
  my $ftsentry;
  foreach $ftsentry qw(HOST_ALIAS DBURL STATS_GENERATION_INTERVAL SUBMIT_VOMS_ATTRIBUTES 
                       ADMIN_VOMS_ATTRIBUTES DB_SQLPLUS_CONNECTSTRING DB_USER DB_PASSWORD) {
      if ($config->elementExists("$ftsbase/$ftsentry")) {
          $ftsval=$config->getValue("$ftsbase/$ftsentry");
          $cfgfile .= 'FTS_'.uc($ftsentry).'="'.$ftsval."\"\n";
      }
  }
  
  #
  # loop over VOMS-ADMIN specific info
  #
  $cfgfile.="\n#\n# VOMS-ADMIN specific part:\n#\n";
  my $vomsadminbase=$base."/VOMS_ADMIN";
  my $vomsadminval;
  my $vomsadminentry;
  foreach $vomsadminentry qw(INSTALL TOMCAT_GROUP DEPLOY_DATABASE ORACLE_CLIENT SMTP_HOST ORACLE_CONNECTION_STRING DB_HOST WEB_REGISTRATION_DISABLE) {
      if ($config->elementExists("$vomsadminbase/$vomsadminentry")) {
          $vomsadminval=$config->getValue("$vomsadminbase/$vomsadminentry");
          $cfgfile .= 'VOMS_ADMIN_'.uc($vomsadminentry).'="'.$vomsadminval."\"\n";
      }
  }



  #
  # loop over CE specific info
  #
  $cfgfile.="\n#\n# CE specific part:\n#\n";
  foreach $entry qw(BATCH_SYS CPU_MODEL CPU_VENDOR
                    CPU_SPEED OS OS_RELEASE OS_ARCH OS_VERSION MINPHYSMEM
                    MINVIRTMEM SMPSIZE SI00 SF00 OUTBOUNDIP
                    INBOUNDIP RUNTIMEENV BDII_SITE_TIMEOUT BDII_RESOURCE_TIMEOUT 
                    GIP_RESPONSE GIP_FRESHNESS GIP_CACHE_TTL GIP_TIMEOUT PHYSCPU LOGCPU) {
      
      if ($config->elementExists("$ceinfobase/$entry")) {
          $val=$config->getValue("$ceinfobase/$entry");
      } else {
          next;
      }
      $cfgfile .= 'CE_'.uc($entry).'="'.$val."\"\n";
  }
  
  #
  # now, loop over CE close SE's
  #
  # I prefer using an nlist (rather than a list) here since it allows
  # for overwriting in inheritance.. that might make sense for VO's as
  # well.
  #
  my $closeSE=$ceinfobase.'/closeSE';
  my @ses;
  my @se_hosts;
  my $se_cfg;
  if ($config->elementExists($closeSE)) {
      %hash = $config->getElement($closeSE)->getHash();
      foreach my $se (sort keys %hash) {
          push (@ses,$se);
          foreach $subkey qw(HOST ACCESS_POINT) {
              if ($config->elementExists("$closeSE/$se/$subkey")) {
                  $se_cfg .= "CE_CLOSE_".uc($se."_".$subkey).'="'.$config->getValue("$closeSE/$se/$subkey")."\"\n";
                  if ($subkey eq "HOST"){
                      push (@se_hosts, $config->getValue("$closeSE/$se/$subkey"));
                  }
              }
          }
      }
      $cfgfile .= 'CE_CLOSE_SE="'.uc(join (' ',@ses)) ."\"\n";
      $cfgfile .= 'SE_LIST="'.join (' ',@se_hosts) ."\"\n";
      $cfgfile .= $se_cfg;
  } elsif ( $yaimversion < 3.1 ) {
      # closeSE information is since a loooong time obsolete (LCG 2.7.0?)
      # to be safe, the warning is only shown for Yaim versions older than 3.1
      $self->warn("no SE information defined under $closeSE");
  }

  # Append queue-related configuration
  $cfgfile .= &getQueueConfig($self, $config, $base, $vobase);
  
  #
  # now, loop over VO's for SW_DIR, DEFAULT_SE etc.
  #
  my @vos;
  my @lfc_local;
  my @lfc_central;
  my $range;
  my $vo_cfg="\n#\n# VO specific part:\n#\n";
  
  my %vo_d_cfg;
  
  if ($config->elementExists($vobase)) {
      %hash = $config->getElement($vobase)->getHash();
      foreach my $key (sort keys %hash) {
          my $vo = $config->getValue("$vobase/$key/name");
          my $vo_for_env=vo_for_env($vo);
          
          $vo_d_cfg{$vo} = "#\n# VO specific config for $vo\n#\n";
          
          push(@vos,$vo);
          if ($config->elementExists("$vobase/$key/services/LFC")){
              $range = $config->getValue("$vobase/$key/services/LFC");
              if (lc($range) eq "local") { push (@lfc_local, $vo); }
              if (lc($range) eq "central") { push (@lfc_central, $vo); }
          }
          foreach $subkey qw(SW_DIR DEFAULT_SE SE SGM USERS STORAGE_DIR 
                             VOMS_SERVERS VOMS_EXTRA_MAPS VOMS_POOL_PATH VOMSES VOMS_CA_DN
                             VOMS_DB_NAME VOMS_PORT VOMS_DB_USER VOMS_ADMIN_DB_USER VOMS_CORE_TIMEOUT VOMS_ADMIN_MAIL VOMS_DB_USER_PASSWORD) {
              if ($config->elementExists("$vobase/$key/services/$subkey")) {
                  if ($use_vo_d) {
                      $vo_d_cfg{$vo} .= "$subkey=\""
                          .  $config->getValue("$vobase/$key/services/$subkey")
                          .  "\"\n";
                  }
                  else {
                      $vo_cfg .= "VO_${vo_for_env}_${subkey}=\""
                          .  $config->getValue("$vobase/$key/services/$subkey")
                          .  "\"\n";
                  }
              }
          }
	  
	    }


      # If we've been given an ordered list of VOs, use it instead of the
      # one we've just created
      if($config->elementExists("$base/VOs")) {
          my @ordered_vos=$config->getElement("$base/VOs")->getList();
          $cfgfile .= "\n".'VOS="'.join (' ',map($_->getValue(),@ordered_vos)) ."\"\n";
      } else {
          $cfgfile .= "\n".'VOS="'.join (' ',@vos) ."\"\n";
      }
      $cfgfile .= $vo_cfg unless ($use_vo_d);
      $cfgfile .= "\n#\n# LFC specific part:\n#\n";
      $cfgfile .= 'LFC_CENTRAL="'.join(' ',@lfc_central)."\"\n";
      $cfgfile .= 'LFC_LOCAL="'.join(' ',@lfc_local)."\"\n";
  } else {
      $self->warn("no VO information defined under $vobase");
  }
  
  #
  # Free variables under .../yaim/extra, as requested 
  #
  $cfgfile.="\n#\n# free configuration part\n#\n";
  my $extrabase=$base."/extra";
  my %extrahash;
  my $extrakey;
  my $extraval;
  if ($config->elementExists($extrabase)) {
      %extrahash = $config->getElement($extrabase)->getHash();
      foreach $extrakey (sort keys %extrahash) {
          $extraval = $config->getValue($extrabase."/".uc($extrakey));
          $cfgfile .= uc($extrakey).'="'.$extraval."\"\n";
      }
  }
  
  #######################################################################################
  #
  # Section to provide a users.conf & groups/conf file
  # Since gLite 3.0, these files are mandatory for a YAIM configuration
  # 1) Check for a creating program in /usr/libexec and run it, if it exists 
  # 2) Check for the existance of the users.conf resp. group.conf file, and
  #    if it does not exist, copy the default one
  #
  
  #
  # Create a USERS_CONF file, if script exists:
  #
  system("[ -x /usr/libexec/create-YAIM-users_conf ] && /usr/libexec/create-YAIM-users_conf $usersconf");
  
  # Copy the default users.conf if no file exists
  #
  system("[ -e $usersconf ] || cp $yaimexampledir/users.conf $usersconf");

  #
  # Create a GROUPS_CONF file, if script exists:
  #
  system("[ -x /usr/libexec/create-YAIM-groups_conf ] && /usr/libexec/create-YAIM-groups_conf $groupsconf");

  # Copy the default groups.conf file, if no file exists
  #
  system("[ -e $groupsconf ] || cp $yaimexampledir/groups.conf $groupsconf");

 
  ##########################################################################################
  #
  # Check for a 'secure' file in /etc and add the contents
  #
  if ( -e $sec_file_name ){
     $cfgfile.="\n#\n# yaim.secretpasswords:\n#\n";
     $cfgfile.=file_contents($sec_file_name);
  }

  ##########################################################################################
  #
  # Recreate the site-info.def file, if there were changes 

  #
  # update the config file if changes
  #
  my $update=0;

  my $res = &write_cfg_file($self, $cfgfilename, $cfgfile);
  return if ($res == -1);
  $update ||= $res;

  if ($use_vo_d) {
    # get basedir for SITE_INFO_DEF and check for existence of dir vo.d
    my $basedir = dirname($cfgfilename);
    if ( ! -d "$basedir/vo.d" ) {
      $self->info("Creating directory $basedir/vo.d");
      mkdir "$basedir/vo.d", "0777" or $self->error("$!");
    }

    # loop over all entries in %vo_d_cfg and write the contents to the individual files
    foreach my $voname (keys %vo_d_cfg) {
      # compare contents via function that contains the above
      $res = &write_cfg_file($self, "$basedir/vo.d/$voname", $vo_d_cfg{$voname});
      return if ($res == -1);
      $update ||= $res;
    }
  }

  if ($update) {
    my $node;
    my @list_of_nodes=();

    foreach $node (@nodetypes) {
      if ($config->elementExists("$base/nodetype/$node") &&
          $config->getValue("$base/nodetype/$node") eq 'true') {
        push(@list_of_nodes,$node);
      }
    }

    unless (scalar @list_of_nodes) {
      $self->warn("no known node types defined under $base/nodetype, no installation was applied");
    } else {

      #
      # The YAIM command to execute
      #
      my $full_install_command;
      my $full_config_command;

      #
      # work around for Savannah bug #27577
      # setting LANG should result in the sorting order which yaim expects
      #
      $ENV{"LANG"}="en_US.UTF-8";
      #
      my $ENVSET = "export LANG=$LANG;";
      if (defined $yaimversion && $yaimversion >= 3.1){
          my $node_type_arg ="";
          foreach my $nodtyp (@list_of_nodes) {
                $node_type_arg .= " -m \"$nodtyp\"";
          }
          $full_install_command = $ENVSET . $yaimbindir."/yaim -i -s ".$cfgfilename.$node_type_arg;

          $node_type_arg ="";
          foreach my $nodtyp (@list_of_nodes) {
                $node_type_arg .= " -n \"$nodtyp\"";
          }
          $full_config_command  = $ENVSET . $yaimbindir."/yaim -c -s ".$cfgfilename.$node_type_arg;

      } else {
          $full_install_command = $ENVSET . $yaimscriptdir."/install_node ".$cfgfilename." ".join(' ',(@list_of_nodes));
          $full_config_command  = $ENVSET . $yaimscriptdir."/configure_node ".$cfgfilename." ".join(' ',(@list_of_nodes));
      }
      #
      # Should NCM run the YAIM installer (if you use apt to install the RPMS)?
      #
      if ($config->elementExists("$base/install") &&
          $config->getValue("$base/install") eq 'true'){
        $self->run_command($full_install_command);
      } else {
        $self->info("install = false   => Do not run : \"".$full_install_command."\".");
      }
      # 
      # Should NCM run YAIM or just print the action?
      #
      if ($config->elementExists("$base/configure") &&
          $config->getValue("$base/configure") eq 'true'){
        $self->run_command($full_config_command);
      } else {
        $self->info("configure = false => Do not run : \"".$full_config_command."\".");
      }
    }      
  } else {
    $self->info("no changes in $cfgfilename, no action taken");
  }
#
# Fix Savannah bug #15494 (read restrictions for the config file)
#
  if (!(chmod 0600, $cfgfilename)){
    $self->warn("Cannot change file mode of $cfgfilename to 0600");
  }

  return;
}

1;      # Required for PERL modules
