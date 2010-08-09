# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
# Coding style: emulate <TAB> characters with 4 spaces, thanks!
################################################################################


package NCM::Component::pbsclient;

#
# a few standard statements, mandatory for all components
#

use strict;
use LC::Check;
use File::Path;
use NCM::Check;
use NCM::Component;
use Fcntl ':mode';
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;

my ($pbsmomconf)="/var/spool/pbs/mom_priv/config";
my ($pbsdir)="/var/spool/pbs";
my ($pbsmomdir)="/var/spool/pbs/mom_priv";
my ($pbsinitscript)="/etc/init.d/pbs";
my ($masterlist, $restrictedlist, $logevent, $tmpdir, %resources);
my ($checkpoint_interval,$checkpoint_script,$restart_script,$checkpoint_run_exe,$remote_checkpoint_dirs,$max_conn_timeout_micro_sec);
my ($resources, $cpuf, $wallf, $idealload, $maxload);
my (%usecp, $prologalarm, $behaviour, $nodecheckscript);
my ($nodecheckinterval);

sub initpaths {
  my ($config) = (@_);

  # where should the config file be written? Will default
  if ( $config->elementExists("/software/components/pbsclient/configPath")){
    $pbsmomconf = 
      $config->getValue("/software/components/pbsclient/configPath");
  }
  # name of the init script to restart pbs if config changed
  if ( $config->elementExists("/software/components/pbsclient/initScriptPath")){
    $pbsinitscript = 
      $config->getValue("/software/components/pbsclient/initScriptPath");
  }
 
  # make sure pbs mom directory exists and it properly writable
  ($pbsmomdir=$pbsmomconf) =~ s/\/[^\/]+$//; # implements dirname()
  ($pbsdir=$pbsmomdir) =~ s/\/[^\/]+$//; # implements dirname() again

}

sub retrieve {
  my ($self,$config,$path,$isreq,$scref,$default) = @_;
  my ($tmpval);

  $self->debug(1,"Retrieving resource in $path");

  if ( $config->elementExists($path) ) {
    $tmpval = $config->getValue($path);
    $$scref=$tmpval;
    $self->debug(1,"Set value of ref ".$scref." to $tmpval");
  } else {
    if ($isreq) {
      $self->Error("Cannot obtain required value from $path");
    } else {
      $$scref=$default;

      $default or $default="<undef>";
      $self->debug(1,"Set value of ref ".$scref." to default $default");
    }
  }
}

##########################################################################
sub Configure {
##########################################################################
  my ($self,$config)=@_;
  my ($n) = 0;
  my $changes = 0;
  
  $self->info("Configuring PBS");

  &initpaths($config);

  $self->debug(2,"PBSMOMDIR $pbsmomdir; PBSDIR $pbsdir");

  # the masterlist will fill the $clienthost directive
  $masterlist="";
  $n=0;
  while ($config->elementExists(
            "/software/components/pbsclient/masters/".$n)) {
    ($masterlist ne "") and $masterlist.=" ";
    $masterlist .=
      $config->getValue("/software/components/pbsclient/masters/".$n);
    $n++;
  }
  if ($masterlist eq ""){
    $self->error("Empty master list");
    return;
  }

  # the restrictedlist will fill the $restricted directive
  $restrictedlist="";
  $n=0;
  while ($config->elementExists(
            "/software/components/pbsclient/restricted/".$n)) {
    ($restrictedlist ne "") and $restrictedlist.=" ";
    $restrictedlist .=
      $config->getValue("/software/components/pbsclient/restricted/".$n);
    $n++;
  }
  if ($restrictedlist eq ""){
    $self->info("No additional hosts added to the restricted list");
  }

  # additional resources (those without a $) that end up in the config

  $n=0;
  while (
      $config->elementExists("/software/components/pbsclient/resources/$n") ) {
    my $resource = 
      $config->getValue("/software/components/pbsclient/resources/$n");
    my ($a,$v)=split(/:/,$resource,2);
    $resources{$a}=$v;
    $n++;
  } 

  # add cpuinfo if defined by user :
  # users can define a list of properties they want to be included?
  # example elements are : "cpu count","model name","cpu MHz","cpu family","model","stepping"...
  if($config->elementExists("/software/components/pbsclient/cpuinfo")) {
    $self->info("Additional CPUINFO elements exist, adding them as resources to mom config");
    my @cpuinfoElements=@{$config->getElement("/software/components/pbsclient/cpuinfo")->getTree};
    my %tmphash=cpuinfo_hash();
    my %tmphash2;
    for my $elem (@cpuinfoElements) {
      if(defined $tmphash{$elem}) {
          my $prop = $elem;
          #have things more readable
          $prop =~ s/^(model |cpu |)//;
          $prop =~ tr/ /_/;
          #prefix a "cpu_" for all properties except ncpus and ncores
          $prop="cpu_" . $prop unless( $prop =~ m/(^ncores)/) ;
          #$tmphash2{$elem}=$tmphash{$elem}
          $tmphash2{$prop}=$tmphash{$elem}
        }
    }      
    # add cpuinfo to resources
    %resources = (%resources, %tmphash2);
  };



  # can we add Torque-specific stuff (e.g. location of the server name)?
  $self->retrieve($config,
                  "/software/components/pbsclient/behaviour",0,
                  \$behaviour,"OpenPBS");

  # verbosity of the pbs mom
  $self->retrieve($config,
                  "/software/components/pbsclient/logEvent",0,
                  \$logevent,undef);

  # tmpdir (from the transient_tmpdir patch)
  $self->retrieve($config,
                  "/software/components/pbsclient/tmpdir",0,
                  \$tmpdir,undef);
  
  # idealload
  $self->retrieve($config,
                  "/software/components/pbsclient/idealLoad",0,
                  \$idealload,undef);
 
  # maxload
  $self->retrieve($config,
                  "/software/components/pbsclient/maxLoad",0,
                  \$maxload,undef);

  # cpuFactor
  $self->retrieve($config,
                  "/software/components/pbsclient/cpuTimeMultFactor",0,
                  \$cpuf,undef);

  # wallFactor
  $self->retrieve($config,
                  "/software/components/pbsclient/wallTimeMultFactor",0,
                  \$wallf,undef);

  # prologAlarmSec
  $self->retrieve($config,
                  "/software/components/pbsclient/prologAlarmSec",0,
                  \$prologalarm,undef);

  # nodeCheckScriptPath
  $self->retrieve($config,
                  "/software/components/pbsclient/nodeCheckScriptPath",0,
                  \$nodecheckscript,undef);

  # nodeCheckIntervalSec
  $self->retrieve($config,
                  "/software/components/pbsclient/nodeCheckIntervalSec",0,
                  \$nodecheckinterval,undef);

  # checkpoint_interval
  $self->retrieve($config,
                  "/software/components/pbsclient/checkpoint_interval",0,
                  \$checkpoint_interval,undef);

  # checkpoint_script
  $self->retrieve($config,
                  "/software/components/pbsclient/checkpoint_script",0,
                  \$checkpoint_script,undef);

  # restart_script
  $self->retrieve($config,
                  "/software/components/pbsclient/restart_script",0,
                  \$restart_script,undef);

  # checkpoint_run_exe
  $self->retrieve($config,
                  "/software/components/pbsclient/checkpoint_run_exe",0,
                  \$checkpoint_run_exe,undef);

  # remote_checkpoint_dirs
  $self->retrieve($config,
                  "/software/components/pbsclient/remote_checkpoint_dirs",0,
                  \$remote_checkpoint_dirs,undef);

  # max_conn_timeout_micro_sec
  $self->retrieve($config,
                  "/software/components/pbsclient/max_conn_timeout_micro_sec",0,
                  \$max_conn_timeout_micro_sec,undef);


  # additional usecp directives, list of lists(2)
  $n=0;
  while (
      $config->elementExists("/software/components/pbsclient/directPaths/$n")){
    # do both elements exist?
    $self->Error("Cannot find mountloc for directPath $n") unless
      $config->elementExists("/software/components/pbsclient/directPaths/$n/locations");
    $self->Error("Cannot find location for directPath $n") unless
      $config->elementExists("/software/components/pbsclient/directPaths/$n/path");

    my $locations = 
      $config->getValue("/software/components/pbsclient/directPaths/$n/locations");
    my $path = 
      $config->getValue("/software/components/pbsclient/directPaths/$n/path");

    $usecp{$locations}=$path;
    $self->debug(1,"Adding direct path $n: \$usecp $locations $path");
    $n++;
  } 



  LC::Check::directory("$pbsmomdir");

  -e "$pbsmomconf" or ( open PBSMOMCONF,">$pbsmomconf" and close PBSMOMCONF );
  -f "$pbsmomconf" or $self->Error("$pbsmomconf exists but is not a file");

  #
  # Create the Torque client config file from configuration
  #
  my $contents = "# File managed by Quattor component ncm-pbsclient. DO NOT EDIT.\n\n";
  
  # create the line(s) with the $clienthost directives from the master list
  foreach ( split(/\s+/,$masterlist) ) { 
    $contents.='$clienthost '.$_."\n";
  }

  $tmpdir and $contents .= '$tmpdir ' . $tmpdir . "\n";
 
  $logevent and $contents .= '$logevent ' . $logevent . "\n";

  $cpuf and $contents .= '$cputmult ' . $cpuf . "\n";

  $wallf and $contents .= '$wallmult ' . $wallf . "\n";

  $idealload and $contents .= '$idealload ' . $idealload . "\n";

  $maxload and $contents .= '$maxload ' . $maxload . "\n";

  $prologalarm and $contents .= '$prologalarm ' . $prologalarm . "\n";

  $nodecheckscript and $contents .= '$nodecheckscript ' . $nodecheckscript . "\n";

  $nodecheckinterval and $contents .= '$nodecheckinterval ' . $nodecheckinterval . "\n";

  $checkpoint_interval and $contents .= '$checkpoint_interval ' . $checkpoint_interval . "\n";

  $checkpoint_script and $contents .= '$checkpoint_script ' . $checkpoint_script . "\n";

  $restart_script and $contents .= '$restart_script ' . $restart_script . "\n";

  $checkpoint_run_exe and $contents .= '$checkpoint_run_exe ' . $checkpoint_run_exe . "\n";

  $remote_checkpoint_dirs and $contents .= '$remote_checkpoint_dirs ' . $remote_checkpoint_dirs . "\n";

  $max_conn_timeout_micro_sec and $contents .= '$max_conn_timeout_micro_sec ' . $max_conn_timeout_micro_sec . "\n";

  if ( $behaviour eq "Torque" ) { # add a $pbsservername line
    # assume first master is the real one
    my $pbsmastername=(split(/\s+/,$masterlist))[0];
    $pbsmastername and $contents .= '$pbsmastername ' . $pbsmastername . "\n";
  }

  # create the line(s) with the $restricted directives from the master list
  foreach ( split(/\s+/,$restrictedlist) ) { 
    $contents .= '$restricted ' . $_ . "\n";
  }

  # create the line(s) with the $usecp direcxties from path hash
  foreach ( keys %usecp ) { 
    $contents .= '$usecp ' . $_ . " " . $usecp{$_} . "\n";
  }

  # Define other resources
  foreach ( keys %resources ) { 
    $self->info("Additional resource '" . $_ . "' defined");
    my $resource_string = $_;
    if ( defined($resources{$_}) && length($resources{$_}) ) {
      $resource_string .= " " . $resources{$_};
    }
    $contents .= $resource_string . "\n";
  }


  #
  # Update Torque client configuration file if needed
  #
  
  my $result = LC::Check::file( $pbsmomconf,
                                backup => ".old",
                                contents => $contents,
                                owner => "root",
                                group => "root",
                                mode  => 0640,
                              );
  if ( $result ) {
    $self->log("$pbsmomconf updated");
    $changes += $result;
  }


  #
  # Update server_name file
  #
  
  my $srvfile="$pbsdir/server_name";
  -e "$srvfile" or ( open SNM,">$srvfile" and close SNM );
  -f "$srvfile" or $self->Error("$srvfile exists but is not a file");

  my $master=(split(/\s+/,$masterlist))[0];
  if ( $master ) { 
    my $result = LC::Check::file( $srvfile,
                                  backup => ".old",
                                  contents => $master,
                                  owner => "root",
                                  group => "root",
                                  mode  => 0644,
                                );
    if ( $result ) {
      $self->log("$srvfile updated");
      $changes += $result;
    }
  }


  # Ensure that the tmpdir exists if it is specified.
  # For torque 2+, this directory must have group write privilege.
  #
  # Bug 28585: 
  # Do NOT set the absolute permissions because that may affect other permissions
  # Just ensure that the group can write to $tmpdir
  if ( defined($tmpdir) ) {
    # Bug 37119: The group writable bit is suppressed by the default umask
    #            So always check that the group writable bit is set and
    #            toggle it if that is not the case
    if ( ! -e $tmpdir ) {
      mkpath("$tmpdir",0,01775);
    }
    my $mode = (stat $tmpdir)[2];
    if ( ! ($mode & S_IWGRP) ) {
        $mode |= S_IWGRP;
        $self->info("Setting permissions on TMPDIR $tmpdir to " .
                     sprintf("%04o", $mode & 07777));
        chmod ($mode, $tmpdir);
    }
  }

  # Install (or remove) the various epilogue and prologue scripts.
  # No need to mark changes because pbs picks up the scripts
  # dynamically.
  my %scriptperms = ("prologue" => 0700,
             "epilogue" => 0700,
             "prologue.user" => 0755,
             "epilogue.user" => 0755,
             "prologue.parallel" => 0700);

  foreach my $script (keys %scriptperms) {
    my $panpath = '/software/components/pbsclient/scripts/'.$script;
    my $fullpath = "$pbsmomdir/$script";
    if ($config->elementExists($panpath)) {
      my $contents = $config->getValue($panpath);
      my $result = LC::Check::file( $fullpath,
                                    backup => ".old",
                                    contents => $contents,
                                    owner => "root",
                                    group => "root",
                                    mode  => $scriptperms{$script},
                                  );
      if ( $result ) {
        $self->log("$fullpath updated");
      }
    }
  }

  # restart PBS if it is already running AND the config changed
  if ($changes) {
    system("$pbsinitscript status > /dev/null && $pbsinitscript restart")
  };

  return;
}


##########################################################################
sub Unconfigure {
##########################################################################
  my ($self,$config)=@_;

  $self->info("Unconfiguring PBS");
  
  &initpaths($config);

  return;
}

##########################################################################
# returns a hash with cpuinfo
sub cpuinfo_hash {
##########################################################################
  my %localres;
  my %cpuinfo;
  #
  #assume processor number is the first information in cpuinfo
  #if a newline is found, increase the processor number
  #(processors are separated with newlines)
  
  # Opening the file /proc/cpuinfo for input...
  my $processor=0;
  open (CPUINFO, "</proc/cpuinfo") || die "Can't open file \/proc\/cpuinfo!! : $!\n";
  while (<CPUINFO>) {
      chomp;                  #removing newline
      my $linetest =$_;          #checking if the line contains a :
      if ($linetest=~ m/^$/) {
          $processor+=1;
      }
      if ($linetest=~ m/:/) {
          my ($key, $value) = split /\s*:\s*/; #if so, split the line in 2
          $cpuinfo{$processor}{$key} = $value;        #and put the keys & and values in a hash
      }
  }

  # close the filehandle since it is no longer needed.
  close (CPUINFO);

  my %cpus=(0,"");
  for (keys %cpuinfo) {
      #print "$_\n";
      my $processor = 0;
      $processor = $cpuinfo{$_}{"processor"} if exists $cpuinfo{$_}{"processor"};
      if(exists($cpuinfo{$_}{"physical id"})) { $cpus{$cpuinfo{$_}{"physical id"}}=$processor ; }
      else  {$cpus{$processor}=$processor ; }
  }
  my @cpulist=sort keys %cpus;

  # define a resource for the number of CPUs
  my $ncpus= $cpulist[$#cpulist] +1;
  #print "ncpus $ncpus" ;
  $localres{"cpu count"}=$ncpus;

  # define a resource for the number of CPU cores
  my $ncores = scalar keys %cpuinfo;
  #print "\nncores $ncores\n";
  $localres{"ncores"}=$ncores;


  # define several localres related to the 1st CPU
  # We're assuming all CPUs are the SAME (does anybody mix CPUs in a cluster node ?) !
  # If the pbs client has different cpus, then... too bad.
  # 
  for my $property (keys %{$cpuinfo{0}}) {
      $localres{$property}=$cpuinfo{0}{$property}
  }

  return %localres
  }

1; #required for Perl modules
