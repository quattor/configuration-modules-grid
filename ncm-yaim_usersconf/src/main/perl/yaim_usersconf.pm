# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
package NCM::Component::yaim_usersconf;

use strict;
use NCM::Component;
use File::Path;
use File::Basename;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;

##########################################################################
# Global variables
##########################################################################
my $basedir    = "/software/components/yaim_usersconf";
my $usersconf  = $basedir . "/users_conf_file";
my $groupsconf = $basedir . "/groups_conf_file";
my $infobyvo   = $basedir . "/vo";

##########################################################################
sub Configure($$@) {
##########################################################################

    my ($self, $config) = @_;

    #
    # users.conf
    #
    if ($config->elementExists($usersconf)){
        my $vo = $config->getElement("${infobyvo}");
        my $result = "";
        while ($vo->hasNextElement()) {
            my $voname = $vo->getNextElement()->getName();
            if ($config->elementExists("${infobyvo}/$voname/gridusers")){
                 my $user_list = $config->getElement("${infobyvo}/$voname/gridusers");
                 while ($user_list->hasNextElement()) {
                     my $index = $user_list->getNextElement()->getName();
                     my $path = "${infobyvo}/$voname/gridusers/$index";
                     my $name = my $flag = undef;
                     if ($config->elementExists("$path/name")){
                         $name = $config->getValue("$path/name");
                     }
                     if ($config->elementExists("$path/flag")){
                         $flag = $config->getValue("$path/flag");
                     }
                     my ($uid,$gid) = (getpwnam($name))[2,3]; 
                     if (not defined $uid or not defined $gid){
                         $self->warn("Cannot get uid/gid belonging to username \"$name\", skipping...");
                         next;
                     }
                     my $gnam = getgrgid($gid);
                     if (not defined $gnam){
                         $self->warn("Cannot get group name belonging to group id \"$gid\", skipping...");
                         next;
                     }
		     if ($flag && ($gid =~ /^\d+$/)){
			 # special case: no secondary gid but flag defined so we reuse the primary
			 $result .= join(":",$uid,$name,"${gid},${gid}","${gnam},${gnam}",$voname,$flag) . ":\n";
		     } else {
			 $flag ||= "";
			 $result .= join(":",$uid,$name,$gid,$gnam,$voname,$flag) . ":\n";
		     }
                 }
            }
        }
        $result ||= "#\n# Empty file, do not remove!!\n#\n#         best regards, yaim_usersconf\n#\n";
        my $cfgfile = $config->getValue($usersconf);
        mkpath(dirname $cfgfile,1,0755);
        if (not open(CFGFILE,"> $cfgfile")){
            $self->error("cannot open $cfgfile for writing: $!");
            return;
        }
        print CFGFILE $result;
        close(CFGFILE);
        $self->info("Successfully written \"$cfgfile\"");
    }else{
        $self->info("no location for users.conf file defined, skipping...");
    }

    #
    # groups.conf
    #
    if ($config->elementExists($groupsconf)){
        my $vo = $config->getElement("${infobyvo}");
        my $result = "";
        while ($vo->hasNextElement() ) {
            my $voname = $vo->getNextElement()->getName();
            if ($config->elementExists("${infobyvo}/$voname/gridgroups")){
                 my $group_list = $config->getElement("${infobyvo}/$voname/gridgroups");
                 while ($group_list->hasNextElement()) {
                     my $index = $group_list->getNextElement()->getName();
                     my $path = "${infobyvo}/$voname/gridgroups/$index";
                     my $role = my $flag = undef;
                     if ($config->elementExists("$path/role")){
                         $role = $config->getValue("$path/role");
                     }else{
                         $self->warn("Cannot find \"$path/role\", skipping...");
                         next;
                     }
                     if ($config->elementExists("$path/flag")){
                         $flag = $config->getValue("$path/flag");
                     }
                     $flag ||= "";
                     $result .=  join(":",$role,"","",$flag) . ":\n";
                 }
            }
        }
        $result ||= "#\n# Empty file, do not remove!!\n#\n#         best regards, yaim_usersconf\n#\n";
        my $cfgfile = $config->getValue($groupsconf);
        mkpath(dirname $cfgfile,1,0755);
        if (not open(CFGFILE,"> $cfgfile")){
            $self->error("cannot open $cfgfile for writing: $!");
            return;
        }
        print CFGFILE $result;
        close(CFGFILE);
        $self->info("Successfully written \"$cfgfile\"");
    }else{
        $self->info("no location for groups.conf file defined, skipping...")
    }
    return;
}

1;      # Required for PERL modules
