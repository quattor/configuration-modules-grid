# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/frontiersquid/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_type = {
    include structure_component
	'username'  : string = 'squid'
	'group'     : string = 'squid'
	'networks'   : string
	'cache_mem' : long = 128
	'cache_dir' : long = 40000
};

bind "/software/components/frontiersquid" = ${project.artifactId}_component_type;

