# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/myproxy/schema;

include { 'quattor/schema' };

# Function to validate component configuration, in particular
# ensure than obsolete trustedDNs is not specified as the same
# time as new authorizedDNs and defaultDNs.

function component_myproxy_options_valid = {
  if ( is_defined(SELF['trustedDNs']) &&
       (is_defined(SELF['authorizedDNs']) || is_defined(SELF['defaultDNs'])) ) {
    error('trustedDNs is obsolete and cannot be mixed with authorizedDNs and defaultDNs');  
  };
  true;
};


type ${project.artifactId}_component_policies = {
  'renewers' ? string[]
  'retrievers' ? string[]
  'keyRetrievers' ? string[]
  'trustedRetrievers' ? string[]
};

type ${project.artifactId}_component = {
	include structure_component
	'flavor' : string = 'edg' with match(SELF,'^(edg|glite)$')
	'confFile' ? string = 'opt/edg/etc/edg-myproxy.conf'
  'trustedDNs' ? string[]
  'authorizedDNs' ? ${project.artifactId}_component_policies
  'defaultDNs' ? ${project.artifactId}_component_policies
} with component_myproxy_options_valid(SELF);

bind '/software/components/myproxy' = ${project.artifactId}_component;


