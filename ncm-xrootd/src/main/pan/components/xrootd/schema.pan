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

# Validation of options
function ${project.artifactId}_component_options_valid = {
  # If token-based authentication is enabled and DPM/Xrootd plugin is
  # used, must check that Authz librarie is specified and that 
  # DPM/Xrootd options principal and authorizedPaths are also present.
  if ( is_defined(SELF['tokenAuthz']) ) {
    if ( !is_defined(SELF['authzLibraries']) ||
         !is_defined(SELF['dpm']['principal']) ||
         !is_defined(SELF['dpm']['authorizedPaths']) ) {
      error("DPM/Xrootd plugin with token-based authz enabled requires 'authzLibraries',\n"+
                                                  "'dpm/principal' and 'dpm/authorizedPaths'");
      return(false);
    };
  };

  # Check that federation information is present if a 'fedredir' instance has been 
  # configured.
  if ( is_defined(SELF['xrootdInstances']) ) {
    foreach (instance;params;SELF['xrootdInstances']) {
      if ( params['type'] == 'fedredir' ) {
        if ( !is_defined(SELF['cmsdInstances'][instance]) ) {
          error("Missing cmsd instance matching xrootd 'fedredir' instance '"+instance+"'");
          false;
        } else if ( !is_defined(params['federation']) ) {
          error("'federation' parameter missing for xrootd instance '"+instance+"'");
          false;
        } else if ( !is_defined(SELF['federations'][params['federation']]) ) {
          error("No information provided for federation '"+params['federation']+"'");
          false;
        }; 
      } else if ( is_defined(params['federation']) ) {
        error("'federation' parameter specified for xrootd instance '"+instance+"' (type '"+params['type']+"')");
        false;
      };
    };
  };
  if ( is_defined(SELF['cmsdInstances']) ) {
    foreach (instance;params;SELF['cmsdInstances']) {
      if ( !is_defined(SELF['xrootdInstances'][instance]) ) {
        error("Missing xrootd instance matching cmsd instance '"+instance+"'");
        false;
      } else if ( !is_defined(params['federation']) ) {
        error("'federation' parameter missing for cmsd instance '"+instance+"'");
        false;
      }; 
    };
  };
  
  # For federations, check that either n2nLibrary and namePrefix are specified or that
  # both are absent.
  if ( is_defined(SELF['federations']) ) {
    foreach(federation;params;SELF['federations']) {
      if ( (is_defined(params['n2nLibrary']) && !is_defined(params['namePrefix'])) ||
           (!is_defined(params['n2nLibrary']) && is_defined(params['namePrefix'])) ) {
        error("Federation '"+federation+"': n2nLibrary and namePrefix must be both specified or absent");
        false;
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
  "mappedFQANs" ? string[]
  "authorizedPaths" ? string[]
  "principal" ? string
};

type ${project.artifactId}_component_fed_options = {
  'federationCmsdManager' : string
  'federationXrdManager' : string
  'n2nLibrary' ? string
  'namePrefix' ? string
  'localPort' : long
  'localRedirector' : string
  'lfcHost' ? string
  'lfcConnectionRetry' ? long
  'lfcSecurityMechanism' ? string
  'validPathPrefix' ? string
  'redirectParams' ? string
  'localRedirectParams' ? string
  "monitoringOptions" ? string
  "reportingOptions" ? string
};

type ${project.artifactId}_component_instances = {
  "configFile" : string
  "federation" ? string
  "logFile" : string
  "logKeep" : long = 90
  "type" : string with match(SELF,'(disk|redir|fedredir)')
};

type ${project.artifactId}_component_global_options = {
  "installDir" ? string
  "configDir" : string = 'xrootd'
  "authzLibraries" : string[]
  "daemonUser" : string
  "daemonGroup" : string
  "restartServices" : boolean = true
  "MonALISAHost" ? string
  "monitoringOptions" ? string
  "reportingOptions" ? string
  "cmsdInstances" ? ${project.artifactId}_component_instances{}
  "xrootdInstances" ? ${project.artifactId}_component_instances{}
  "federations" ? ${project.artifactId}_component_fed_options{}
  "tokenAuthz" ? ${project.artifactId}_component_token_authz_options
  "dpm" ? ${project.artifactId}_component_dpm_options
} with ${project.artifactId}_component_options_valid(SELF);

type ${project.artifactId}_component_node_config = {
  "roles" : string[]
};

type ${project.artifactId}_component = {
  include structure_component

  "hosts"    : ${project.artifactId}_component_node_config{} with ${project.artifactId}_component_node_config_valid(SELF)
  "options"  : ${project.artifactId}_component_global_options
};

bind "/software/components/xrootd" = ${project.artifactId}_component;


