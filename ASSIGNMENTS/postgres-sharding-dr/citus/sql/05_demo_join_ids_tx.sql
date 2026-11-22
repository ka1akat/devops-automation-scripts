\echo '=== 1. JOINS ==='
\echo '--- co-located join by user_id + reference table movie: WORKS'
SELECT m.genre, count(*) AS recommendations
FROM user_recommendation ur
JOIN "user" u ON u.user_id = ur.user_id
JOIN movie m  ON m.movie_id = ur.movie_id
GROUP BY m.genre ORDER BY 1;

\echo '--- join by iin (not the distribution column): REJECTED by Citus (limitation)'
SELECT count(*) FROM "user" u JOIN user_recommendation ur ON ur.iin = u.iin;

\echo '=== 2. UNIQUE IDS ==='
SELECT count(*) AS users, count(DISTINCT user_id) AS distinct_ids FROM "user";
INSERT INTO "user" (user_id, device_id, iin, name, email)
VALUES (gen_random_uuid(), gen_random_uuid(), '999999999999', 'Demo User', 'demo@kbtu.devops')
RETURNING user_id AS new_user \gset
SELECT :'new_user' AS new_user_id, nodename
FROM citus_shards
WHERE shardid = get_shard_id_for_distribution_column('"user"', :'new_user'::uuid);

\echo '=== 3. TRANSACTIONS ACROSS TWO WORKERS ==='
-- u1 is on worker1 (see results/explain_routing.txt), u2 is on worker2 (found earlier)
\set u1 'eca7aa28-0553-4105-80dd-0592eff582fd'
\set u2 'dc249947-30d6-4c23-b00b-a8e6cd7de1f4'
\echo 'u1 (worker1) =' :u1
\echo 'u2 (worker2) =' :u2

\echo '--- 3a. second insert breaks CHECK -> whole transaction rolled back on BOTH workers'
BEGIN;
INSERT INTO reaction (user_id, reaction_type, reaction_date) VALUES (:'u1', 'click', '2000-01-01');
INSERT INTO reaction (user_id, reaction_type, reaction_date) VALUES (:'u2', 'WRONG', '2000-01-01');
COMMIT;
SELECT count(*) AS demo_rows_after_failed_tx FROM reaction WHERE reaction_date = '2000-01-01';

\echo '--- 3b. both inserts valid -> committed on BOTH workers (two-phase commit)'
BEGIN;
INSERT INTO reaction (user_id, reaction_type, reaction_date) VALUES (:'u1', 'click', '2000-01-01');
INSERT INTO reaction (user_id, reaction_type, reaction_date) VALUES (:'u2', 'close', '2000-01-01');
COMMIT;
SELECT count(*) AS demo_rows_after_ok_tx FROM reaction WHERE reaction_date = '2000-01-01';

\echo '--- cleanup demo rows'
DELETE FROM reaction WHERE reaction_date = '2000-01-01';
DELETE FROM "user"   WHERE iin = '999999999999';