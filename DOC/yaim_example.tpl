#
# example template for YAIM configuration.
# needs to be adapted to your site.
#
# PLEASE read:
# 1. the ncm-yaim man page
# 2. the yaim documentation
#

template yaim_example;

"/software/components/yaim/active"=true;

#
# uncomment if APT install is required (eg. not running SPMA)
#
#"/software/components/yaim/install"=true;



#
# node type. Add/replace as required.
#
"/software/components/yaim/nodetype/WN"=true;
#"/software/components/yaim/nodetype/CE"=true;
# etc.

#
# General info
#
"/software/components/yaim/conf/CE_HOST"="ce.mydomain.com";
"/software/components/yaim/conf/CLASSIC_HOST"="se.mydomain.com";
"/software/components/yaim/conf/RB_HOST"="rb.mydomain.com";
"/software/components/yaim/conf/PX_HOST"="px.mydomain.com";
"/software/components/yaim/conf/BDII_HOST"="bdii.mydomain.com";
"/software/components/yaim/conf/MON_HOST"="mon.mydomain.com";
"/software/components/yaim/conf/REG_HOST"="lcgic01.gridpp.rl.ac.uk"; # there is only 1 central registry for now


# Set this if you are building a LFC server
# not if you're just using clients
"/software/components/yaim/conf/LFC_HOST"="my-lfc.mydomain.com";


"/software/components/yaim/conf/WN_LIST"=
  "/opt/lcg/yaim/examples/wn-list.conf";

# set this to /usr/lib/ncm/config/yaim/empty if you don't want users defined
"/software/components/yaim/conf/USERS_CONF"=
  "/opt/lcg/yaim/examples/users.conf";



"/software/components/yaim/conf/LCG_REPOSITORY"=
  "rpm http://grid-deployment.web.cern.ch/grid-deployment/gis apt/LCG-2_7_0/sl3/en/i386 lcg_sl3 lcg_sl3.updates";
"/software/components/yaim/conf/CA_REPOSITORY"=
  "rpm http://grid-deployment.web.cern.ch/grid-deployment/gis apt/LCG_CA/en/i386 lcg";

# only needed if non-root installation
#"/software/components/yaim/conf/CA_WGET"="http://grid-deployment.web.cern.ch/grid-deployment/download/RpmDir/security/index.html"'


# You'll probably want to change these too for the relocatable dist
"/software/components/yaim/conf/OUTPUT_STORAGE"="/tmp/jobOutput";
"/software/components/yaim/conf/JAVA_LOCATION"="/usr/java/j2sdk1.4.2_08";

# Set this to '/dev/null' or some other dir if you want
# to turn off yaim's installation of cron jobs
"/software/components/yaim/conf/CRON_DIR"="/etc/cron.d";

"/software/components/yaim/conf/GLOBUS_TCP_PORT_RANGE"="20000 25000";

"/software/components/yaim/conf/MYSQL_PASSWORD"="set_this_to_a_good_password";

"/software/components/yaim/conf/GRID_TRUSTED_BROKERS"="  ";

"/software/components/yaim/conf/GRIDMAP_AUTH"="ldap://lcg-registrar.cern.ch/ou=users,o=registrar,dc=lcg,dc=org";
 #GRIDMAP_AUTH="ldap://lcg-registrar.cern.ch/ou=users,o=registrar,dc=lcg,dc=org ldap://xxx"


"/software/components/yaim/conf/GRIDICE_SERVER_HOST"=
  value("/software/components/yaim/conf/CLASSIC_HOST");


"/software/components/yaim/conf/SITE_EMAIL"="root@localhost";
"/software/components/yaim/conf/SITE_NAME"="my-site-name";
"/software/components/yaim/conf/SITE_VERSION"="lcg-2_7_0";
"/software/components/yaim/conf/YAIM_VERSION"="lcg-2_7_0";

"/software/components/yaim/conf/SITE_LOC"          = "Mytown, MyCountry";
"/software/components/yaim/conf/SITE_LAT"          = "54.33";
"/software/components/yaim/conf/SITE_LONG"         = "09.33";
"/software/components/yaim/conf/SITE_WEB"          = "http://www.myweb.com";
"/software/components/yaim/conf/SITE_TIER"         = "TIER 4";
"/software/components/yaim/conf/SITE_SUPPORT_SITE" = "CERN";



#
# CE info
#

"/software/components/yaim/conf/SE_TYPE"="disk";
"/software/components/yaim/conf/JOB_MANAGER"="lcgpbs";

"/software/components/yaim/CE/BATCH_SYS"="torque";
"/software/components/yaim/CE/CPU_MODEL"="PIII";
"/software/components/yaim/CE/CPU_VENDOR"="intel";
"/software/components/yaim/CE/CPU_SPEED"="1001";
"/software/components/yaim/CE/OS"="Redhat";
"/software/components/yaim/CE/OS_RELEASE"="SLC3";
"/software/components/yaim/CE/MINPHYSMEM"="513";
"/software/components/yaim/CE/MINVIRTMEM"="1025";
"/software/components/yaim/CE/SMPSIZE"="2";
"/software/components/yaim/CE/SI00"="381";
"/software/components/yaim/CE/SF00"="0";
"/software/components/yaim/CE/OUTBOUNDIP"="TRUE";
"/software/components/yaim/CE/INBOUNDIP"="FALSE";
"/software/components/yaim/CE/RUNTIMEENV"=
  "LCG-2 LCG-2_1_0 LCG-2_1_1 LCG-2_2_0 LCG-2_3_0 LCG_2_3_1 LCG_2_4_0 LCG_2_6_0
  LCG_2_7_0 R-GMA";

"/software/components/yaim/CE/closeSE/se1/HOST"=
  value("/software/components/yaim/conf/CLASSIC_HOST");
"/software/components/yaim/CE/closeSE/se1/ACCESS_POINT"="/storage";
"/software/components/yaim/CE/closeSE/se2/HOST"="another-se.mydomain.com";
"/software/components/yaim/CE/closeSE/se2/ACCESS_POINT"="/somewhere";


#
# dCache and DPM
#
# dCache-specific settings
"/software/components/yaim/conf/DCACHE_ADMIN"="my-admin-node";
"/software/components/yaim/conf/DCACHE_POOLS"="my-pool-node1:/pool-path1 my-pool-node2:/pool-path2";
# Optional
# "/software/components/yaim/conf/DPM_POOLS"="DCACHE_PORT_RANGE="20000,25000";
# SE_dpm-specific settings
"/software/components/yaim/conf/DPM_POOLS"="lxb1727:/dpmpool2";
# Optional
# "/software/components/yaim/conf/DPM_POOLS"="DPM_PORT_RANGE="20000,25000" ??
"/software/components/yaim/conf/DPMDATA"=value("/software/components/yaim/CE/closeSE/se1/ACCESS_POINT");
"/software/components/yaim/conf/DPM_POOLS"="dpmu_Bar";
"/software/components/yaim/conf/DPMUSER_PWD"="dpmu_Bar";
"/software/components/yaim/conf/DPMCONFIG"="/home/dpmuser/DPMCONFIG";
"/software/components/yaim/conf/DPMLOGS"="/var/tmp/DPMLogs";
"/software/components/yaim/conf/DPMFSIZE"="200M";
"/software/components/yaim/conf/DPM_HOST"=value("/software/components/yaim/conf/CLASSIC_HOST");
## Temp
"/software/components/yaim/conf/DPMPOOL"="dpmpool2";




#
# BDII info
#
"/software/components/yaim/conf/BDII_HTTP_URL"=
  "http://grid-deployment.web.cern.ch/grid-deployment/gis/lcg2-bdii/dteam/lcg2-all-sites.conf";
"/software/components/yaim/conf/BDII_REGIONS"="CE SE RB PX";
# rely on shell variable substitution (as below) works but is not nice..
# alternative is to use pan global variables.
"/software/components/yaim/conf/BDII_CE_URL"=
  "ldap://$CE_HOST:2135/mds-vo-name=local,o=grid";
"/software/components/yaim/conf/BDII_SE_URL"=
  "ldap://$CLASSIC_HOST:2135/mds-vo-name=local,o=grid";
"/software/components/yaim/conf/BDII_RB_URL"=
  "ldap://$RB_HOST:2135/mds-vo-name=local,o=grid";
"/software/components/yaim/conf/BDII_PX_URL"=
  "ldap://$PX_HOST:2135/mds-vo-name=local,o=grid";


#
# VO's and VO info.
#

# set QUEUES to defined VOS
"/software/components/yaim/conf/QUEUES"="ATLAS ALICE CMS LHCB DTEAM";
# Note. Can the above QUEUES definition be derived from the info below??

# Note:
# /system/vo has been moved to /software/components/yaim/vo
# for backwards compatibility, /system/vo is tried if 
# /software/components/yaim/vo does not exist

"/software/components/yaim/vo/atlas/name"="ATLAS";
"/software/components/yaim/vo/atlas/services/SW_DIR"="/opt/exp_soft";
"/software/components/yaim/vo/atlas/services/DEFAULT_SE"=
  value("/software/components/yaim/conf/CLASSIC_HOST");
"/software/components/yaim/vo/atlas/services/SGM"=
  "ldap://grid-vo.nikhef.nl/ou=lcgadmin,o=atlas,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/atlas/services/USERS"=
  "ldap://grid-vo.nikhef.nl/ou=lcg1,o=atlas,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/atlas/services/STORAGE_DIR"=
  "/storage/atlas";
"/software/components/yaim/vo/atlas/services/QUEUES"="atlas";

"/software/components/yaim/vo/alice/name"="ALICE";
"/software/components/yaim/vo/alice/services/SW_DIR"="/opt/exp_soft";
"/software/components/yaim/vo/alice/services/DEFAULT_SE"=
  value("/software/components/yaim/conf/CLASSIC_HOST");
"/software/components/yaim/vo/alice/services/SGM"=
  "ldap://grid-vo.nikhef.nl/ou=lcgadmin,o=alice,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/alice/services/USERS"=
  "ldap://grid-vo.nikhef.nl/ou=lcg1,o=alice,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/alice/services/STORAGE_DIR"=
  "/storage/alice";
"/software/components/yaim/vo/alice/services/QUEUES"="alice";

"/software/components/yaim/vo/cms/name"="CMS";
"/software/components/yaim/vo/cms/services/SW_DIR"="/opt/exp_soft";
"/software/components/yaim/vo/cms/services/DEFAULT_SE"=
  value("/software/components/yaim/conf/CLASSIC_HOST");
"/software/components/yaim/vo/cms/services/SGM"=
  "ldap://grid-vo.nikhef.nl/ou=lcgadmin,o=cms,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/cms/services/USERS"=
  "ldap://grid-vo.nikhef.nl/ou=lcg1,o=cms,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/cms/services/STORAGE_DIR"=
  "/storage/CMS";
"/software/components/yaim/vo/cms/services/QUEUES"="cms";

"/software/components/yaim/vo/lhcb/name"="LHCB";
"/software/components/yaim/vo/lhcb/services/SW_DIR"="/opt/exp_soft";
"/software/components/yaim/vo/lhcb/services/DEFAULT_SE"=
  value("/software/components/yaim/conf/CLASSIC_HOST");
"/software/components/yaim/vo/lhcb/services/SGM"=
  "ldap://grid-vo.nikhef.nl/ou=lcgadmin,o=lhcb,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/lhcb/services/USERS"=
  "ldap://grid-vo.nikhef.nl/ou=lcg1,o=lhcb,dc=eu-datagrid,dc=org";
"/software/components/yaim/vo/lhcb/services/STORAGE_DIR"=
  "/storage/lhcb";
"/software/components/yaim/vo/lhcb/services/QUEUES"="lhcb";


"/software/components/yaim/vo/dteam/name"="DTEAM";
"/software/components/yaim/vo/dteam/services/SW_DIR"="/opt/exp_soft";
"/software/components/yaim/vo/dteam/services/DEFAULT_SE"=
  value("/software/components/yaim/conf/CLASSIC_HOST");
"/software/components/yaim/vo/dteam/services/SGM"=
  "ldap://lcg-vo.cern.ch/ou=lcgadmin,o=dteam,dc=lcg,dc=org";
"/software/components/yaim/vo/dteam/services/USERS"=
  "ldap://lcg-vo.cern.ch/ou=lcg1,o=dteam,dc=lcg,dc=org";
"/software/components/yaim/vo/dteam/services/STORAGE_DIR"=
  "/storage/dteam";
"/software/components/yaim/vo/dteam/services/QUEUES"="dteam";




