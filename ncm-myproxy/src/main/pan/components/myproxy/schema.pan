# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/myproxy/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component_dn_types = {
  'renewers' ? string[]
  'retrievers' ? string[]
  'keyRetrievers' ? string[]
  'trustedRetrievers' ? string[]
};

type ${project.artifactId}_component = {
	include structure_component
	'flavor' : string = 'edg' with match(SELF,'^edg|glite$')
	'confFile' ? string = 'opt/edg/etc/edg-myproxy.conf'
  'trustedDNs' ? string[]
  'authorizedDNs' ? ${project.artifactId}_component_dn_types
  'defaultDNs' ? ${project.artifactId}_component_dn_types
};

bind '/software/components/myproxy' = ${project.artifactId}_component;


