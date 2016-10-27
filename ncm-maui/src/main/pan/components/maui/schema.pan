# ${license-info}
# ${developer-info}
# ${author-info}

declaration template components/maui/schema;

include 'quattor/types/component';

type ${project.artifactId}_component = {
    include structure_component
    'configPath' ? string
    'configFile' ? string
    'contents' ? string
};
