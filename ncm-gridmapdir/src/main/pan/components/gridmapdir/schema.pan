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
	'sharedGridmapdir' ? string
  'owner'            : string = 'root'
  'group'            : string = 'root'
  'perms'            : string = '0755';
};

bind '/software/components/gridmapdir' = ${project.artifactId}_component;
