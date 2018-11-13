# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/vomsclient/schema;

include 'quattor/schema';
include 'pan/types';

type structure_vomsclient_voms_info = {
    @{The complete name of the VO, if the 'vos' key is an alias name. This
    property is deprecated : it is recommended to use the complete name of the
    VO as 'vos' key.}
    'name' ? string
    @{The complete hostname of the VOMS server.}
    'host' : type_fqdn
    @{The port number of the VOMS server.}
    'port' : type_port
    @{The certificate for the server.}
    'cert' : string
    @{The expiring certificate for the server. This allows smooth transition
    between 2 certificates.}
    'oldcert' ? string
    @{DN of VOMS server certificate.}
    'DN' ? string
    @{DN of VOMS server certificate issuer.}
    'issuer' ? string
};

type ${project.artifactId}_component = {
    include structure_component
    @{Use LSC format instead of certificate to configure vomsCertsDir.}
    'lscfile' ? boolean
    @{The directory to write the VOMS server certificates into. If the
    directory doesn't exist, it is created. It will remove all managed
    files and create new ones each time the configuration is done.}
    'vomsCertsDir' ? string
    @{The directory to write the VOMS server parameters into. If the
    directory doesn't exist, it is created. It will remove all managed
    file and create new ones each time the configuration is done.}
    'vomsServersDir' ? string
    @{This is a named list of VOMS VO information. Each key should be the
    VO name. The value is a list of dict: each dict describes one VOMS server
    supporting the VO.}
    'vos' ? structure_vomsclient_voms_info[]{}
};

bind '/software/components/vomsclient' = ${project.artifactId}_component;
