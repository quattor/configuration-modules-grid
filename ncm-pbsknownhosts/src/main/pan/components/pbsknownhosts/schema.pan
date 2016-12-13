# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/pbsknownhosts/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component = {
    include structure_component
    'configFile' : string = '/opt/edg/etc/edg-pbs-knownhosts.conf'
    'pbsbin' : string = '/usr/bin'
    'nodes' : string = ''
    'keytypes' : string = 'rsa1,rsa,dsa'
    'knownhosts' : string = '/etc/ssh/ssh_known_hosts'
    'knownhostsscript' ? string
    'targets' ? string[]
    'shostsConfigFile' ? string
    'shosts' ? string
    'shostsscript' ? string
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
