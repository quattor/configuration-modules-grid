# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/apel/schema;

include { 'quattor/schema' };
include { 'pan/types' };

type structure_apel_db_delete_processor = {
	'cleanAll' : string with match(self, 'yes|no')
};

type structure_apel_cpu_processor = {
	'GIIS' ? type_hostname
	'DefaultCPUSpec' ? string with match(self, '^\d+:\d+$')
};

type structure_apel_event_log_processor = {
	'searchSubDirs' ? string with match(self, 'yes|no')
	'reprocess' ? string with match(self, 'yes|no')
	'Dir' : string
	'ExtraFile' ? string[]
	'Timezone' ? string
};

type structure_apel_gk_log_processor = {
	'SubmitHost' : type_hostname
	'searchSubDirs' ? string with match(self, 'yes|no')
	'reprocess' ? string with match(self, 'yes|no')
	'GKLogs' : string[]
	'MessageLogs' : string[]
};

type structure_apel_blahd_log_processor = {
	'SubmitHost' : type_hostname
	'BlahdLogPrefix' : string
	'BlahdLogDir' : string[]
	'searchSubDirs' : string with match(self, 'yes|no')
	'reprocess' : string with match(self, 'yes|no')
};


type structure_apel_join_processor = {
	'publishGlobalUserName' : string with match(self, 'yes|no')
	'Republish' : string with match(self, 'all|missing|nothing')
};

type structure_apel_file = {
	'enableDebugLogging' ? string with match(self, 'yes|no')
	'inspectTables' ? string with match(self, "yes|no")
	'DBURL' : string
	'DBUsername' : string
	'DBPassword' : string
	'SiteName' : string
	'DBDeleteProcessor' ? structure_apel_db_delete_processor
	'CPUProcessor' ? structure_apel_cpu_processor
	'EventLogProcessor' ? structure_apel_event_log_processor
	'GKLogProcessor' ? structure_apel_gk_log_processor
	'JoinProcessor' ? structure_apel_join_processor
	'BlahdLogProcessor' ? structure_apel_blahd_log_processor
};


type ${project.artifactId}_component = {
	include structure_component
	'configFiles' ? structure_apel_file{}
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
