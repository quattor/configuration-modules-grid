# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
############################################################
#
# type definition components/vomrs
#
#
#
#
#
############################################################

declaration template components/vomrs/schema;

include { 'quattor/schema' };

type structure_vomrs_vo = {
         "name"        : string
         "vomrs"              ? string{} # Related to vomrs configuration.
         "voinfo"             ? string{} # Related to VO
         "gridorg"            ? string{} # Grid Orgnisation Info.
         "tomcat"             ? string{} # Tomcat Information
         "cacert"             ? string{} # CA RelatedA
         "vomem"              ? string{} # VO Membership Related.
         "event"              ? string{} # Event Notification 
         "sync"               ? string{} # VOMS syncronisation
         "db"                 ? string{} # VOMRS Database details.
         "lcg"                ? string{} # LCG Registration.

 };

type ${project.artifactId}_component = {
        include structure_component
        "VOs"                : list 
        "home"               : string  # VOMRS_LOCATION /opt/vomrs-1.3.
        "configure"          ? boolean # Should voms_configure be ran ? (default no)
        "confscript"         : string  # Pathc to voms_configure
        "confdir"            : string  # Path to create and use quattor created files.
        "vomrssecretdir"     ? string
        "vo"                 ? structure_vomrs_vo{}
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;


