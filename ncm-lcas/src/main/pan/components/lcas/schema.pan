# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
# Coding style: emulate <TAB> characters with 4 spaces, thanks!
################################################################################


declaration template components/lcas/schema;

include 'quattor/schema';

# Validation function to ensure that legacy schema properties for describing
#databases ('dbpath', 'module') are not used with the new ones (under 'db').
function component_lcas_valid = {
    if ( (ARGC != 1) && !is_nlist(ARGV[0]) ) {
        error('Invalid argument list in validation function component_lcas_valid');
    };

    if ( is_defined(SELF['db']) && is_defined(SELF['dbpath']) ) {
        error('Single database and multiple database configuration are mutually exclusive');
        return(false);
    } else if ( !is_defined(SELF['db']) && !is_defined(SELF['dbpath']) ) {
        error('Neither multiple database configuration nor valid single database configuration present');
        return(false);
    };

    return(true);
};


type ${project.artifactId}_component_plainfile_content = {
    "path" : string
    "noheader" : boolean = false
    "content" ? string[]
};

type ${project.artifactId}_component_modulespec = {
    "path" : string
    "args" ? string
    "conf" ? ${project.artifactId}_component_plainfile_content
};

type ${project.artifactId}_component_db = {
    "path" : string
    "module" ? ${project.artifactId}_component_modulespec[]
};

type ${project.artifactId}_component = {
    include structure_component
    "db" ? ${project.artifactId}_component_db[]
    # Deprecated: use 'db' instead.
    "dbpath" ? string
    "module" ? ${project.artifactId}_component_modulespec[]
} with component_lcas_valid(SELF);

bind "/software/components/lcas" = ${project.artifactId}_component;
