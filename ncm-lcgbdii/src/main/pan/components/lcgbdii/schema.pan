# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/lcgbdii/schema;

include { 'quattor/schema' };

include { 'pan/types' };

# Function to check that some optional properties are present in context they
# are requireed
function lcgbdii_check_params = {
  if ( ARGC != 1 ) {
    error('lcgbdii_check_params must receive exactly one argument of type component_lcgbdii');
  };
  
  if ( (SELF['autoUpdate'] == 'yes') && !exists(SELF['updateUrl']) ) {
    error('Property updateUrl required when autoUpdate=yes');
  };

  if ( (SELF['autoModify'] == 'yes') && !exists(SELF['updateLdif']) ) {
    error('Property updateLdif required when autoModify=yes');
  };
 
  return(true);
};


type ${project.artifactId}_component = {
	include structure_component

  'dir'           : string = '/opt/bdii/'
  'varDir'        : string = '/opt/bdii/var'
  'configFile'    : string = '/opt/bdii/var/lcg-bdii.conf'
  'schemaFile'    ? string
  'debugLevel'    : long = 4

  'portRead'      : type_port = 2170
  'portsWrite'    : type_port[] = list(2171,2172,2173)
  'user'          : string = 'lcgbdii'
  'bind'          : string = 'mds-vo-name=local,o=grid'
  'passwd'        : string
  'searchFilter'  : string = "'*'"
  'searchTimeout' : long(1..) = 30
  'breatheTime'   : long(1..) = 60
  'autoUpdate'    : string = 'no' with match (SELF, 'yes|no')
  'autoModify'    : string = 'no' with match (SELF, 'yes|no')
  'isCache'       : string = 'no' with match (SELF, 'yes|no')
  'modifyDN'      : string = 'no' with match (SELF, 'yes|no')

  'updateUrl'     ? type_absoluteURI
  'updateLdif'    ? type_absoluteURI = 'http://lcg-fcr.cern.ch:8083/fcr-data/exclude.ldif'
  'defaultLdif'   : string = '/opt/bdii/etc/default.ldif'

  'slapd'         : string = '/opt/openldap/libexec/slapd'
  'slapadd'       : string = '/opt/openldap/sbin/slapadd'
  'salpdConf'     : string = '/opt/bdii/etc/glue-slapd.conf'

  'urls'          ? type_absoluteURI{}
  'schemas'       ? string[]
} with lcgbdii_check_params(SELF);

bind '/software/components/lcgbdii' = ${project.artifactId}_component;
