# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/vomsclient/schema;

include 'quattor/schema';
include 'pan/types';

type structure_vomsclient_voms_info = {
    'name' ? string
    'host' : type_fqdn
    'port' : type_port
    'cert' : string
    'oldcert' ? string
        'DN' ? string
        'issuer' ? string
};

type ${project.artifactId}_component = {
    include structure_component
    'lscfile' ? boolean
    'vomsCertsDir' ? string
    'vomsServersDir' ? string
    'vos' ? structure_vomsclient_voms_info[]{}
};

bind '/software/components/vomsclient' = ${project.artifactId}_component;

