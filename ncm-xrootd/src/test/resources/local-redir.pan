@{ Template for testing a local redirector configuration with ncm-xrootd }

object template local-redir;

prefix '/software/components/xrootd';

'hosts/grid05.lal.in2p3.fr/roles/0' = 'redir';
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
'options/reportingOptions' = ' atl-prod05.slac.stanford.edu:9931 every 60s all -buff -poll sync';
'options/restartServices' = true;
'options/siteName' = 'GRIF-LAL';
'options/xrootdInstances/redir/configFile' = '/etc/xrootd/xrootd-dpmredir.cfg';
'options/xrootdInstances/redir/logFile' = '/var/log/xrootd/xrootd.log';
'options/xrootdInstances/redir/logKeep' = '90';
'options/xrootdInstances/redir/type' = 'redir';
