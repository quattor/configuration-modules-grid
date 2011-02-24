# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/moab/schema;

include { 'quattor/schema' };

## to be used for USERCFG, GROUPCFG...
type ${project.artifactId}_component_cfg = string[];

type ${project.artifactId}_component_include = {
    'contents' ? string
    'ok' : boolean = true
};

type ${project.artifactId}_component = {
    include structure_component
    'mode'  ? string with match(SELF,'moab|maui')

    'configPath' ? string
    'binPath' ? string
    'configFile' ? string
    
    'sched' ? ${project.artifactId}_component_cfg{}
    'rm' ? ${project.artifactId}_component_cfg{}
    
    'am' ? ${project.artifactId}_component_cfg{}
    
    'id' ? ${project.artifactId}_component_cfg{}
    
    'user' ? ${project.artifactId}_component_cfg{}
    'group' ? ${project.artifactId}_component_cfg{}
    
    'include' ? ${project.artifactId}_component_include{}
    
    'main' : string{}
    'priority' ? string{}
    
};

bind '/software/components/moab' = ${project.artifactId}_component;


