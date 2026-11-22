--V2:recommendation functions, naive version (baseline for performance comparison)

CREATE OR REPLACE FUNCTION get_recommendations_by_device_id(p_device_id UUID)
RETURNS TABLE (movie_id UUID, title VARCHAR, genre VARCHAR, release_date DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT m.movie_id, m.title, m.genre, m.release_date
    FROM "user" u
    JOIN user_recommendation ur ON ur.iin = u.iin
    JOIN movie m ON m.movie_id = ur.movie_id
    WHERE u.device_id = p_device_id
      AND ur.period @> NOW()
      AND m.movie_id NOT IN (
          SELECT r.movie_id
          FROM reaction r
          WHERE r.device_id = p_device_id
      );
END;
$$;

CREATE OR REPLACE FUNCTION get_recommendations_by_user_id(p_user_id UUID)
RETURNS TABLE (movie_id UUID, title VARCHAR, genre VARCHAR, release_date DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT m.movie_id, m.title, m.genre, m.release_date
    FROM "user" u
    JOIN user_recommendation ur ON ur.iin = u.iin
    JOIN movie m ON m.movie_id = ur.movie_id
    WHERE u.user_id = p_user_id
      AND ur.period @> NOW()
      AND m.movie_id NOT IN (
          SELECT r.movie_id
          FROM reaction r
          WHERE r.user_id = p_user_id
      );
END;
$$;