# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/maui/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component = {
	include structure_component
        'configPath' ? string
        'configFile' ? string
        'contents' ? string
};

bind '/software/components/maui' = ${project.artifactId}_component;


