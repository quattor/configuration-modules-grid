object template simple;

# mock pkg_repl
function pkg_repl = { null; };

include 'components/pbsserver/config';

# remove the dependencies
'/software/components/pbsserver/dependencies' = null;

"/software/components/pbsserver/pbsroot" = '/var/spool/pbs';

"/software/components/pbsserver/server/manualconfig" = false;
prefix "/software/components/pbsserver/server/attlist";
"server_name" = "master.example.com";
"down_on_error" = true;
"scheduling" = true;

"/software/components/pbsserver/queue/manualconfig" = false;
prefix "/software/components/pbsserver/queue/queuelist/default";
"attlist/enabled" = true;
"attlist/queue_type" = "Route";
"attlist/route_destinations" = '"short,long"';
"attlist/started" = true;
"manualconfig" = false;

prefix "/software/components/pbsserver/queue/queuelist/q72h";
"attlist/Priority" = 60;
"attlist/acl_group_enable" = true;
"attlist/acl_group_sloppy" = true;
"attlist/acl_groups" = '"gpilot,wheel"';
"attlist/enabled" = true;
"attlist/queue_type" = "Execution";
"manualconfig" = false;

"/software/components/pbsserver/node/manualconfig" = false;
prefix "/software/components/pbsserver/node/nodelist/node1.example.com";
"attlist/np" = 20;
"attlist/properties" = 'prop2,prop3';
"manualconfig" = false;
prefix "/software/components/pbsserver/node/nodelist/node2.example.com";
"attlist/np" = 22;
"attlist/properties" = 'prop3,prop4';
"manualconfig" = false;
