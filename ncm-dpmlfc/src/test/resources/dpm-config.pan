@{ Template for testing with ncm-dpmlfc (DPM configuration) }

object template dpm-config;

prefix '/software/components/dpmlfc';

"copyd/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"dav/grid05.lal.in2p3.fr/NSFlags/0" = "Write";
"dav/grid16.lal.in2p3.fr/DiskFlags/0" = "Write";
"dav/grid17.lal.in2p3.fr/DiskFlags/0" = "Write";
"dependencies/pre/0" = "spma";
"dependencies/pre/1" = "accounts";
"dependencies/pre/2" = "sysconfig";
"dependencies/pre/3" = "filecopy";
"dispatch" = true;
"dpm/grid05.lal.in2p3.fr/allowCoreDump" = true;
"dpm/grid05.lal.in2p3.fr/fastThreads" = "70";
"dpm/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"dpm/grid05.lal.in2p3.fr/port" = "5015";
"dpm/grid05.lal.in2p3.fr/requestMaxAge" = "180d";
"dpm/grid05.lal.in2p3.fr/slowThreads" = "20";
"dpns/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"dpns/grid05.lal.in2p3.fr/port" = "5010";
"gsiftp/grid16.lal.in2p3.fr/globusThreadModel" = "pthread";
"gsiftp/grid16.lal.in2p3.fr/port" = "2811";
"gsiftp/grid17.lal.in2p3.fr/globusThreadModel" = "pthread";
"gsiftp/grid17.lal.in2p3.fr/port" = "2811";
"options/dpm/accessProtocols/0" = "gsiftp";
"options/dpm/accessProtocols/1" = "rfio";
"options/dpm/accessProtocols/2" = "https";
"options/dpm/accessProtocols/3" = "xroot";
"options/dpm/db/configfile" = "/etc/DPMCONFIG";
"options/dpm/db/password" = "daipouseur";
"options/dpm/db/server" = "sqlsrv1.lal.in2p3.fr";
"options/dpm/db/user" = "dpmmgr";
"options/dpm/group" = "dpmmgr";
"options/dpm/installDir" = "/";
"options/dpm/user" = "dpmmgr";
"rfio/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"rfio/grid05.lal.in2p3.fr/port" = "5001";
"rfio/grid16.lal.in2p3.fr/globusThreadModel" = "pthread";
"rfio/grid16.lal.in2p3.fr/port" = "5001";
"rfio/grid17.lal.in2p3.fr/globusThreadModel" = "pthread";
"rfio/grid17.lal.in2p3.fr/port" = "5001";
"srmv1/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"srmv1/grid05.lal.in2p3.fr/port" = "8443";
"srmv22/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"srmv22/grid05.lal.in2p3.fr/port" = "8446";
"version" = "15.4.0";
"xroot/grid16.lal.in2p3.fr/globusThreadModel" = "pthread";
"xroot/grid17.lal.in2p3.fr/globusThreadModel" = "pthread";