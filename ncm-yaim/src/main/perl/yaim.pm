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
# build_yaim_command:   construct the shell command line to run yaim
#
# returns the shell command to execute, or undef if no node types were found
#
# Note: this only supports yaim >= 3.1
#       in particular, support for installation has been dropped
#
sub build_yaim_command {
    my ($self, $cfgtree, $cfgfilename, $nodetypes) = @_;

    #
    # work around for Savannah bug #27577
    # setting LANG should result in the sorting order which yaim expects
    #
    # default language setting (work around for Savannah bug #27577)
    my $LANG="en_US.UTF-8";
    $ENV{"LANG"}= $LANG;
    my $ENVSET = "export LANG=$LANG;";

    #
    # The YAIM command to execute
    #
    my $yaim_script;
    if ( exists $cfgtree->{'conf'}->{'YAIM_SCRIPT'} ) {
        $yaim_script = $cfgtree->{'conf'}->{'YAIM_SCRIPT'};
    }
    elsif ( exists $cfgtree->{'conf'}->{'YAIM_HOME'} ) {
        $yaim_script = $cfgtree->{'conf'}->{'YAIM_HOME'} . '/bin/yaim';
    }
    else {
        # default
        $yaim_script = '/opt/glite/yaim/bin/yaim';
    }

    # verify that the command can be executed
    if ( ! -x $yaim_script ) {
        $self->error("Yaim script $yaim_script not executable: $!");
        return undef;
    }

    my $yaimcmd = $ENVSET . $yaim_script . " -c -s " . $cfgfilename;

    # Support for an ordered node list (Savannah bug #47269)
    my $count = 0;
    foreach my $req_type ( @{$cfgtree->{'nodetype'}} ) {
        my $found = 0;
        # there is no consistency in naming of node types, so consider
        # node type glite-X equivalent to node type X
        $req_type =~ s/^glite-//;
        foreach my $def_type ( @{$nodetypes} ) {
            if ( $req_type eq $def_type ) {
                # requested node type is defined; add it to the yaim command 
                $yaimcmd .= " -n \"$req_type\"";
                $found = 1;
                last;
            }
        }
        $self->info("No node type definition found for '$req_type' on this host") if ( ! $found );
        $count += $found;
    }

    # if no node types found, clear the command
    if ( $count == 0 ) {
        $self->warn("no known node types defined under nodetype, no configuration was applied");
        $yaimcmd = undef;
    }
    return $yaimcmd;
}


#
# get_available_node_types: determine the defined node types
#
# return: array of unique node types represented as strings
#
sub get_available_node_types() {
    my ($self, $nodeinfodir) = @_;
    my @nodetypes = ();

    # Search all files in node-info.d for the pattern
    # <NODETYPE>_FUNCTIONS=
    if ( ! opendir DIR, $nodeinfodir ) {
        $self->error("$!: $nodeinfodir");
        return @nodetypes;
    }
    while (defined(my $file = readdir(DIR))) {
        $file = $nodeinfodir."/".$file;
        if ( open FILE, $file ) {
            push @nodetypes, grep { s/^([\w_]+)_FUNCTIONS=.*$/$1/; } <FILE>;
        }
        else {
            $self->warn("$!: $file");            
        }
        close FILE;
    }
    closedir DIR;

    # ugly fix: Yaim expects node type lcg-CE, but the files in node-info.d
    #           for the lcg-CE start with prefix CE_
    #           So replace CE by lcg-CE
    map( s/^CE$/lcg-CE/, @nodetypes );

    # prepare return: a sorted list of unique node types without trailing newline
    chomp @nodetypes;               # remove all trailing newlines
    my %saw;                        # temporary hash used to find unique type
    return grep(!$saw{$_}++, @nodetypes);
}


#
# get_secret_configuration:     read secret configuration from file
#
# return:                       string representing the configuration
#                               empty if there is no secret configuration
#
sub get_secret_configuration {
    my ($self, $cfgtree) = @_;

    my $cfg = "";       # string containing the secret configuration

    my $sec_file_name="/etc/yaim.secretpasswords";
    if ( exists $cfgtree->{'SECRET_PASSWORDS'} ) {
        $sec_file_name = $cfgtree->{'SECRET_PASSWORDS'};
    } 
    if ( -e $sec_file_name ){
        $cfg .= "\n#\n# yaim.secretpasswords:\n#\n";
        $cfg .= file_contents($sec_file_name);
    }
    return $cfg;
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

        # Fix Savannah bug #15494 (read restrictions for the config file)
        if (!(chmod 0600, $cfgfilename)){
            $self->warn("Cannot change file mode of $cfgfilename to 0600");
        }
        $self->info ("updated $cfgfilename");
    }
    return($update);
}


#
# Take a VO and convert it into a form suitable for a environment variable.
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
#
# return:           Text that contains the Yaim variable definitions related to
#                   the queue configuration.
#
sub getQueueConfig {
    my ($self, $cfgtree) = @_;

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
    if ( exists $cfgtree->{'conf'}  && exists $cfgtree->{'conf'}->{'QUEUES'} ) {
        my $val = $cfgtree->{'conf'}->{'QUEUES'};
       
        foreach my $queue ( split(/\s+/, $val) ) {
            if ( ! defined $queues{$queue} ) {
                $queues{$queue} = "";
            }
        }
    }

    # Collect input from VO-specific settings
    # Although the queues are in the (unspecified) schema of this component 
    # connected to a VO, they are no longer part of the VO config in Yaim.
    my $votree = &get_vo_tree($self, $cfgtree);
    if ( $votree ) {
        foreach my $key (sort keys %{$votree}) {
            if ( exists $votree->{$key}->{'services'}->{'QUEUES'} ) {
                my $list = $votree->{$key}->{'services'}->{'QUEUES'};
                my $vo = $votree->{$key}->{'name'};

                $self->verbose("list of queues for VO $vo = $list");

                my @vals = split('\s',$list);
                foreach my $val (@vals){
                    $queues{$val} .= "$vo";        # add VO name to the queue
                  
                    # If defined, the specific VOMS groups and roles
                    if ( $votree->{$key}->{'services'}->{'groupsroles'} ) {
                        my $groupsroles = $votree->{$key}->{'services'}->{'groupsroles'};
                        chomp $groupsroles;
                        $queues{$val} .= " $groupsroles ";
                    }
                }
            }
        }
    }

    # Construct the output for the variables QUEUES and <QUEUE>_GROUP_ENABLE
    my $cfg = "\n#\n# Queue configuration\n#\n";
    if ( scalar %queues ) {
        $cfg .="QUEUES=\"".join(' ', keys %queues)."\"\n";
        foreach my $qvar ( sort keys %queues ) {
            my $varname = uc($qvar)."_GROUP_ENABLE";
            $cfg .= "${varname}=\"".$queues{$qvar}."\"\n";
        }
    }
    return($cfg);
}


#
# get_section_config:   convert a (sub)section of the configuration tree
#                       into a string representation
#
sub get_section_config {
    my ($self, $section_tree, $section_name, $prefix, $fields) = @_;

    my $cfg = "";

    if ( defined $section_tree ) {
        $cfg = "\n#\n# section $section_name\n#\n" if ( $section_name );
        if ( ! $fields ) {
            # no list fields; use all defined elements
            $fields = [ sort keys %{$section_tree} ];
        }
        foreach my $key (sort keys %{$section_tree}) {
            my $value = $section_tree->{$key};
            next if ( ref $value eq "HASH" || ref $value eq "ARRAY" );
            $cfg .= uc($prefix.$key) . "=\"$value\"\n";
        }
    }

    return $cfg;
}


#
# get_vo_tree:  find the VO base definition location
#
# return:       reference to a hash of the VO definition tree
#
sub get_vo_tree {
    my ($self, $cfgtree) = @_;

    if ( exists( $cfgtree->{'vo'} ) ) {
        return $cfgtree->{'vo'};
    }
    elsif ( exists $cfgtree->{'system'} && exists $cfgtree->{'system'}->{'vo'} ) {
        return $cfgtree->{'system'}->{'vo'};
    }
    $self->error("Failed to find a VO base");
    return undef;
}


#
# get_vo_config:    Process the VO configuration tree.
#                   If the 3rd parameter (href) is defined, this function works in
#                   "use_vo_d" mode, meaning:
#                   * the VO configuration is stored in the hash referenced by $href,
#                     with key VO name and value the full config string for that VO
#                   * the VO configuration is not contained in the return string
#                   * variable names in the result do not start with prefix VO_<VONAME>_
#                   The configuration strings -either the return string or those in 
#                   the hash- can directly be written to Yaim's configuration files.
#                   
# return:           string holding the Yaim configuration based on the VO settings
#
sub get_vo_config {
    my ($self, $cfgtree, $href) = @_;

    my @vos;
    my @lfc_local;
    my @lfc_central;

    my $vo_cfg;
    $vo_cfg = "\n#\n# VO configuration\n#\n" if ( defined $href );
    
    my $votree = &get_vo_tree($self, $cfgtree);
    if ( defined $votree ) {
        foreach my $key (sort keys %{$votree} ) {
            my $vo = $votree->{$key}->{'name'};
            my $vo_for_env = &vo_for_env($vo);
            
            push(@vos,$vo);
            if ( exists $votree->{$key}->{'services'}->{'LFC'} ){
                my $range = $votree->{$key}->{'services'}->{'LFC'};
                if (lc($range) eq "local") { push (@lfc_local, $vo); }
                if (lc($range) eq "central") { push (@lfc_central, $vo); }
            }

            my $var_prefix = '';      # no prefix
            my $section_comment = ''; # no comment
            if ( defined $href ) {
                $section_comment = "VO $vo configuration";
            }
            else {
                $var_prefix = "VO_${vo_for_env}_";        # prefix VO_<VONAME>_ 
            }
            my $cfgstr = &get_section_config($self, $votree->{$key}->{'services'}, 
                                             $section_comment, $var_prefix, undef);
            if ( defined $href ) {
                $$href{$vo} = $cfgstr;
            }
            else {
                $vo_cfg .= $cfgstr;
            }
        }

        # If we've been given an ordered list of VOs, use it instead of the
        # one we've just created
        if ( exists $cfgtree->{VOs} ) {
            my @ordered_vos = $cfgtree->{VOs}->getList();
            $vo_cfg .= 'VOS="'.join (' ',map($_->getValue(),@ordered_vos)) ."\"\n";
        } else {
            $vo_cfg .= 'VOS="'.join (' ',@vos) ."\"\n";
        }
        $vo_cfg .= $vo_cfg unless ( defined $href );
        $vo_cfg .= "\n#\n# LFC configuration\n#\n";
        $vo_cfg .= 'LFC_CENTRAL="'.join(' ',@lfc_central)."\"\n";
        $vo_cfg .= 'LFC_LOCAL="'.join(' ',@lfc_local)."\"\n";
    } else {
        $self->warn("no VO information defined");
    }
    return $vo_cfg;
}



#
# get_bdii_regions_config:  dedicated processing of the BDII_REGIONS
#
# return:                   string containing BDII regions configuration
#
sub get_bdii_regions_config {
    my ($self, $cfgtree) = @_;

    my $cfgstr = '';

    # Just verify that the region tag is defined under conf
    # Its value was already appended to the configuration file 
    # when the variables under conf were processed
    #
    # When ncm-yaim will use a proper schema definition (incompatible with v 1.x)
    # this function should actually do something again!
    if ( exists $cfgtree->{'conf'}->{'BDII_REGIONS'} ){
        my $val = $cfgtree->{'conf'}->{'BDII_REGIONS'};
        $self->verbose("LIST of BDII REGIONS = \"$val\"\n");
        my @region_list = split('\s+',$val);
        foreach my $region (@region_list){
            $self->verbose("Region \"$region\"\n");
            if ($region =~ /-/){
                $self->error("Character \"-\" not allowed in the region tag \"$region\". Yaim will break");
            }
            my $region_tag = "BDII_". uc($region)."_URL";
            $self->verbose("Region tag \"$region_tag\"\n");

            if ( exists $cfgtree->{'conf'}->{$region_tag} ) {
                $self->verbose("URL for $region_tag found: \"$cfgtree->{'conf'}->{$region_tag}\"\n");
            }
            else{
                $self->error("No URL specified for region $region_tag");
            }
        }
    }
    return $cfgstr;
}


#
# get_close_se_config:  process information under closeSE
#
# return:               string holding the configuration
#
sub get_close_se_config {
    my ($self, $cfgtree) = @_;

    my $cfgstr = '';

    if ( exists $cfgtree->{'CE'}->{'closeSE'} ) {
        my @ses;
        my @se_hosts;
        my $se_cfg = "";
        $cfgstr = "\n#\n# section close SE\n#\n";
        foreach my $se (sort keys (%{$cfgtree->{'CE'}->{'closeSE'}})) {
            push( @ses, $se );
            my @se_fields = qw(HOST ACCESS_POINT);
            $se_cfg .= &get_section_config($self, $cfgtree->{'CE'}->{'closeSE'}->{$se},
                                             '', "CE_CLOSE_${se}_", undef);
            push (@se_hosts, $cfgtree->{'CE'}->{'closeSE'}->{$se}->{'HOST'});
        }
        $cfgstr .= 'CE_CLOSE_SE="'.uc(join (' ',@ses)) ."\"\n";
        $cfgstr .= 'SE_LIST="'.join (' ',@se_hosts) ."\"\n";
        $cfgstr .= $se_cfg;
    }
    return $cfgstr;
}


#
# create_user_groups_conf:      create users and/or groups configuration filesn if needed
#
sub create_user_groups_conf {
    my ($self, $cfgtree, $yaimhome) = @_;

    # Since gLite 3.0, these files are mandatory for a YAIM configuration
    # 1) Check for a creating program in /usr/libexec and run it, if it exists 
    # 2) Check for the existance of the users.conf resp. group.conf file, and
    #    if it does not exist, copy the default one
    #
  
    my $yaimexampledir=$yaimhome.'/examples/';

    # User.conf
    #
    my $usersconf='$yaimhome/users.conf';
    if ( exists $cfgtree->{'conf'}->{'USERS_CONF'} ) {
        $usersconf = $cfgtree->{'conf'}->{'USERS_CONF'};
    }

    #
    # Create a USERS_CONF file, if script exists:
    #
    system("[ -x /usr/libexec/create-YAIM-users_conf ] && /usr/libexec/create-YAIM-users_conf $usersconf");
  
    # Copy the default users.conf if no file exists
    #
    system("[ -e $usersconf ] || cp $yaimexampledir/users.conf $usersconf");

    # Group.conf
    #
    my $groupsconf='$yaimhome/groups.conf';
    if ( exists $cfgtree->{'conf'}->{'GROUPS_CONF'} ) {
        $groupsconf = $cfgtree->{'conf'}->{'GROUPS_CONF'};
    }

    #
    # Create a GROUPS_CONF file, if script exists:
    #
    system("[ -x /usr/libexec/create-YAIM-groups_conf ] && /usr/libexec/create-YAIM-groups_conf $groupsconf");

    # Copy the default groups.conf file, if no file exists
    #
    system("[ -e $groupsconf ] || cp $yaimexampledir/groups.conf $groupsconf");
}



#
# write_configuration:  Write all configuration files
#                       If an error occurs, file SITEINFO is renamed with suffix .failed
#                       to force Yaim to run again
#
sub write_configuration {
    my ($self, $cfgtree, $cfgfile, $vo_d_ref, @nodetypes) = @_;

    # update the config file if there are changes
    # or if the force flag was set
    my $update = 0;
    if ( $cfgtree->{'force'} ) {
        $update = $cfgtree->{'force'};
        $self->info("Forcing the execution of the Yaim command was enabled");
    }

    # yaim config file name
    my $cfgfilename = '/etc/lcg-quattor-site-info.def';
    if ( exists $cfgtree->{'SITE_INFO_DEF_FILE'} ){
        $cfgfilename = $cfgtree->{'SITE_INFO_DEF_FILE'};
    } 

    my $result = &write_cfg_file($self, $cfgfilename, $cfgfile);
    if ( $result != -1 ) {
        $update ||= $result;

        if ( defined $vo_d_ref ) {
            # get basedir for SITE_INFO_DEF and check for existence of dir vo.d
            my $basedir = dirname($cfgfilename);
            if ( ! -d "$basedir/vo.d" ) {
                $self->info("Creating directory $basedir/vo.d");
                mkdir "$basedir/vo.d", "0777" or $self->error("$!");
                $result = -1;
            }

            if ( $result != -1 ) {
                # loop over all entries in %vo_d_cfg and write the contents to the individual files
                foreach my $voname (keys %{$vo_d_ref}) {
                    # compare contents via function that contains the above
                    $result = &write_cfg_file($self, "$basedir/vo.d/$voname", $$vo_d_ref{$voname});
                    last if ( $result == -1 );      # no need to continue on failure
                    $update ||= $result;
                }
            }
        }
    }

    if ( $result != -1 ) {
        if ( $update ) {
            my $cmd = &build_yaim_command($self, $cfgtree, $cfgfilename, \@nodetypes);
            if ( $cmd ) {
                # Should NCM run YAIM or just print the action?
                if ( $cfgtree->{'configure'} ) {
                    my $retval = $self->run_command($cmd);
                    $result = -1 if ( $retval );
                } else {
                    $self->info("configure = false => Do not run : \"".$cmd."\".");
                }
            }      
        } else {
           $self->info("no changes in $cfgfilename, no action taken");
        }
    }

    my $failed_cfg = $cfgfilename . ".failed";
    if ( $result == -1 ) {
        # Yaim completed with errors; rename config file to force running again
        $self->info("Renaming configuration file to $failed_cfg");
        LC::File::move($cfgfilename, $failed_cfg);
    }
    else {
        # Yaim completed without errors; remove an old "failed" configuration file
        if ( -f $failed_cfg ) {
            $self->debug(1, "Deleting $failed_cfg");
            LC::File::remove($failed_cfg);
        }
    }
}


##########################################################################
sub Configure($$@) {
##########################################################################

    my ($self, $config) = @_;

    # Define base paths
    my $base = "/software/components/yaim";
    my $cfgroot = $config->getElement($base);
    my $cfgtree = $cfgroot->getTree;


    #
    # get the yaim version - if defined
    #
    if ( exists $cfgtree->{'conf'}->{'YAIM_VERSION'} ) {
        my $yaimversion = $cfgtree->{'conf'}->{'YAIM_VERSION'};
        $yaimversion = $1 if ($yaimversion =~ /^(\d\.\d)/);
        if ( $yaimversion < 3.1 ) {
            $self->error("Detected old and unsupported Yaim version: $yaimversion");
            return;
        }
    }

    # yaim directory
    my $yaimhome = $cfgtree->{'conf'}->{'YAIM_HOME'} || '/opt/glite/yaim';

    #
    # determine the available node types based on the information under node-info.d
    #
    my $yaimnodeinfo = $yaimhome . "/node-info.d";
    my @nodetypes = &get_available_node_types($self, $yaimnodeinfo);
    if ( scalar @nodetypes == 0 ) {
      $self->error("Could not find any node types in $yaimnodeinfo");
      return;
    }
    $self->debug(1, "Node types defined on this host: " . join(',', @nodetypes));
    

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
    my $use_vo_d = $cfgtree->{'USE_VO_D'} || 0;
    $self->debug(3, "Will " . ($use_vo_d ? "" : "not ") . "use vo.d");
    
    #
    # fields under conf
    #
    my $conf_str = &get_section_config($self, $cfgtree->{'conf'}, "", "", undef);
    unless ($conf_str) {
        $self->error("no known configuration keys found under $base/conf, no configuration was applied");
        return;
    }
    $cfgfile .= $conf_str;
  
    # Loop on BDII REGIONS
    $cfgfile .= &get_bdii_regions_config($self, $cfgtree);

    #
    # loop over FTA specific info
    # The possible keys are not specified. Therefore no predefined list of KEYs.
    #
    $cfgfile .= &get_section_config($self, $cfgtree->{'FTA'}, "FTA configuration", "FTA_", undef);
  
    # loop over FTM specific info
    # The possible keys are not specified. Therefore no predefined list of KEYs.
    $cfgfile .= &get_section_config($self, $cfgtree->{'FTM'}, "FTM configuration", "FTM_", undef);
  
    # loop over FTS specific info
    $cfgfile .= &get_section_config($self, $cfgtree->{'FTS'}, "FTS configuration", "FTS_", undef);
  
    # loop over VOMS-ADMIN specific info
    $cfgfile .= &get_section_config($self, $cfgtree->{'VOMS_ADMIN'}, "VOMS admin configuration",
                                  "VOMS_ADMIN_", undef);

    #
    # loop over CE specific info
    #
    $cfgfile .= &get_section_config($self, $cfgtree->{'CE'}, "CE configuration",
                                    "CE_", undef);

    $cfgfile .= &get_close_se_config($self, $cfgtree);     

    # Append queue-related configuration
    $cfgfile .= &getQueueConfig($self, $cfgtree);
  
    # now, loop over VO's for SW_DIR, DEFAULT_SE etc.
    my %vo_d_cfg;
    my $vo_d_ref = undef;           # default is undef, i.e. do NOT use vo.d/*
    $vo_d_ref = \%vo_d_cfg if ( $use_vo_d );
    $cfgfile .= &get_vo_config($self, $cfgtree, $vo_d_ref);
  
    # SCAS
    $cfgfile .= &get_section_config($self, $cfgtree->{'SCAS'}, "SCAS server configuration",
                                    "", undef);

    # GLEXEC
    $cfgfile .= &get_section_config($self, $cfgtree->{'GLEXEC'}, "GLEXEC_wn configuration",
                                    "", undef);

    # Free variables under .../yaim/extra, as requested 
    $cfgfile .= &get_section_config($self, $cfgtree->{'extra'}, "free configuration", "", undef);

    # Create user.conf and/or groups.conf
    &create_user_groups_conf($self, $cfgtree, $yaimhome);

    # Check for a 'secure' file in /etc and add the contents
    $cfgfile .= &get_secret_configuration($self, $cfgtree);
 
    # Recreate the site-info.def file, if there were changes 
    &write_configuration($self, $cfgtree, $cfgfile, $vo_d_ref, @nodetypes);

    return;
}

1;      # Required for PERL modules
