# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
############################################################
#
# type definition components/yaim_usersconf
#
#
#
#
#
############################################################

declaration template components/yaim_usersconf/schema;

include { 'quattor/schema' };

type structure_yaim_usersconf_gridusers = {
        "name" : string
        "flag" ? string
};

type structure_yaim_usersconf_gridgroups = {
        "role" : string # "VOMS path"
        "flag" ? string
};

type structure_yaim_usersconf_vo = {
    "name"      : string
    "gridusers"   ? structure_yaim_usersconf_gridusers[]
    "gridgroups"  ? structure_yaim_usersconf_gridgroups[]

};

type ${project.artifactId}_component = {
    include component_type
    "users_conf_file"  ? string # "location of users.conf file"
    "groups_conf_file" ? string # "location of groups.conf file"
    "vo"               ? structure_yaim_usersconf_vo{}

};

bind "/software/components/yaim_usersconf" = ${project.artifactId}_component;


