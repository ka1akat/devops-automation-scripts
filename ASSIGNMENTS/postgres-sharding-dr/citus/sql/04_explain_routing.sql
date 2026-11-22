-- 1) Request WITH the sharding key (user_id): expect 1 task on 1 worker
EXPLAIN (COSTS OFF)
SELECT m.movie_id, m.title
FROM "user" u
JOIN user_recommendation ur ON ur.user_id = u.user_id
JOIN movie m ON m.movie_id = ur.movie_id
WHERE u.user_id = 'eca7aa28-0553-4105-80dd-0592eff582fd'
  AND ur.period @> NOW()
  AND NOT EXISTS (SELECT 1 FROM reaction r
                  WHERE r.user_id = 'eca7aa28-0553-4105-80dd-0592eff582fd'
                    AND r.movie_id = m.movie_id);

-- 2) Request WITHOUT the sharding key (device_id): expect tasks on all shards
EXPLAIN (COSTS OFF)
SELECT m.movie_id, m.title
FROM "user" u
JOIN user_recommendation ur ON ur.user_id = u.user_id
JOIN movie m ON m.movie_id = ur.movie_id
WHERE u.device_id = '8dd3c9ab-5c5a-4f6c-8dbd-66380dee00ed'
  AND ur.period @> NOW()
  AND NOT EXISTS (SELECT 1 FROM reaction r
                  WHERE r.user_id = u.user_id
                    AND r.device_id = '8dd3c9ab-5c5a-4f6c-8dbd-66380dee00ed'
                    AND r.movie_id = m.movie_id);
