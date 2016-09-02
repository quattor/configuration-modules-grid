use strict;
use warnings;

BEGIN {
    *CORE::GLOBAL::sleep = sub {};
}

use Test::More;
use CAF::Object;
use Test::Quattor qw(simple);
use NCM::Component::pbsserver;


use Readonly;

# Very minimal server config
Readonly my $PRINT_SERVER => <<'EOF';

create queue q24h
set queue q24h queue_type = Execution
set queue q24h Priority = 60

create queue default
set queue default queue_type = Route
set queue default route_destinations = short
set queue default route_destinations += long
set queue default enabled = True
set queue default started = True


set server scheduling = True
set server acl_host_enable = False
set server acl_hosts = localhost
set server acl_hosts += some.server
set server to = remove

EOF

Readonly my $PBSNODES => <<'EOF';
node0.example.com
    state = job-exclusive
    power_state = Running
    np = 20
    properties = prop1,prop2
    ntype = cluster
    jobs = 10-19/123.master.example.comf,0-9/456.master.example.com
    status = rectime=some,garbage
    mom_service_port = 15002
    mom_manager_port = 15003
    total_sockets = 2
    total_numa_nodes = 4
    total_cores = 20
    total_threads = 20
    dedicated_sockets = 0
    dedicated_numa_nodes = 0
    dedicated_cores = 0
    dedicated_threads = 20

node1.example.com
    state = job-exclusive
    power_state = Running
    np = 20
    properties = prop1,prop2
    ntype = cluster
    jobs = 10-19/123.master.example.comf,0-9/456.master.example.com
    status = rectime=some,garbage
    mom_service_port = 15002
    mom_manager_port = 15003
    total_sockets = 2
    total_numa_nodes = 4
    total_cores = 20
    total_threads = 20
    dedicated_sockets = 0
    dedicated_numa_nodes = 0
    dedicated_cores = 0
    dedicated_threads = 20
EOF

$CAF::Object::NoAction = 1;

set_caf_file_close_diff(1);

my $cfg = get_config_for_profile('simple');
my $cmp = NCM::Component::pbsserver->new('simple');

set_file_contents("/var/spool/maui/maui.cfg", "something");

# Set expected binaries
set_file_contents("/usr/bin/qmgr", "qmgr");
set_file_contents("/usr/bin/pbsnodes", "pbsnodes");

# Only has to exist, content is not actually used
set_file_contents("/var/spool/pbs/server_priv/nodes", "all nodes");

set_desired_output('/usr/bin/qmgr -c print server', $PRINT_SERVER);
set_desired_output('/usr/bin/pbsnodes -a', $PBSNODES);

command_history_reset();
$cmp->set_qmgr('/usr/bin/qmgr');
diag explain $cmp->get_current_config();
is_deeply($cmp->get_current_config(), {
    satt => {
        scheduling => 1,
        acl_host_enable => 1,
        acl_hosts => 1,
        to => 1,
    },
    queues => {
        default => {
            enabled => 1,
            queue_type => 1,
            route_destinations => 1,
            started => 1,
        },
        q24h => {
            Priority => 1,
            queue_type => 1,
        },
    },
}, "Current config from PRINT_SERVER");
ok(command_history_ok(['qmgr -c print server']), "expected commands for get_current_config");

command_history_reset();
is($cmp->Configure($cfg), 1, "Component runs correctly with a test profile");

my $fh = get_file("/var/spool/pbs/server_name");
is("$fh", "master.example.com\n", "server_name file created");

ok(command_history_ok([
    # missing serverdb
    'service pbs_server stop',
    '/usr/sbin/pbs_server -d /var/spool/pbs -t create -f',
    'service pbs_server start',
    # current config
    'qmgr -c print server',
    # set/unset server attributes
    'qmgr -c set server down_on_error = 1',
    'qmgr -c set server scheduling = 1',
    'qmgr -c set server server_name = master.example.com',
    'qmgr -c unset server acl_host_enable',
    'qmgr -c unset server to',
    # restart due to changed server_name
    'service pbs_server restart',
    # queues
    'qmgr -c print server',
    'qmgr -c set queue default queue_type = Route',
    'qmgr -c set queue default route_destinations = "short,long"',
    'qmgr -c set queue default enabled = 1',
    'qmgr -c set queue default started = 1',
    'qmgr -c create queue q72h',
    'qmgr -c set queue q72h Priority = 60',
    'qmgr -c set queue q72h acl_group_enable = 1',
    'qmgr -c set queue q72h acl_group_sloppy = 1',
    'qmgr -c set queue q72h acl_groups = "gpilot,wheel"',
    'qmgr -c set queue q72h queue_type = Execution',
    'qmgr -c set queue q72h enabled = 1',
    'qmgr -c delete queue q24h',
    # node state
    'pbsnodes -a',
    'qmgr -c set node node1.example.com np = 20',
    'qmgr -c set node node1.example.com properties \+= prop3',
    "qmgr -c set node node1.example.com properties -= 'prop1'",
    'qmgr -c create node node2.example.com',
    'qmgr -c set node node2.example.com np = 22',
    'qmgr -c set node node2.example.com properties \+= prop3',
    'qmgr -c set node node2.example.com properties \+= prop4',
    'qmgr -c delete node node0.example.com',
], [
    # protected attributes
    'qmgr -c .*? node1.example.com.*(status|(total|dedicated)_(sockets|numa_nodes|cores|threads))',
]), "expected configure commands");


done_testing;
