@{ Template for testing ncm-xrootd Configure for a Xrootd disk server }

object template disk;

include 'components/xrootd/schema';

prefix '/software/components/xrootd';

'active' = true;
'dispatch' = true;
'hosts/grid41.lal.in2p3.fr/roles/0' = 'disk';
'options/MonALISAHost' = 'aliendb2.cern.ch';
'options/authzLibraries/0' = 'libXrdDPMRedirAcc.so.3';
'options/configDir' = 'xrootd';
'options/daemonGroup' = 'dpmmgr';
'options/daemonUser' = 'dpmmgr';
'options/dpm/defaultPrefix' = '/dpm/lal.in2p3.fr/home';
'options/dpm/dpmHost' = 'grid05.lal.in2p3.fr';
'options/dpm/dpnsHost' = 'grid05.lal.in2p3.fr';
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
'options/siteName' = 'GRIF-LAL';
'options/xrootdInstances/disk/configFile' = '/etc/xrootd/xrootd-dpmdisk.cfg';
'options/xrootdInstances/disk/logFile' = '/var/log/xrootd/xrootd.log';
'options/xrootdInstances/disk/logKeep' = '90';
'options/xrootdInstances/disk/type' = 'disk';
