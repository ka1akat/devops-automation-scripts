\set n random(1, 1000)
SELECT * FROM get_recommendations_by_user_id((SELECT user_id FROM bench_ids WHERE n = :n));
