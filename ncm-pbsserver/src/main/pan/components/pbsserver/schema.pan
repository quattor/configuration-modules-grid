# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

declaration template components/pbsserver/schema;

include { 'quattor/schema' };

type pbs_server_extended_att = {
    'attribute' : string
    'operator' : string with match(SELF, '^(\+\=|\=|\-\=)$')
    'value' : string
};


type pbs_server_attlist = {
    'acl_hosts'           ? string
    'acl_host_enable'     ? boolean = false
    'acl_logic_or'        ? boolean = false
    'acl_roots'           ? string
    'allow_node_submit'   ? boolean = false
    'allow_proxy_user'    ? boolean = false
    'default_node'        ? string
    'default_queue'       ? string
    'job_stat_rate'       ? long(1..) = 150
    'job_nanny'           ? boolean = false
    'log_events'          ? long(0..)
    'log_level'           ? long(0..) = 0 
    'log_file_max_size'   ? long(0..) = 0
    'log_file_roll_depth' ? long(1..) = 10
    'mail_domain'         ? string
    'mail_from'           ? string
    'managers'            ? string
    'mom_job_sync'        ? boolean = true
    'node_check_rate'     ? long(10..) = 600
    'node_pack'           ? boolean
    'node_ping_rate'      ? long(10..) = 300
    'operators'           ? string
    'poll_jobs'           ? boolean = true
    'query_other_jobs'    ? boolean = false
    'resources_available' ? string
    'resources_available.nodect' ? long(1..) = 2048
    'scheduler_iteration' ? long(1..)
    'scheduling'          ? boolean
    'server_name'         ? type_hostname
    'submit_host'         ? string
    'tcp_timeout'         ? long(1..) = 8
};

type pbs_server = {
    'manualconfig' : boolean
    'attlist'      ? pbs_server_attlist
    'extended_att' ? pbs_server_extended_att[0..]
};

type pbs_queue_attlist = {
    'queue_type'             ? string
    'max_running'            ? long(1..)
    'max_queuable'           ? long(1..)
    'resources_available.nodect' ? long(1..) = 2048
    'resources_max.cput'     ? string
    'resources_max.pcput'     ? string
    'resources_max.file' ? string
    'resources_max.mem' ? string
    'resources_max.vmem' ? string
    'resources_max.pmem' ? string
    'resources_max.pvmem' ? string
    'resources_max.nice'     ? long(1..)
    'resources_max.walltime' ? string
    'resources_min.nice'     ? long(1..)
    'resources_min.mem' ? string
    'resources_min.vmem' ? string
    'resources_min.pmem' ? string
    'resources_min.pvmem' ? string
    'resources_max.nodect'   ? long(1..)
    'resources_default.nodect'  ? long(1..)
    'resources_default.nice' ? long(1..)
    'resources_default.mem' ? string
    'resources_default.vmem' ? string
    'resources_default.pmem' ? string
    'resources_default.pvmem' ? string
    'resources_default.neednodes' ? string
    'acl_group_enable'       ? boolean
    'acl_groups'             ? string
    'acl_host_enable'        ? boolean
    'acl_hosts'              ? string
    'acl_user_enable'        ? boolean
    'acl_users'              ? string
    'enabled'                ? boolean
    'started'                ? boolean
    'keep_completed'         ? long(0..)
};

type pbs_queue = {
    'manualconfig' : boolean
    'attlist'      ? pbs_queue_attlist
};

type pbs_queuelist = {
    'manualconfig' : boolean
    'queuelist'    ? pbs_queue{}
};

type pbs_node_attlist = {
    'np'         ? long(1..)
    'properties' ? string
    'state'      ? string with match(SELF,'free|down|offline')
    'ntype'      ? string
};

type pbs_node = {
    'manualconfig' : boolean
    'attlist'      ? pbs_node_attlist
};

type pbs_nodelist = {
    'manualconfig' : boolean
    'nodelist'     ? pbs_node{}
};

type ${project.artifactId}_component = {
    include structure_component
    'pbsroot'      ? string
    'binpath'      ? string
    'submitfilter' ? string
    'env'          ? string{}
    'server'       ? pbs_server
    'queue'        ? pbs_queuelist
    'node'         ? pbs_nodelist
};

bind '/software/components/pbsserver' = ${project.artifactId}_component;
