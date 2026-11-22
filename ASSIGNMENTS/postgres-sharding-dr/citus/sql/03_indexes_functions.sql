-- Indexes: from V3__add_indexes.sql
-- CHANGED: user_recommendation is joined by user_id now, so index user_id instead of iin
CREATE INDEX IF NOT EXISTS idx_user_device_id            ON "user" (device_id);
CREATE INDEX IF NOT EXISTS idx_user_user_id              ON "user" (user_id);
CREATE INDEX IF NOT EXISTS idx_user_recommendation_user  ON user_recommendation (user_id);
CREATE INDEX IF NOT EXISTS idx_movie_movie_id            ON movie (movie_id);
CREATE INDEX IF NOT EXISTS idx_reaction_device_movie     ON reaction (device_id, movie_id);
CREATE INDEX IF NOT EXISTS idx_reaction_user_movie       ON reaction (user_id, movie_id);

ANALYZE;

-- Functions: from V4__optimize_recommendation_functions.sql
-- CHANGED: join user_recommendation by user_id (distribution column) instead of iin

CREATE OR REPLACE FUNCTION get_recommendations_by_user_id(p_user_id UUID)
RETURNS TABLE (movie_id UUID, title VARCHAR, genre VARCHAR, release_date DATE)
LANGUAGE plpgsql          -- CHANGED: Citus does not support parameterized SQL functions
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT m.movie_id, m.title, m.genre, m.release_date
    FROM "user" u
    JOIN user_recommendation ur ON ur.user_id = u.user_id
    JOIN movie m ON m.movie_id = ur.movie_id
    WHERE u.user_id = p_user_id
      AND ur.period @> NOW()
      AND NOT EXISTS (
          SELECT 1
          FROM reaction r
          WHERE r.user_id = p_user_id
            AND r.movie_id = m.movie_id
      );
END;
$$;

CREATE OR REPLACE FUNCTION get_recommendations_by_device_id(p_device_id UUID)
RETURNS TABLE (movie_id UUID, title VARCHAR, genre VARCHAR, release_date DATE)
LANGUAGE plpgsql          -- CHANGED: Citus does not support parameterized SQL functions
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT m.movie_id, m.title, m.genre, m.release_date
    FROM "user" u
    JOIN user_recommendation ur ON ur.user_id = u.user_id
    JOIN movie m ON m.movie_id = ur.movie_id
    WHERE u.device_id = p_device_id
      AND ur.period @> NOW()
      AND NOT EXISTS (
          SELECT 1
          FROM reaction r
          WHERE r.user_id = u.user_id
            AND r.device_id = p_device_id
            AND r.movie_id = m.movie_id
      );
END;
$$;