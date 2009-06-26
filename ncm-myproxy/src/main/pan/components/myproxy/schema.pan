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
        'Auth_Retriev' ? string[]
        'Auth_RetrievRenew' ? string[]
        'AuthTrust_Retriev' ? string[]
};

bind '/software/components/myproxy' = ${project.artifactId}_component;


