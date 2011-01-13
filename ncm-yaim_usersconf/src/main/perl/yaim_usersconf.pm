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

sub ReadCache($);

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

    my $usecache = 0;
    if ($config->elementExists("$basedir/usecache")){
        $usecache = $config->getElement("$basedir/usecache");
    }
    if ($usecache){
        $self->info("Using cached entries from " . $config->getValue($usersconf)." (if exists...)");
    }
    #
    # users.conf
    #
    if ($config->elementExists($usersconf)){
        my %user_cache = my %gid_cache = ();
        if ($usecache){
             my ($ref1,$ref2) = ReadCache($config->getValue($usersconf));
             %user_cache = %$ref1 if $ref1;
             %gid_cache  = %$ref2 if $ref2;
        }
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
                     my $uid = my $gid = undef;
                     if (exists $user_cache{$name}){
                         ($uid,$gid) = @{$user_cache{$name}};
                         delete $user_cache{$name}; # delete used entries, to obtain minor speedup...
                     }else{
                         ($uid,$gid) = (getpwnam($name))[2,3];
                     }
                     if (not defined $uid or not defined $gid){
                         $self->warn("Cannot get uid/gid belonging to username \"$name\", skipping...");
                         next;
                     }
                     $gid_cache{$gid} ||= getgrgid($gid);
                     my $gnam = $gid_cache{$gid};
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

sub ReadCache($){
    my $cachefile = shift @_;
    my %user_cache = my %gid_cache = ();
    open(C,$cachefile) || return ();
    while(<C>){
        next if /^\s*#/; # skip comments
        # 8957:aliceprd:1395,1395:z2,z2:alice:prd:
        my ($uid,$username,$gid,$groupname) = split(":",$_);
        $gid = (split(",",$gid))[0];
        @{$user_cache{$username}} = ($uid,$gid);
        $gid_cache{$gid} ||= (split(",",$groupname))[0];
    }
    close(C);

    return \%user_cache,\%gid_cache;
}

1;      # Required for PERL modules
