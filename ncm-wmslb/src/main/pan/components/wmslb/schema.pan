# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/wmslb/schema;

include { 'quattor/schema' };

include { 'pan/types' };

type ${project.artifactId}_component_env = {
  'GLITE_LOCATION' ? string
  'GLITE_LOCATION_LOG' ? string
  'GLITE_LOCATION_TMP' ? string
  'GLITE_LOCATION_VAR' ? string
  'GLITE_LB_TYPE' ? string
  'GLITE_WMS_LOCATION_VAR' ? string
  'GLITE_WMS_TMP' ? string
  'GLITE_WMS_USER' ? string
  'GLITE_WMS_GROUP' ? string
  'GLITE_HOST_CERT' ? string
  'GLITE_HOST_KEY' ? string
  'GLITE_WMS_QUERY_TIMEOUT' : long = 300
  'GLITE_WMS_WMPROXY_MAX_SERVED_REQUESTS' : long = 50
  'GLITE_PR_TIMEOUT' : long = 300
  'GLITE_SD_PLUGIN' : string = 'bdii,rgma'
  'GLITE_HOST_KEY' ? string
  'GLITE_HOST_CERT' ? string
  'GLOBUS_LOCATION' ? string
  'CONDORG_INSTALL_PATH' ? string
  'CONDOR_CONFIG' ? string
  'GLITE_USER' ? string = 'glite'
  'X509_CERT_DIR' ? string = '/opt/grid-security/certificates'
  'X509_VOMS_DIR' ? string = '/opt/grid-security/vomses'
  'MYPROXY_TCP_PORT_RANGE' ? string
  'HOSTNAME' ? string
  'WMS_JOBWRAPPER_TEMPLATE' ? string
  'WMS_LOCATION_USR' ? string
  'WMS_LOCATION_BIN' ? string
  'WMS_LOCATION_ETC' ? string
  'WMS_LOCATION_LIBEXEC' ? string
  'WMS_LOCATION_LOG' ? string
  'WMS_LOCATION_SBIN' ? string
  'WMS_LOCATION_TMP' ? string
  'WMS_LOCATION_VAR' ? string
  'GLITE_WMS_CONFIG_DIR' ? string
  'LCG_GFAL_INFOSYS' ? string
  'LD_LIBRARY_PATH' ? string
};

type ${project.artifactId}_component_service_special_dirs = {
  'perms'       : string
};

# Used to describe optional service specific configruation files
# built from a template.
type ${project.artifactId}_component_service_conf_file = {
  'template'       : string
};

type ${project.artifactId}_component_service_common = {
  'name'        : string
  'workDirs'    : string[] = list()
  'specialDirs' ? ${project.artifactId}_component_service_special_dirs{}
  'confFiles'   ? ${project.artifactId}_component_service_conf_file{}
};

type ${project.artifactId}_component_service_ice_opts = {
  'log_on_file'                        ? boolean
  'log_on_console'                     ? boolean
  'listener_port'                      ? long
  'Input'                              ? string
  'InputType'                          ? string
  'logfile'                            ? string
  'start_poller'                       ? boolean
  'purge_jobs'                         ? boolean
  'start_listener'                     ? boolean
  'start_subscription_updater'         ? boolean
  'subscription_update_threshold_time' ? long
  'subscription_duration'              ? long
  'poller_delay'                       ? long
  'poller_status_threshold_time'       ? long
  'start_job_killer'                   ? boolean
  'job_cancellation_threshold_time'    ? long
  'start_proxy_renewer'                ? boolean
  'start_lease_updater'                ? boolean
  'ice_host_cert'                      ? string
  'ice_host_key'                       ? string
  'cream_url_prefix'                   ? string
  'cream_url_postfix'                  ? string
  'creamdelegation_url_prefix'         ? string
  'creamdelegation_url_postfix'        ? string
  'cemon_url_prefix'                   ? string
  'cemon_url_postfix'                  ? string
  'ice_topic'                          ? string
  'lease_delta_time'                   ? long
  'notification_frequency'             ? long
  'ice_log_level'                      ? long
  'listener_enable_authn'              ? boolean
  'listener_enable_authz'              ? boolean
  'max_logfile_size'                   ? long
  'max_logfile_rotations'              ? long
  'max_ice_threads'                    ? long
  'persist_dir'                        ? string
  'soap_timeout'                       ? long
  'proxy_renewal_frequency'            ? long
  'bulk_query_size'                    ? long
  'lease_update_frequency'             ? long
  'max_ice_mem'                        ? long
  'ice_empty_threshold'                ? long
};

type ${project.artifactId}_component_service_ice = {
  include ${project.artifactId}_component_service_common

  'options'     : ${project.artifactId}_component_service_ice_opts
};

type ${project.artifactId}_component_service_jc_opts = {
  'CondorSubmit'   ? string
  'CondorRemove'   ? string
  'CondorQuery'    ? string
  'CondorRelease'  ? string
  'CondorDagman'   ? string

  'SubmitFileDir'  ? string
  'OutputFileDir'  ? string
  'Input'          ? string
  'InputType'      ? string

  'MaximumTimeAllowedForCondorMatch' ? long
  'DagmanMaxPre'   ? long
  'LockFile'       ? string
  'LogFile'        ? string
  'LogLevel'       ? long(1..6)

  'ContainerRefreshThreshold' ? long
};

type ${project.artifactId}_component_service_jc = {
  include ${project.artifactId}_component_service_common

  'options'     : ${project.artifactId}_component_service_jc_opts
};

type ${project.artifactId}_component_service_lbproxy_opts = {
};

type ${project.artifactId}_component_service_lbproxy = {
  include ${project.artifactId}_component_service_common

  'options'     ? ${project.artifactId}_component_service_lbproxy_opts
};

type ${project.artifactId}_component_service_lm_opts = {
  'JobsPerCondorLog'    ? string

  'LockFile'            ? string
  'LogFile'             ? string
  'LogLevel'            ? long(1..6)
  'ExternalLogFile'     ? string

  'MainLoopDuration'    ? long

  'CondorLogDir'        ? string
  'CondorLogRecycleDir' ? string
  'MonitorInternalDir'  ? string
  'IdRepositoryName'   ? string

  'AbortedJobsTimeout' ? long
  'RemoveJobFiles' ? boolean
};

type ${project.artifactId}_component_service_lm = {
  include ${project.artifactId}_component_service_common

  'options'     : ${project.artifactId}_component_service_lm_opts
};

type ${project.artifactId}_component_service_logger_opts = {
};

type ${project.artifactId}_component_service_logger = {
  include ${project.artifactId}_component_service_common

  'options'     ? ${project.artifactId}_component_service_logger_opts
};

type ${project.artifactId}_component_service_ns_opts = {
  'II_Port'                      ? string
  'Gris_Port'                    ? long
  'II_Timeout'                   ? long
  'Gris_Timeout'                 ? long
  'II_DN'                        ? string
  'Gris_DN'                      ? string
  'II_Contact'                   ? string

  'BacklogSize'                  ? long
  'ListeningPort'                ? long
  'MasterThreads'                ? long
  'DispatcherThreads'            ? long
  'SandboxStagingPath'           ? string

  'LogFile'                      ? string
  'LogLevel'                     ? long(1..6)

  'EnableQuotaManagement'        ? boolean
  'MaxInputSandboxSize'          ? long
  'EnableDynamicQuotaAdjustment' ? boolean
  'QuotaAdjustmentAmount'        ? long
  'QuotaInsensibleDiskPortion'   ? long
};

type ${project.artifactId}_component_service_ns = {
  include ${project.artifactId}_component_service_common

  'options'     : ${project.artifactId}_component_service_ns_opts
};

type ${project.artifactId}_component_service_wm_opts = {
  'CeForwardParameters'       ? string
  'CeMonitorAsyncPort'        ? long
  'CeMonitorServices'         ? string{}
  'DispatcherType'            ? string
  'EnableBulkMM'              ? boolean
  'EnableRecovery'            ? boolean
  'ExpiryPeriod'              ? long
  'Input'                     ? string
  'IsmBlackList'              ? string
  'IsmDump'                   ? string
  'IsmIiLDAPCEFilterExt'      ? string
  'IsmIiPurchasingRate'       ? long
  'IsmThreads'                ? boolean
  'IsmUpdateRate'             ? long 
  'JobWrapperTemplateDir'     ? string
  'LogFile'                   ? string
  'LogLevel'                  ? long(1..6)
  'MaxReplansCount'           ? long
  'MatchRetryPeriod'          ? long
  'MaxOutputSandboxSize'      ? long
  'MaxRetryCount'             ? long
  'PropagateToLRMS'           ? string
  'QueueSize'                 ? long
  'ReplanGracePeriod'         ? long
  'RuntimeMalloc'             ? string
  'SbRetryDifferentProtocols' ? boolean
  'WmsRequirements'           ? string
  'WorkerThreads'             ? long
};

type ${project.artifactId}_component_service_wm_jw = {
  'file'     : string
  'contents' : string
};

type ${project.artifactId}_component_service_wm = {
  include ${project.artifactId}_component_service_common

  'jobWrapper'  ? ${project.artifactId}_component_service_wm_jw
  'options'     : ${project.artifactId}_component_service_wm_opts
};

type ${project.artifactId}_component_service_wmproxy_loadmonitor_script = {
  'name'        : string = '/usr/sbin/glite_wms_wmproxy_load_monitor'
};

type ${project.artifactId}_component_service_wmproxy_loadmonitor_opts = {
  'ThresholdCPULoad1'  : long
  'ThresholdCPULoad5'  : long
  'ThresholdCPULoad15' : long
  'ThresholdMemUsage'  : long
  'ThresholdSwapUsage' : long
  'ThresholdFDNum'     : long
  'ThresholdDiskUsage' : long
  'ThresholdFLSize' : long
  'ThresholdFLNum' : long
  'ThresholdJDSize' : long
  'ThresholdJDNum'     : long
  'ThresholdFTPConn'   : long
};

#type component_wmslb_service_wmproxy_operationsloadscripts_opts = {
#  'load1'     ? long
#  'load5'     ? long
#  'load15'    ? long
#  'memusage'  ? long
#  'diskusage' ? long
#  'fdnum'     ? long
#};

type ${project.artifactId}_component_service_wmproxy_opts = {
#  'ApacheLogLevel'               ? string with match(SELF,'emerg|alert|crit|error|warn|notice|info|debug')
  'AsyncJobStart'                ? boolean
#  'DefaultProtocol'              ? string
  'EnableServiceDiscovery'       ? boolean
  'GridFTPPort'                  ? long
#  'HTTPSPort'                    ? long
  'LBLocalLogger'                ? string
  'LBServer'                     ? string
  'LBServiceDiscoveryType'       ? string
  'ListMatchRootPath'            ? string
#  'ListMatchTimeout'             ? long
  'LoadMonitor'                  : ${project.artifactId}_component_service_wmproxy_loadmonitor_opts
  'LogFile'                      ? string
  'LogLevel'                     ? long(1..6)
#  'LBProxy'                      ? boolean
#  'MaxInputSandboxSize'          ? long
  'MaxServedRequests'            ? long
  'MinPerusalTimeInterval'       ? long
#  'OperationLoadScripts'        ? ${project.artifactId}_component_service_wmproxy_operationsloadscripts_opts
  'SandboxStagingPath'           ? string
#  'SDJRequirements'              ? string
  'ServiceDiscoveryInfoValidity' ? long
  'WeightsCacheValidity'         ? long
};

type ${project.artifactId}_component_service_wmproxy = {
  include ${project.artifactId}_component_service_common

  'LoadMonitorScript' : ${project.artifactId}_component_service_wmproxy_loadmonitor_script
  'options'     : ${project.artifactId}_component_service_wmproxy_opts
};

type ${project.artifactId}_component_service_wmsclient_opts = {
  'ErrorStorage' ? string
  'OutputStorage' ? string
  'ListenerStorage' ? string
  'virtualorganisation' ? string
  'rank' ? string
  'requirements' ? string
  'RetryCount' ? long
  'ShallowRetryCount' ? long
  'WMProxyEndPoints' ? string
  'LBAddress' ? string
  'MyProxyServer' ? string
  'JobProvenance' ? string
  'PerusalFileEnable' ? boolean
  'AllowZippedISB' ? boolean
  'LBServiceDiscoveryType' ? string
  'WMProxyServiceDiscoveryType' ? string
};

type ${project.artifactId}_component_service_wmsclient = {
  include ${project.artifactId}_component_service_common

  'options'     ? ${project.artifactId}_component_service_wmsclient_opts
};

type ${project.artifactId}_component_common_opts = {
  'LBProxy'     ? boolean
};

type ${project.artifactId}_component_services = {
  'ice'         ? ${project.artifactId}_component_service_ice
  'jc'          ? ${project.artifactId}_component_service_jc
  'lbproxy'     ? ${project.artifactId}_component_service_lbproxy
  'logger'      ? ${project.artifactId}_component_service_logger
  'lm'          ? ${project.artifactId}_component_service_lm
  'ns'          ? ${project.artifactId}_component_service_ns
  'wm'          ? ${project.artifactId}_component_service_wm
  'wmproxy'     ? ${project.artifactId}_component_service_wmproxy
  'wmsclient'   ? ${project.artifactId}_component_service_wmsclient
};

type ${project.artifactId}_component = {
  include structure_component

  'confFile'  : string = '/opt/glite/etc/glite_wms.conf'
  'env'       ? ${project.artifactId}_component_env
  'envScript' ? string = '/etc/profile.d/glite-wms.sh'
  'services'  ? ${project.artifactId}_component_services
  'common'    ? ${project.artifactId}_component_common_opts
  'workDirDefaultParent' ? string
};

bind '/software/components/wmslb' = ${project.artifactId}_component;
