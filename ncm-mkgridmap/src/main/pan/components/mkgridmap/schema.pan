# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/mkgridmap/schema;

include { 'quattor/schema' };

type structure_mkgridmap_local = {
        'cert' : string
        'user' : string
};

type structure_mkgridmap_lcmaps = {
  'flavor'     : string = 'glite' with match(SELF,'edg|glite')
	'gridmapfile' : string = '/opt/edg/etc/lcmaps/gridmapfile'
	'groupmapfile' : string = '/opt/edg/etc/lcmaps/groupmapfile'
};

type ${project.artifactId}_component_entry = {
        'mkgridmapconf' : string
        'format'        : string with (match(SELF, 'edg|lcgdm'))
        'command'       ? string
        'gmflocal'      ? string
        'lcuser'        ? string
        'allow'         ? string
        'deny'          ? string
        'overwrite'     : boolean
        'authURIs'      ? type_hostURI[]
        'locals'        ? structure_mkgridmap_local[]
};

type ${project.artifactId}_component = {
	include structure_component
	'entries'    : ${project.artifactId}_component_entry{}
	'lcmaps'     ? structure_mkgridmap_lcmaps
	'voList'     ? string[]
};

bind '/software/components/mkgridmap' = ${project.artifactId}_component;

