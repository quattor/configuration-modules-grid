# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/lbconfig/schema;

include 'quattor/schema';

type structure_index_list = string[];

type ${project.artifactId}_component = {
    include structure_component
        'configFile' : string = 'edg_wl_query_index.conf'
        'indicies' : structure_index_list{} = dict('system', list('owner', 'location', 'destination'))
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
