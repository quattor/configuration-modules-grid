@{ Template for testing a local redirector configuration with ncm-xrootd }

object template cms-fed-redir;

prefix '/software/components/xrootd';

'hosts/grid05.lal.in2p3.fr/roles/0' = 'redir';
'hosts/grid05.lal.in2p3.fr/roles/1' = 'fedredir';
'options/MonALISAHost' = 'aliendb2.cern.ch';
'options/authzLibraries/0' = 'libXrdDPMRedirAcc.so.3';
'options/configDir' = 'xrootd';
'options/daemonGroup' = 'dpmmgr';
'options/daemonUser' = 'dpmmgr';
'options/dpm/defaultPrefix' = '/dpm/lal.in2p3.fr/home';
'options/dpm/dpmHost' = 'grid05.lal.in2p3.fr';
'options/dpm/dpnsHost' = 'grid05.lal.in2p3.fr';
'options/installDir' = '';
'options/monitoringOptions' = 'all rbuff 32k auth flush 30s  window 5s dest files info user io redir  atl-prod05.slac.stanford.edu:9930';
'options/federations/cms/federationCmsdManager' = 'xrootd.ba.infn.it+:1213';
'options/federations/cms/federationXrdManager' = 'xrootd.ba.infn.it:1094';
'options/federations/cms/localPort' = '11001';
'options/federations/cms/localRedirectParams' = 'grid05.lal.in2p3.fr:11001 /store/';
'options/federations/cms/localRedirector' = 'localhost:11001';
'options/federations/cms/n2nLibrary' = 'libXrdCmsTfc.so file:/etc/xrootd/storage.xml?protocol=direct';
'options/federations/cms/namePrefix' = '/dpm/lal.in2p3.fr/home/cms';
'options/federations/cms/redirectParams' = 'xrootd.ba.infn.it:1094 ? /store/';
'options/federations/cms/validPathPrefix' = '/store/';
'options/reportingOptions' = ' atl-prod05.slac.stanford.edu:9931 every 60s all -buff -poll sync';
'options/restartServices' = true;
'options/xrootdInstances/cmsfed/configFile' = '/etc/xrootd/xrootd-dpmfedredir_cmsfed.cfg';
'options/xrootdInstances/cmsfed/federation' = 'cms';
'options/xrootdInstances/cmsfed/logFile' = '/var/log/xrootd/xrootd.log';
'options/xrootdInstances/cmsfed/logKeep' = '90';
'options/xrootdInstances/cmsfed/type' = 'fedredir';
'options/xrootdInstances/redir/configFile' = '/etc/xrootd/xrootd-dpmredir.cfg';
'options/xrootdInstances/redir/logFile' = '/var/log/xrootd/xrootd.log';
'options/xrootdInstances/redir/logKeep' = '90';
'options/xrootdInstances/redir/type' = 'redir';
