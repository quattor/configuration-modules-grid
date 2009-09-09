# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/hydraserver/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_instance_type = {   
    "adminpwd"   : string
    "db_name"    : string
    "db_user"    : string
    "db_pass"    : string
    "create"     : string
    "admin"      : string
    "peers"      : string[]
};

type ${project.artifactId}_component = {
    include structure_component
    "instances"          : ${project.artifactId}_component_instance_type{}      
};

bind '/software/components/hydraserver' = ${project.artifactId}_component;
