\set n random(1, 1000)
SELECT * FROM get_recommendations_by_device_id((SELECT device_id FROM bench_ids WHERE n = :n));
