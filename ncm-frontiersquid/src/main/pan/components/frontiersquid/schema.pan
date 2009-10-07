# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/frontiersquid/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_type = {
    include structure_component
	'home'      : string = '/home/dbfrontier'
	'username'  : string = 'dbfrontier'
	'group'     : string = 'dbfrontier'
	'networks'   : string[]
	'servers'   : string[]
	'cache_mem' : long = 2000
	'cache_dir' : long = 20000
};

bind "/software/components/frontiersquid" = ${project.artifactId}_component_type;

