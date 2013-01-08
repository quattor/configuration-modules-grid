# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/frontiersquid/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_type = {
    include structure_component
        'rpmhome'   : string = '/'
        'postinstall' : string = '/etc/squid/postinstall'
        'squidconf' : string = '/etc/squid/squidconf'
	'username'  : string = 'squid'
	'group'     : string = 'squid'
	'networks'   : string = '0.0.0.0/32'
	'cache_mem' : long = 128
	'cache_dir' : long = 10000
};

bind "/software/components/frontiersquid" = ${project.artifactId}_component_type;

