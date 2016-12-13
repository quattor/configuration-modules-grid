# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/wmsclient/schema;

include 'quattor/schema';

type ${project.artifactId}_component_mw_ce_attrs = {
    'rank' ? string
    'rankMPI' ? string
    'requirements' ? string
};

type ${project.artifactId}_component_mw_def_attrs = {
    'defaultSchema' ? string = 'Glue'
    'CEAttrs' ? ${project.artifactId}_component_mw_ce_attrs{}
    'defaultVO' ? string = 'unspecified'
    'errorStorage' ? string = '/tmp'
    'loggingDestination' ? string
    'listenerPort' ? type_port = 44000
    'listenerStorage' ? string = '/tmp'
    'loggingLevel' ? long = 0
    'loggingSyncTimeout' ? long = 30
    'loggingTimeout' ? long = 30
    'NSLoggerLevel' ? long = 0
    'outputStorage' ? string = '${HOME}/JobOutput'
    'retryCount' ? long = 3
    'statusLevel' ? long = 0
};

type ${project.artifactId}_component_mw_entry = {
    'active' : boolean = true
    'configDir' ? string
    'classAdsHelper' ? string
    'defaultAttrs' ? ${project.artifactId}_component_mw_def_attrs
};

type ${project.artifactId}_component = {
    include structure_component
    'edg' ? ${project.artifactId}_component_mw_entry
    'glite' ? ${project.artifactId}_component_mw_entry
    'wmproxy' ? ${project.artifactId}_component_mw_entry
};

bind '/software/components/wmsclient' = ${project.artifactId}_component;


