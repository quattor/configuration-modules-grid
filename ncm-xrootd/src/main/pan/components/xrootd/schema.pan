# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/xrootd/schema;

include { 'quattor/schema' };

# Validation of host configiguration (hosts resource)
function ${project.artifactId}_component_node_config_valid = {
  if ( !is_defined(SELF) ) {
    error('Internal error: Xroot host configuration undefined in validation function');
    return(false);
  };
  valid_roles = 'disk|redir|fedredir';
  foreach (host;params;SELF) {
    foreach (k;v;params) {
      if ( k == 'roles' ) {
        foreach (i;role;v) {
        if ( !match(role,'^('+valid_roles+')$') ) {
          error('Invalid role ('+role+') specified for host '+host+' (valid roles='+valid_roles+')');
          return(false);
        }; 
        };
      };
    };
  };
  true;
};

# Validation of xroot access rules
function ${project.artifactId}_component_access_rules_valid = {
  if ( !is_defined(SELF) ) {
    error('Internal error: Xroot access rules undefined in validation function');
    return(false);
  };
  
  foreach (i;operation_type;list('authenticated','unauthenticated')) {
    if ( is_defined(SELF[operation_type]) ) {
      foreach (j;operation;SELF[operation_type]) {
        if ( !match(operation,'^(delete|read|write|write-once)$') ) {
          error('Invalid operation ('+operation+') specified in xroot access rules for '+operation_type+' operations');
          return(false);
        }; 
      };
    };
  };
  true;
};

# xrootd authentication plug-in allow to specify operations requiring
# authentication and those allowed without authentication (authentication will be
# used if present).

type ${project.artifactId}_component_exported_path = {
  # Path is optional: if absent the VO name (nlist key will be used).
  # If the path is not starting with '/', will be appended to exportedPathRoot.
  'path' ? string
};

type ${project.artifactId}_component_access_rules = {
  'path' : string
  'authenticated' : string[]
  'unauthenticated' : string[]
  'vo' : string = '*'
  'cert' : string = '*'
} with ${project.artifactId}_component_access_rules_valid(SELF);

type ${project.artifactId}_component_token_authz_options = {
  "authzConf" : string = '/etc/grid-security/xrootd/TkAuthz.Authorization'
  "allowedFQANs" : string[]
  "authorizedPaths" : string[]
  "principal" : string
  "tokenPrivateKey" ? string = '/etc/grid-security/xrootd/pvkey.pem'
  "tokenPublicKey" ? string = '/etc/grid-security/xrootd/pubkey.pem'
  "accessRules" : ${project.artifactId}_component_access_rules[]
  "exportedVOs" : ${project.artifactId}_component_exported_path{}
  "exportedPathRoot" : string
};


# DPM/Xrootd plugin configuration

type ${project.artifactId}_component_dpm_options = {
  "alternateNames" ? string
  "coreMaxSize" ? long
  "dpmConnectionRetry" ? long
  "dpmHost" : string
  "dpnsConnectionRetry" ? long
  "dpnsHost" : string
  "defaultPrefix" ? string
  "replacementPrefix" ? string{}
};

type ${project.artifactId}_component_fed_options = {
  'remote_cmsd_manager' : string
  'remote_xrd_manager' : string
  'cmsd_options' ? string
  'xrootd_options' ? string
  'redir_local_port' ? long
};

type ${project.artifactId}_component_instances = {
  "configFile" : string
  "logFile" : string
  "type" : string with match(SELF,'(disk|redir|fedredir)')
};

type ${project.artifactId}_component_global_options = {
  "installDir" ? string
  "configDir" : string = 'xrootd'
  "ofsPlugin" : string = 'Ofs'
  "authzLibraries" : string[]
  "daemonUser" : string
  "daemonGroup" : string
  "restartServices" : boolean = true
  "MonALISAHost" ? string
  "cmsdInstances" ? ${project.artifactId}_component_instances{}
  "xrootdInstances" ? ${project.artifactId}_component_instances{}
  "federation" ? ${project.artifactId}_component_fed_options
  "tokenAuthz" ? ${project.artifactId}_component_token_authz_options
  "dpm" ? ${project.artifactId}_component_dpm_options
};

type ${project.artifactId}_component_node_config = {
  "roles" : string[]
};

type ${project.artifactId}_component = {
  include structure_component

  "hosts"    : ${project.artifactId}_component_node_config{} with ${project.artifactId}_component_node_config_valid(SELF)
  "options"  : ${project.artifactId}_component_global_options
};

bind "/software/components/xrootd" = ${project.artifactId}_component;


