# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/gridmapdir/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component = {
	include structure_component
	'gridmapdir'       : string 
	'poolaccounts'     : long(0..0){}
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
