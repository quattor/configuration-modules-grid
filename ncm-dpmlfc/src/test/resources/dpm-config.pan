@{ Template for testing with ncm-dpmlfc (DPM configuration) }

object template dpm-config;

include 'components/dpmlfc/schema';

prefix '/software/components/dpmlfc';

"copyd/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"dav/grid05.lal.in2p3.fr" = dict();
"dav/grid16.lal.in2p3.fr" = dict();
"dav/grid17.lal.in2p3.fr" = dict();
"dpm/grid05.lal.in2p3.fr/allowCoreDump" = true;
"dpm/grid05.lal.in2p3.fr/fastThreads" = 70;
"dpm/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"dpm/grid05.lal.in2p3.fr/port" = 5015;
"dpm/grid05.lal.in2p3.fr/requestMaxAge" = "180d";
"dpm/grid05.lal.in2p3.fr/slowThreads" = 20;
"dpns/grid05.lal.in2p3.fr/globusThreadModel" = "pthread";
"dpns/grid05.lal.in2p3.fr/port" = 5010;
"gsiftp/grid16.lal.in2p3.fr/globusThreadModel" = "pthread";
"gsiftp/grid16.lal.in2p3.fr/port" = 2811;
"gsiftp/grid17.lal.in2p3.fr/globusThreadModel" = "pthread";
"gsiftp/grid17.lal.in2p3.fr/port" = 2811;
"options/dpm/accessProtocols" = list("gsiftp", "rfio", "https", "xroot");
"options/dpm/db/configfile" = "/etc/DPMCONFIG";
"options/dpm/db/password" = "dpmdbpwd";
"options/dpm/db/server" = "sqlsrv1.lal.in2p3.fr";
"options/dpm/db/user" = "dpmdb";
"options/dpm/group" = "dpmgroup";
"options/dpm/installDir" = "/";
"options/dpm/user" = "dpmuser";
"protocols/dav" = dict(
    "DiskAnonUser", "nobody",
    "DiskFlags", list("Write"),
    "NSAnonUser", "nobody",
    "NSFlags", list("Write"),
    "NSMaxReplicas", 4,
    "NSRedirectPort", list(80, 443),
    "NSSecureRedirect", "on",
    "NSServer", list("headnode", "1234"),
    "NSTrustedDNs", list(
        '"/DC=ch/DC=cern/OU=computers/CN=trusted-host.cern.ch"',
        '"/DC=ch/DC=cern/OU=computers/CN=trusted-host2.cern.ch"',
    ),
    "NSType", "DPM",
    "SSLCertFile", "/etc/grid-security/hostcert.pem",
    "SSLCertKey", "/etc/grid-security/hostkey.pem",
    "SSLCACertPath", "/etc/grid-security/certificates",
    "SSLCARevocationPath", "/etc/grid-security/certificates",
    "SSLOptions", list("+StdEnvVars"),
    "SSLProtocol", list("all", "-SSLv2", "-SSLv3"),
    "SSLSessionCache", "shmcb:/dev/shm/ssl_gcache_data(1024000)",
    "SSLSessionCacheTimeout", 7200,
    "SSLVerifyClient", "require",
    "SSLVerifyDepth", 10,
);
"protocols/rfio" = dict(
    "globusThreadModel", "pthread",
    "port", 5001,
);
"protocols/srmv1" = dict(
    "globusThreadModel", "pthread",
    "port", 8443,
);
"protocols/srmv22" = dict(
    "globusThreadModel", "pthread",
    "port", 8446,
);
"protocols/xroot" = dict(
    "globusThreadModel", "pthread",
);
"rfio/grid05.lal.in2p3.fr" = dict();
"rfio/grid16.lal.in2p3.fr" = dict();
"rfio/grid17.lal.in2p3.fr" = dict();
"srmv1/grid05.lal.in2p3.fr" = dict();
"srmv22/grid05.lal.in2p3.fr" = dict();
"xroot/grid16.lal.in2p3.fr" = dict();
"xroot/grid17.lal.in2p3.fr" = dict();


prefix '/software/components/gip2';
"user" = "ldap";
