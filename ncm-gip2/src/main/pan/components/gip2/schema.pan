# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/gip2/schema;

include { 'quattor/schema' };
include { 'pan/types' };

type structure_gip2_attribute = string[];

type structure_gip2_ldif = {
    'template'              : string
    'ldifFile'              : string
    'entries'               : structure_gip2_attribute{}{}
    'staticInfoArgs'        ? string
};

type structure_gip2_standardOutput = {
    'command'               : string = '/bin/echo'
    'arguments'             : string = '-n'
};

type ${project.artifactId}_component = {
    include structure_component
    'user'                  : string
    'group'                 : string = 'root'
    'flavor'                : string = 'lcg' with match(SELF,'lcg|glite')
    'basedir'               : string
    'etcDir'                ? string
    'ldifDir'               ? string
    'pluginDir'             ? string
    'providerDir'           ? string
    'workDirs'              ? string[]
    'staticInfoCmd'         : string
    'bdiiRestartAllowed'    : boolean = true

    'confFiles'             ? string{}
    'ldif'                  ? structure_gip2_ldif{}
    'plugin'                ? string{}
    'provider'              ? string{}
    'scripts'               ? string{}
    'stubs'                 ? structure_gip2_attribute{}{}{}
    'standardOutput'        ? structure_gip2_standardOutput{}
    'external'              ? string[]
};

bind '/software/components/gip2' = ${project.artifactId}_component;
