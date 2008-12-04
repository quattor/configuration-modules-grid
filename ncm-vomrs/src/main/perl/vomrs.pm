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


package NCM::Component::vomrs;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;


use LC::File qw(file_contents copy);
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
    chmod 0600, $cfgfilename ;
    $self->info ("updated $cfgfilename");
  }
  return($update);
}



##########################################################################
sub Configure($$@) {
##########################################################################

  my ($self, $config) = @_;

  my (%hash,$subkey,$found,$entry,$val);

  # Define base paths
  my $base = "/software/components/vomrs";


  my %info = (   
                "vomrs" => "VOMRS Configuration",
                "voinfo" => "VO Related information",
                "gridorg" => "Grid Organisation",
                "tomcat" => "Tomcat Related Information",
                "cacert" => "Dealing with Certificate Authorities",
                "vomem"  => "VO Membership Related",
                "event"   => "Event Notification" ,
                "sync"    => "VOMS Syncronisation",
                "db"      => "VOMRS Database  Details",
                "lcg"    => "LCG Registration Details"
             ) ;

  my $vobase=$base."/vo";
  my $LANG="en_US.UTF-8";



  # yaim config file name
  #
  my $cfgdir='/etc/vomrs-quattor.d' ;
  if ($config->getValue($base."/confdir")) {
      $cfgdir=$config->getValue($base."/confdir") ;
  }
 if ( ! -d "$cfgdir" ) {
      $self->info("Creating directory $cfgdir");
      mkdir "$cfgdir", "0777" or $self->error("$!");
 }



  # yaim secrets dir
  my $secdir="/etc/vomrs-secrets";

  if ($config->elementExists($base."/vomrssecretdir")){
     $secdir=$config->getValue($base."/vomrssecretdir");
  } 

  

  my $vomrshome= '/opt/vomrs-1.3'; # VOMRS_LOCATON 

  if ($config->elementExists($base."/home")){
    $vomrshome=$config->getValue($base."/home");
  }

  if ( ! -f $vomrshome."/etc/profile.d/vomrs.sh" && -f '/opt/glite/etc/profile.d/grid-env.sh' ) {
     $self->info("Creating symbolic link ".$vomrshome."/etc/profile.d/vomrs.sh to") ;
     $self->info("  /opt/glite/etc/profile.d/grid-env.sh") ;
     symlink('/opt/glite/etc/profile.d/grid-env.sh',$vomrshome.'/etc/profile.d/vomrs.sh') ;
  }


  my $confscript =  $vomrshome."/sbin/configure_vomrs" ;
  if ($config->elementExists($base."/confscript")){
    $confscript = $config->getValue($base."/confscript");
  }

  if ($config->elementExists($base."/log4jconfig")){
      $self->info("Creating file: ".$vomrshome."/etc/cfg/log4j.properties.template") ;
      open(LOG,">".$vomrshome."/etc/cfg/log4j.properties.template") ;
      print LOG "# Quattor created file in location\n" ;
      print LOG "# ".$vomrshome."/etc/cfg/log4j.properties.template\n\n" ;
      print LOG $config->getValue($base."/log4jconfig") ;
      print LOG "\n# End of Quattor created file, the rest comes from vomrs_configure itself.\n\n" ;
      close(LOG);
  }


  #
  # build up config file in mem, using pre-defined template
  #


    
  if ($config->elementExists("$base/VOs")) {
    foreach my $voh ($config->getElement("$base/VOs")->getList()){
        my $vo = $voh->getValue() ;
        $self->verbose("Looking at configuration for vo \"$vo\"\n") ;
        my $cfgfile=LC::File::file_contents("/usr/lib/ncm/config/vomrs/vomrs.cfg.template");
        $cfgfile .= "##### VOMRS Configuration for VO $vo #########\n\n" ;
        foreach my $section  (sort keys %info ) {
           if ($config->elementExists($base.'/vo/'.$vo.'/'.$section) ) {
               $cfgfile .= "###### Section: ".$info{$section}."\n" ;
               my %secthash = $config->getElement($base.'/vo/'.$vo.'/'.$section)->getHash();
               foreach my $key (sort keys %secthash ) {
                    $cfgfile .= $key.' = '.$secthash{$key}->getValue."\n" ;
               }
               $cfgfile .= "\n" ;
           }
        }
        my $secret = $secdir."/vomrs-secrets-".$vo.".cfg"  ;
        $self->verbose("Checking for secrets file \"$secret\"") ;
        if ( -e $secret ) {
             $self->verbose("Reading in secrets file \"$secret\"") ;
             $cfgfile.= "\n####   Secrets from vomrs-secrets via SINDES\n\n" ;
             $cfgfile.= file_contents($secret) ;
        }
        my $update = 0 ;
        my $cfgfilename = $cfgdir.'/vomrs-'.$vo.'.cfg' ;
        my $res = &write_cfg_file($self, $cfgfilename, $cfgfile);
        return if ($res == -1) ;
        $update ||= $res ;

        my $command =  $confscript." --autorun --skip-database -f ".$cfgfilename ;
        if ( $update ) {
           if ( $config->elementExists("$base/configure" ) && $config->getValue("$base/configure") eq 'true' ) {
                $self->run_command($command) ;
                $self->info("Copying vomrs_$vo.xml file to /etc/tomcat5/Catalina/localhost/.") ;
                LC::File::copy($vomrshome.'/var/etc/vomrs_'.$vo.'/vomrs_'.$vo.'.xml','/etc/tomcat5/Catalina/localhost/vo#'.$vo.'.xml') ;
           }
           else {
                $self->info("configure = false => Do not run \"$command\"") ;
           }
        }
        else {
             $self->info("no changes in $cfgfilename, no action taken") ;
        }
    }

  }

  return;
}

1;      # Required for PERL modules
