# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

unique template components/${project.artifactId}/config;

include { 'components/${project.artifactId}/schema' };

# Set prefix to root of component configuration.
prefix '/software/components/${project.artifactId}';

'version' = '${no-snapshot-version}';
#'package' = 'NCM::Component';
'active' ?= true;
'dispatch' ?= true;

# Install Quattor configuration module via RPM package.
'/software/packages' = pkg_repl('ncm-${project.artifactId}','${no-snapshot-version}-${rpm.release}','noarch');
'dependencies/pre' ?= list('spma');

