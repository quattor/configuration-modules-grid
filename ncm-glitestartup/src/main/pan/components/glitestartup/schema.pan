# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/glitestartup/schema;

include { 'quattor/schema' };

include { 'pan/types' };

type ${project.artifactId}_component_service = {
  'args' ? string = ''
};

type ${project.artifactId}_component_post_restart = {
  'cmd'            : string
  'expectedStatus' ? long
};

type ${project.artifactId}_component = {
  include structure_component

  'configFile'      : string = '/opt/glite/etc/gLiteservices'
  'initScript'      : string = '/etc/rc.d/init.d/gLite'
  'restartEnv'      ? string[]
  'postRestart'     ? ${project.artifactId}_component_post_restart[]
  'restartServices' ? boolean
  'createProxy'     : boolean = true
  'scriptPaths'     : string[] = list('/opt/glite/etc/init.d')
  'services'        : ${project.artifactId}_component_service{}
};

bind '/software/components/glitestartup' = ${project.artifactId}_component;
