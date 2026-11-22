\echo '--- BEFORE: shards of "user" per worker'
SELECT nodename, count(*) AS shards FROM citus_shards
WHERE table_name = '"user"'::regclass GROUP BY 1 ORDER BY 1;

SELECT now() AS add_node_at;
SELECT citus_add_node('worker3', 5432);

SELECT now() AS rebalance_start_at;
-- tables have no primary key -> logical (non-blocking) transfer is not possible;
-- block_writes: reads continue, writes to a moving shard wait until it is copied
SELECT citus_rebalance_start(shard_transfer_mode := 'block_writes');
SELECT citus_rebalance_wait();
SELECT now() AS rebalance_done_at;

\echo '--- AFTER: shards of "user" per worker'
SELECT nodename, count(*) AS shards FROM citus_shards
WHERE table_name = '"user"'::regclass GROUP BY 1 ORDER BY 1;

\echo '--- AFTER: users per worker'
SELECT s.nodename, sum(r.result::int) AS users
FROM run_command_on_shards('"user"', $$SELECT count(*) FROM %s$$) r
JOIN citus_shards s ON s.shardid = r.shardid
GROUP BY s.nodename ORDER BY 1;
