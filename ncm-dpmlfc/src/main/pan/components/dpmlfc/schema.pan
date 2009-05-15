# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/dpmlfc/schema;

include { 'quattor/schema' };

function component_dpmlfc_global_options_validation = {
  if ( !is_defined(SELF) ) {
    error('Internal error: DPM/LFC global options undefied in validation function');
    return(false);
  };
  
  if ( exists(SELF['accessProtocols']) && is_defined(SELF['accessProtocols']) ) {
    if ( !is_list(SELF['accessProtocols']) ) {
      error("Global option 'accessProtocols' must be a list");
      return(false);
    };
    foreach (i;protocol;SELF['accessProtocols']) {
      if ( !match(protocol,'https|gsiftp|rfio|xroot') ) {
        error('Invalid DPM access protocol specified ('+protocol+'). Must be https, gsiftp, rfio or xroot');
        return(false);
      };
    };
  };
  
  if ( exists(SELF['controlProtocols']) && is_defined(SELF['controlProtocols']) ) {
    if ( !is_list(SELF['controlProtocols']) ) {
      error("Global option 'controlProtocols' must be a list");
      return(false);
    };
    foreach (i;protocol;SELF['controlProtocols']) {
      if ( !match(protocol,'srmv1|srmv2|srmv2.2') ) {
        error('Invalid DPM control protocol specified ('+protocol+'). Must be srmv1, srmv2 or srmv2.2');
        return(false);
      };
    };
  };
  
  true;  
};

type ${project.artifactId}_component_fs_entry = {
        "host"     ? string
        "name"     ? string
        "status"     ? string
};

type ${project.artifactId}_component_pool_entry = {
        "def_filesize"    ? string
        "gc_start_thresh" ? long(0..)
        "gc_stop_thresh"  ? long(0..)
        "def_pintime"     ? long(0..)
        "gid"             ? long(1..)
        "group"           ? string
        "put_retenp"      ? long(0..)
        "s_type"          ? string with match (SELF,'-|D|P|V')
        "fs"              ? ${project.artifactId}_component_fs_entry[]
};

type ${project.artifactId}_component_vo_entry = {
        "gid"     ? long = -1
};

type ${project.artifactId}_component_node_config = {
        "host"      ? string
        "logfile"   ? string
        "port"      ? type_port
        "assumekernel" ? string
};

# xrood plugin daemons have several specific options
type ${project.artifactId}_component_xroot_options = {
        "ofsPlugin" ? string
        "config"    ? string
        "exportedVOs" ? string[]
        "tokenPrivateKey" ? string
        "tokenPublicKey" ? string
};

type ${project.artifactId}_component_db_conn_options = {
        "type"          ? string
        "configfile"    ? string
        "configmode"    ? string = '600'
        "server"        ? string
        "user"          : string = "dpmmgr"
        "password"      : string
#        "oldpassword"   ? string  # to be used when changing password
        "adminuser"     : string
        "adminpwd"      : string
#        "oldadminpwd"   ? string  # to be used when changing password
        "infoFile"      ? string
        "infoUser"      : string = "dminfo"
        "infoPwd"       ? string
};

type ${project.artifactId}_component_global_options = {
        "user"        ? string
        "group"       ? string
        "db"          ? ${project.artifactId}_component_db_conn_options
        "xroot"       ? ${project.artifactId}_component_xroot_options
        "installDir"  ? string = '/opt/lcg'
        "gridmapfile" ? string
        "gridmapdir"  ? string
        "accessProtocols"   ? string[]
        "controlProtocols"   ? string[]
} with component_dpmlfc_global_options_validation(SELF);

type ${project.artifactId}_component_global_options_tree = {
        "dpm"     ? ${project.artifactId}_component_global_options
        "lfc"     ? ${project.artifactId}_component_global_options
};

type ${project.artifactId}_component = {
	include structure_component

        "dpm"      ? ${project.artifactId}_component_node_config[]
        "dpns"     ? ${project.artifactId}_component_node_config[]
        "gsiftp"   ? ${project.artifactId}_component_node_config[]
        "rfio"     ? ${project.artifactId}_component_node_config[]
        "srmv1"    ? ${project.artifactId}_component_node_config[]
        "srmv2"    ? ${project.artifactId}_component_node_config[]
        "srmv22"   ? ${project.artifactId}_component_node_config[]
        "xroot"   ? ${project.artifactId}_component_node_config[]

        "pools"    ? ${project.artifactId}_component_pool_entry{}
        "vos"      ? ${project.artifactId}_component_vo_entry{}

        "lfc"      ? ${project.artifactId}_component_node_config[]
        "lfc-dli"  ? ${project.artifactId}_component_node_config[]

	      "options"  ? ${project.artifactId}_component_global_options_tree
};

bind "/software/components/dpmlfc" = ${project.artifactId}_component;


