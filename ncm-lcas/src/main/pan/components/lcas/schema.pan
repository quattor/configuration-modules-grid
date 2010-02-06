# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
# Coding style: emulate <TAB> characters with 4 spaces, thanks!
################################################################################


declaration template components/lcas/schema;

include { 'quattor/schema' };

type lcas_plainfile_content_type = {
	"path"		: string
	"noheader"	? boolean
	"content"	? string[]
};

type lcas_modulespec_type = {
	"path"	: string
	"args"	? string
	"conf"  ? lcas_plainfile_content_type
};

type ${project.artifactId}_component = {
  include structure_component
  "dbpath"	: string
  "module"	? lcas_modulespec_type[]
};

bind "/software/components/lcas" = ${project.artifactId}_component;

