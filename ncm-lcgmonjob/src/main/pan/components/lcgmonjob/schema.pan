# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/lcgmonjob/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component = {
    include structure_component
    'EDG_LOCATION' : string
    'LCG_LOCATION' : string
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;


