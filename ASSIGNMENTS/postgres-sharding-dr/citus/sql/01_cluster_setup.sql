-- Tell Citus the coordinator's own address (workers use it to connect back)
SELECT citus_set_coordinator_host('coordinator', 5432);

-- Register the two workers
SELECT citus_add_node('worker1', 5432);
SELECT citus_add_node('worker2', 5432);

-- list of active workers
SELECT * FROM citus_get_active_worker_nodes();
