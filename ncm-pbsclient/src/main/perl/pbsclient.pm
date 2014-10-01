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

use constant COMPONENTPATH => "/software/components/pbsclient";

use constant DEFAULTPBSMOMCONF => "mom_priv/config";
use constant DEFAULTPBSINITSCRIPT => "/etc/init.d/pbs";
use constant DEFAULTPBSDIR => "/var/torque";
use constant DEFAULTPBSMOMDIR => "mom_priv";

use constant SCRIPTPERMS => {"epilogue" => 0700,
                             "epilogue.user" => 0755,
                             "epilogue.parallel" => 0700,
                             "prologue" => 0700,
                             "prologue.user" => 0755,
                             "prologue.parallel" => 0700
                            };

use constant PBSCLIENTOPTIONS => qw(
    mom_host
    xauthpath
);

use constant PBSINITIALISATIONVALUES => qw(
    auto_ideal_load
    auto_max_load
    cputmult
    configversion
    check_poll_time
    checkpoint_interval
    checkpoint_script
    checkpoint_run_exe
    down_on_error
    enablemomrestart
    ideal_load
    igncput
    ignmem
    ignvmem
    ignwalltime
    job_output_file_mask
    log_directory
    logevent
    log_file_suffix
    log_keep_days
    loglevel
    log_file_max_size
    log_file_roll_depth
    max_conn_timeout_micro_sec
    max_load
    memory_pressure_threshold
    memory_pressure_duration
    node_check_script
    node_check_interval
    nodefile_suffix
    nospool_dir_list
    prologalarm
    rcpcmd
    remote_checkpoint_dirs
    remote_reconfig
    restart_script
    source_login_batch
    source_login_interactive
    spool_as_final_name
    status_update_time
    tmpdir
    timeout
    use_smt
    wallmult
);

## Camelcase reflect older naming convention
## map is: schemaname -> initialisationname
## legacy issues: idealLoad, maxLoad, nodeCheckScriptPath, nodeCheckIntervalSec are probably wrong
use constant PBSINITIALISATIONVALUESMAP => {
    'logEvent' => 'logevent',
    'cpuTimeMultFactor' => 'cputmult',
    'wallTimeMultFactor' => 'wallmult',
    'idealLoad' => 'idealload',
    'maxLoad' => 'maxload',
    'prologAlarmSec' => 'prologalarm',
    'nodeCheckScriptPath' => 'nodecheckscript',
    'nodeCheckIntervalSec' => 'nodecheckinterval'
};


##########################################################################
sub Configure {
##########################################################################
    my ($self,$config)=@_;
    my $changes = 0;

    $self->info("Configuring PBS");

    #
    # Create the Torque client config file from configuration
    #
    my $contents = "# File managed by Quattor component ncm-pbsclient. DO NOT EDIT.\n\n";

    our $cfgtree = $config->getElement(COMPONENTPATH)->getTree;

    ##
    ## initPaths
    ##
    my $pbsroot    = exists($cfgtree->{pbsroot}) ? $cfgtree->{pbsroot} : DEFAULTPBSDIR;
    my $pbsmomconf = exists($cfgtree->{configPath}) ? $pbsroot . '/' . $cfgtree->{configPath} : $pbsroot . '/' . DEFAULTPBSMOMCONF;
    my $pbsinitscript = exists($cfgtree->{initScriptPath}) ? $cfgtree->{initScriptPath} : DEFAULTPBSINITSCRIPT;

    my $pbsdir=$pbsroot;
    my $pbsmomdir=$pbsroot. '/' . DEFAULTPBSMOMDIR;
    # make sure pbs mom directory exists and it properly writable
    #($pbsmomdir=$pbsmomconf) =~ s/\/[^\/]+$//; # implements dirname()
    #($pbsdir=$pbsmomdir) =~ s/\/[^\/]+$//; # implements dirname() again
    $self->debug(2,"PBSMOMDIR $pbsmomdir; PBSDIR $pbsdir");


    # the masterlist will fill the $clienthost directive
    # create the line(s) with the $clienthost directives from the master list
    my $pbsclienthostname='clienthost';
    if ( $cfgtree->{behaviour} eq "Torque3" ) {
         $pbsclienthostname='pbsserver';
    }
    if ($cfgtree->{masters} && @{$cfgtree->{masters}}[0]){
        foreach ( @{$cfgtree->{masters}} ) {
            $contents.='$' . $pbsclienthostname . ' '.$_."\n";
        };
    } else {
        $self->error("Empty master list");
        return;
    }


    foreach ( @{$cfgtree->{aliases}} ) {
        $contents.='$alias_server_name '.$_."\n";
    }

    foreach ( @{$cfgtree->{pbsclient}} ) {
        $contents.='$pbsclient '.$_."\n";
    }

    foreach ( @{$cfgtree->{varattr}} ) {
        $contents.='$varattr '.$_."\n";
    }

    # create the line(s) with the $restricted directives from the master list
    foreach ( @{$cfgtree->{restricted}} ) {
        $contents .= '$restricted ' . $_ . "\n";
    }

    # additional resources (those without a $) that end up in the config
    my %resources;
    foreach my $resource (@{$cfgtree->{resources}}) {
        my ($a,$v)=split(/:/,$resource,2);
        $resources{$a}=$v;
    }

    # add cpuinfo if defined by user :
    # users can define a list of properties they want to be included?
    # example elements are : "cpu count","model name","cpu MHz","cpu family","model","stepping"...
    if(exists($cfgtree->{cpuinfo})) {
        $self->info("Additional CPUINFO elements exist, adding them as resources to mom config");

        my %tmphash=cpuinfo_hash();
        my %tmphash2;
        for my $elem (@{$cfgtree->{cpuinfo}}) {
            if(defined $tmphash{$elem}) {
                my $prop = $elem;
                #have things more readable
                $prop =~ s/^(model |cpu |)//;
                $prop =~ tr/ /_/;
                #prefix a "cpu_" for all properties except ncpus and ncores
                $prop="cpu_" . $prop unless( $prop =~ m/(^ncores)/) ;
                #$tmphash2{$elem}=$tmphash{$elem}
                $tmphash2{$prop}=$tmphash{$elem};
            }
        }
        # add cpuinfo to resources
        %resources = (%resources, %tmphash2);
    };

    # Define other resources
    foreach ( keys %resources ) {
        $self->info("Additional resource '" . $_ . "' defined");
        my $resource_string = $_;
        if ( defined($resources{$_}) && length($resources{$_}) ) {
            $resource_string .= " " . $resources{$_};
        }
        $contents .= $resource_string . "\n";
    }



    # additional usecp directives
    foreach my $dp ( @{$cfgtree->{directPaths}} ) {
        my $locations = $dp->{locations};
        my $path = $dp->{path};
        $self->debug(1,"Adding direct path \$usecp $locations $path");
        $contents .= '$usecp ' . $locations . " " . $path . "\n";
    }

    ## bulk of all options
    ## regular style
    sub makestring {
        my $arg=shift;
        my $tmp = $cfgtree->{$arg};
        my $res;
        if ( ref($tmp) eq "ARRAY" ) {
            $res=join(',',@{$tmp});
        } else {
            $res=$tmp;
        }
        return $res;
    }
    foreach ( PBSINITIALISATIONVALUES ) {
        $contents .= '$'.$_ . ' ' . makestring($_) . "\n" if ($cfgtree->{$_});
    }
    ## camelcase with mapping
    while ( my ($schemaname, $cfgentry) = each %{&PBSINITIALISATIONVALUESMAP} ) {
        ## regular style is preferred in case of mixing (but silently)
        $contents .= '$'.$cfgentry . ' ' . makestring($schemaname) . "\n" if ($cfgtree->{$schemaname} && (! $cfgtree->{$cfgentry}));
    }

    ## options don't start with $
    foreach ( PBSCLIENTOPTIONS ) {
        $contents .= $_ . ' ' . makestring($_) . "\n" if ($cfgtree->{$_});
    }


    ## behaviour OpenPBS default pushed to schema
    ## This Torque behaviour is from very early Torque version. OpenPBS is best left as default.
    if ( $cfgtree->{behaviour} eq "Torque" ) {
        # add a $pbsservername line
        # assume first master is the real one
        $contents .= '$pbsmastername ' . @{$cfgtree->{masters}}[0] . "\n";
    }

    #
    # Update Torque client configuration file if needed
    #
    LC::Check::directory("$pbsmomdir");

    ## Is this still needed? LC::Check::file probably already does this?
    -e "$pbsmomconf" or ( open PBSMOMCONFFH,">$pbsmomconf" and close PBSMOMCONFFH );
    -f "$pbsmomconf" or $self->Error("$pbsmomconf exists but is not a file");

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

    ## Is this still needed? LC::Check::file probably already does this?
    -e "$srvfile" or ( open SNM,">$srvfile" and close SNM );
    -f "$srvfile" or $self->Error("$srvfile exists but is not a file");

    ## @{$cfgtree->{masters}}[0] checked above
    $result = LC::Check::file( $srvfile,
                               backup => ".old",
                               contents => @{$cfgtree->{masters}}[0],
                               owner => "root",
                               group => "root",
                               mode  => 0644,
                             );
    if ( $result ) {
        $self->log("$srvfile updated");
        $changes += $result;
    }


    # Ensure that the tmpdir exists if it is specified.
    # For torque 2+, this directory must have group write privilege.
    #
    # Bug 28585:
    # Do NOT set the absolute permissions because that may affect other permissions
    # Just ensure that the group can write to $tmpdir
    if ( $cfgtree->{tmpdir} ) {
        my $tmpdir=$cfgtree->{tmpdir};
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
    while ( my ($script, $scriptcontents) = each %{$cfgtree->{scripts}} ) {
        my $fullpath = "$pbsmomdir/$script";
        my $result = LC::Check::file($fullpath,
                                     backup => ".old",
                                     contents => $scriptcontents,
                                     owner => "root",
                                     group => "root",
                                     mode  => SCRIPTPERMS->{$script},
                                    );
        if ( $result ) {
            $self->log("$fullpath updated");
        }
    }

    # restart PBS if it is already running AND the config changed
    if ($changes) {
        if ($cfgtree->{submitonly}) {
            $self->info("Submit only configuration; no checking for any MOM state.");
        } else {
            my $output = CAF::Process->new([$pbsinitscript, "status"], log => $self)->output();
            if ($?) {
                $self->info("Not running (from $pbsinitscript status)");
            } else {
                $self->info("Running, will attempt restart (from $pbsinitscript status)");
                $output = CAF::Process->new([$pbsinitscript, "restart"], log => $self)->output();
                if ($?) {
                    $self->info("Restart failed (output from $pbsinitscript restart: $output)");
                } else {
                    $self->info("Restarted (from $pbsinitscript restart)");
                }
            }
        }    
    };

    return;
}


##########################################################################
sub Unconfigure {
##########################################################################
  my ($self,$config)=@_;

  $self->info("Unconfiguring PBS. Nothing implemented.");

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
        if(exists($cpuinfo{$_}{"physical id"})) {
            $cpus{$cpuinfo{$_}{"physical id"}}=$processor ;
        } else  {
            $cpus{$processor}=$processor ;
        }
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
