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

type ${project.artifactId}_component = {
    include component_type
    "users_conf_file"  ? string # "location of users.conf file"
    "groups_conf_file" ? string # "location of groups.conf file"

};

bind "/software/components/yaim_usersconf" = ${project.artifactId}_component;


