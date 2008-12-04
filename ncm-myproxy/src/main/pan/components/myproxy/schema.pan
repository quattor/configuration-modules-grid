# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/myproxy/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component = {
	include structure_component
        'trustedDNs' ? string[]
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;


