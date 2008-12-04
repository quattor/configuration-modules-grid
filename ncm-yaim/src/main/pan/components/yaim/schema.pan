# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
############################################################
#
# type definition components/yaim
#
#
#
#
#
############################################################

declaration template components/yaim/schema;

include { 'quattor/schema' };

type structure_yaim_vo = {
         "name"        : string
         "auth"        ? string[] # was structure_vo_auth[], mandatory
         "services"    ? string{} # ? structure_vo_services
 };

type ${project.artifactId}_component = {
        include structure_component
        "install"            ? boolean # Should YAIM itself be run? (default no)
        "configure"          ? boolean # Should YAIM itself be run? (default no)
        "conf"               : string{}
        "nodetype"           : boolean{}
        "CE"                 ? nlist # to be removed and replaced by /software/components/yaim/CE
        "FTA"                ? string{}
        "FTS"                ? string{}
        "FTM"                ? string{}
        "extra"              ? string{}
        "vo"                 ? structure_yaim_vo{}
        "SECRET_PASSWORDS"   ? string
        "SITE_INFO_DEF_FILE" ? string
        "USE_VO_D"           ? boolean # store VO config in file per VO under vo.d (default no)
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;


