@{ Template for testing a local redirector configuration with ncm-xrootd }

object template atlas-fed-redir;

include 'components/xrootd/schema';

prefix '/software/components/xrootd';

'hosts/grid05.lal.in2p3.fr/roles/0' = 'redir';
'hosts/grid05.lal.in2p3.fr/roles/1' = 'fedredir';
'options/MonALISAHost' = 'aliendb2.cern.ch';
'options/authzLibraries/0' = 'libXrdDPMRedirAcc.so.3';
'options/cmsdInstances/atlasfed/configFile' = '/etc/xrootd/xrootd-dpmfedredir_atlasfed.cfg';
'options/cmsdInstances/atlasfed/federation' = 'atlas';
'options/cmsdInstances/atlasfed/logFile' = '/var/log/xrootd/cmsd.log';
'options/cmsdInstances/atlasfed/logKeep' = '90';
'options/cmsdInstances/atlasfed/type' = 'fedredir';
'options/configDir' = 'xrootd';
'options/daemonGroup' = 'dpmmgr';
'options/daemonUser' = 'dpmmgr';
'options/dpm/defaultPrefix' = '/dpm/lal.in2p3.fr/home';
'options/dpm/dpmHost' = 'grid05.lal.in2p3.fr';
'options/dpm/dpnsHost' = 'grid05.lal.in2p3.fr';
'options/federations/atlas/federationCmsdManager' = 'atlas-xrd-fr.cern.ch+:1098';
'options/federations/atlas/federationXrdManager' = 'atlas-xrd-fr.cern.ch:1094';
'options/federations/atlas/lfcConnectionRetry' = 0;
'options/federations/atlas/lfcHost' = 'prod-lfc-atlas-ro.cern.ch';
'options/federations/atlas/lfcSecurityMechanism' = 'ID';
'options/federations/atlas/localPort' = 11000;
'options/federations/atlas/localRedirectParams' = 'grid05.lal.in2p3.fr:11000 /atlas/';
'options/federations/atlas/localRedirector' = 'localhost:11000';
'options/federations/atlas/monitoringOptions' = 'all rbuff 32k auth flush 30s  window 5s dest files info user io redir atl-prod05.slac.stanford.edu:9930';
'options/federations/atlas/n2nLibrary' = 'XrdOucName2NameLFC.so root=/dpm/lal.in2p3.fr/home/atlas match=grid05.lal.in2p3.fr';
'options/federations/atlas/namePrefix' = '/dpm/lal.in2p3.fr/home/atlas';
'options/federations/atlas/redirectParams' = 'atlas-xrd-fr.cern.ch:1094 ? /atlas/';
'options/federations/atlas/reportingOptions' = 'atl-prod05.slac.stanford.edu:9931 every 60s all -buff -poll sync';
'options/federations/atlas/validPathPrefix' = '/atlas/';
'options/installDir' = '';
'options/mallocArenaMax' = 4;
'options/monitoringOptions' = 'all rbuff 32k auth flush 30s  window 5s dest files info user io redir  atl-prod05.slac.stanford.edu:9930';
'options/reportingOptions' = ' atl-prod05.slac.stanford.edu:9931 every 60s all -buff -poll sync';
'options/restartServices' = true;
'options/securityProtocol/gsi' = nlist("ca", 2,
                                       "cert", "/etc/grid-security/dpmmgr/dpmcert.pem",
                                       "crl", 3,
                                       "gmapopt", 10,
                                       "key", "/etc/grid-security/dpmmgr/dpmkey.pem",
                                       "md", "sha256:sha1",
                                       "vomsfun", "/usr/lib64/libXrdSecgsiVOMS.so",
                                      );
'options/xrootdInstances/atlasfed/configFile' = '/etc/xrootd/xrootd-dpmfedredir_atlasfed.cfg';
'options/xrootdInstances/atlasfed/federation' = 'atlas';
'options/xrootdInstances/atlasfed/logFile' = '/var/log/xrootd/xrootd.log';
'options/xrootdInstances/atlasfed/logKeep' = '90';
'options/xrootdInstances/atlasfed/type' = 'fedredir';
'options/xrootdInstances/redir/configFile' = '/etc/xrootd/xrootd-dpmredir.cfg';
'options/xrootdInstances/redir/logFile' = '/var/log/xrootd/xrootd.log';
'options/xrootdInstances/redir/logKeep' = '90';
'options/xrootdInstances/redir/type' = 'redir';
