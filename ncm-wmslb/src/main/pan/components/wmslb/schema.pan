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
  'GLITE_WMS_LOCATION' : string = '/opt/glite'
  'GLITE_WMS_LOCATION_VAR' ? string
  'GLITE_WMS_TMP' ? string
  'GLITE_WMS_LOG_DESTINATION' ? string
  'GLITE_WMS_USER' ? string
  'GLITE_WMS_GROUP' ? string
  'GLITE_HOST_CERT' ? string
  'GLITE_HOST_KEY' ? string
  'GLITE_WMS_QUERY_TIMEOUT' : long = 300
  'GLITE_WMS_WMPROXY_WEIGHTS_UPPER_LIMIT' : long = 10
  'GLITE_WMS_WMPROXY_MAX_SERVED_REQUESTS' : long = 50
  'GLITE_PR_TIMEOUT' : long = 300
  'GLITE_SD_VO' : string = ''
  'GLITE_SD_PLUGIN' : string = 'bdii,rgma'
  'GLITE_HOST_KEY' ? string
  'GLITE_HOST_CERT' ? string
  'GLOBUS_LOCATION' ? string
  'GT_PROXY_MODE' ? string = 'old'
  'CONDORG_INSTALL_PATH' ? string
  'CONDOR_CONFIG' ? string
  'GLITE_USER' ? string = 'glite'
  'X509_CERT_DIR' ? string = '/opt/grid-security/certificates'
  'X509_VOMS_DIR' ? string = '/opt/grid-security/vomses'
  'MYPROXY_TCP_PORT_RANGE' ? string
  'JAVA_HOME' ? string
  'CONDOR_IDS' ? string
  'LCMAPS_DB_FILE' ? string
  'RGMA_HOME' ? string
  'HOSTNAME' ? string
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
  'InputType'                          ? string
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

  'LockFile'       ? string
  'LogFile'        ? string
  'LogLevel'       ? long

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
  'LogLevel'            ? long
  'ExternalLogFile'     ? string

  'MainLoopDuration'    ? long

  'CondorLogDir'        ? string
  'CondorLogRecycleDir' ? string
  'MonitorInternalDir'  ? string
  'IdRepositoryNamer'   ? string

  'AbortedJobsTimeoutr' ? long
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
  'LogLevel'                     ? long

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
  'CeMonitorAsyncPort' ? long
  #'CeMonitorServices" ? string{}
  'DisablePurchasingFromGris' ? boolean
  'DispatcherType'     ? string
  'DliServiceName'     ? string
  'EnableBulkMM'       ? boolean
  'EnableIsmDump'      ? boolean
  'EnableRecovery'     ? boolean
  'ExpiryPeriod'       ? long
  'Input'              ? string
  'IsmDump'            ? string
  'IsmUpdateRate'      ? string
  'IsmIiPurchasingRate' ? long
  'IsmIiLDAPCEFilterExt' ? string
  'IsmIiLDAPSearchAsync' ? boolean
  'IsmThreads'         ? boolean
  'JobWrapperTemplateDir' ? string
  'LogLevel'           ? long
  'LogFile'            ? string
  'MatchRetryPeriod'   ? long
  'MaxOutputSandboxSize' ? long
  'MaxRetryCount'      ? long
  'MaxShallowRetryCount'      ? long
  'PipeDepth'          ? long
  'SiServiceName'      ? string
  'WorkerThreads'      ? long
  'IsmDumpRate'         ? long
  'IsmIiPurchasingRate' ? long 
  'IsmUpdateRate'       ? long 
  'MinPerusalTimeInterval' ? long
  'QueueSize'          ? long
  'RuntimeMalloc'      ? string
};

type ${project.artifactId}_component_service_wm = {
  include ${project.artifactId}_component_service_common

  'options'     : ${project.artifactId}_component_service_wm_opts
};

type ${project.artifactId}_component_service_wmproxy_loadmonitor_script = {
  'contents'    ? string
  'name'        : string = '/opt/glite/sbin/glite_wms_wmproxy_load_monitor'
  # template is ignored if contents is specified
  'template'    : string = '/opt/glite/sbin/glite_wms_wmproxy_load_monitor.template'
};

type ${project.artifactId}_component_service_wmproxy_loadmonitor_opts = {
  'ThresholdCPULoad1'  ? long = 10
  'ThresholdCPULoad5'  ? long = 10
  'ThresholdCPULoad15' ? long = 10
  'ThresholdDiskUsage' ? long = 95
  'ThresholdFDNum'     ? long = 500
  'ThresholdMemUsage'  ? long = 95
};

type ${project.artifactId}_component_service_wmproxy_opts = {
  'SandboxStagingPath'           ? string
  'LogFile'                      ? string
  'LogLevel'                     ? long
  'MaxInputSandboxSize'          ? long
  'ListMatchRootPath'            ? string
  'ListMatchTimeout'             ? long
  'LBProxy'                      ? boolean
  'HTTPSPort'                    ? long
  'GridFTPPort'                  ? long
  'DefaultProtocol'              ? string
  'LBServer'                     ? string
  'LBLocalLogger'                ? string
  'LoadMonitor'                  : ${project.artifactId}_component_service_wmproxy_loadmonitor_opts
  'MinPerusalTimeInterval'       ? long
  'MaxServedRequests'            ? long
  'AsyncJobStart'                ? boolean
  'SDJRequirements'              ? string
  'EnableServiceDiscovery'       ? boolean
  'LBServiceDiscoveryType'       ? string
  'ServiceDiscoveryInfoValidity' ? long
  #'OperationLoadScripts'        ? string{}
};

type ${project.artifactId}_component_service_wmproxy = {
  include ${project.artifactId}_component_service_common

  'LoadMonitorScript' : ${project.artifactId}_component_service_wmproxy_loadmonitor_script
  'options'     : ${project.artifactId}_component_service_wmproxy_opts
  'drained'     : boolean = false
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
