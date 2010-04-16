# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
# Coding style: emulate <TAB> characters with 4 spaces, thanks!
################################################################################


declaration template components/pbsclient/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_pathmapping_type = {
    "locations" : string
    "path"      : string
};

type ${project.artifactId}_component_scripts_type = {
    "prologue"          ? string
    "epilogue"          ? string
    "prologue.user"     ? string
    "epilogue.user"     ? string
    "prologue.parallel" ? string
};

type ${project.artifactId}_component_type = {
    include structure_component
    "masters"   : string[]
    "resources" ? string[]
    "tmpdir"	? string
    "restricted" ? string[]
    "logEvent"	? long
    "idealLoad"	? double
    "maxLoad"	? double
    "directPaths" ? ${project.artifactId}_component_pathmapping_type[]
    "cpuTimeMultFactor" ? double
    "wallTimeMultFactor" ? double
    "prologAlarmSec" ? long
    "configPath" ? string
    "behaviour" ? string with match (self,'OpenPBS|Torque')
    "nodeCheckScriptPath" ? string
    "nodeCheckIntervalSec" ? long
    "initScriptPath" ? string
    "scripts" ? ${project.artifactId}_component_scripts_type
    "cpuinfo" ? string[]
    "checkpoint_interval" ? long
    "checkpoint_script" ? string
    "restart_script" ? string
    "checkpoint_run_exe" ? string
    "remote_checkpoint_dirs" ? string
    "max_conn_timeout_micro_sec" ? long
};


bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
