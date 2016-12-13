# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/gsissh/schema;

include { 'quattor/schema' };
include { 'pan/types' };

type structure_gsissh_server = {
    'port' : type_port
    'options' ? string{}
};

type structure_gsissh_client = {
    'options' ? string{}
};

type ${project.artifactId}_component = {
    include structure_component
    'globus_location' ? string
    'gpt_location' ? string
    'server' ? structure_gsissh_server
    'client' ? structure_gsissh_client
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;

