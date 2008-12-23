# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/myproxy/schema;

include { 'quattor/schema' };

type ${project.artifactId}_component = {
	include structure_component
	'flavor' : string = 'edg' with match(SELF,'^edg|glite$')
	'confFile' ? string = 'opt/edg/etc/edg-myproxy.conf'
  'trustedDNs' ? string[]
};

bind '/software/components/myproxy' = ${project.artifactId}_component;


