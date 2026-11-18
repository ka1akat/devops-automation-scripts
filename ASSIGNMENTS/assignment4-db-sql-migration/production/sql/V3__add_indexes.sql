--V3: indexes for recommendation lookups

CREATE INDEX IF NOT EXISTS idx_user_device_id ON "user" (device_id);
CREATE INDEX IF NOT EXISTS idx_user_user_id ON "user" (user_id);
CREATE INDEX IF NOT EXISTS idx_user_recommendation_iin ON user_recommendation (iin);
CREATE INDEX IF NOT EXISTS idx_movie_movie_id ON movie (movie_id);
CREATE INDEX IF NOT EXISTS idx_reaction_device_movie ON reaction (device_id, movie_id);
CREATE INDEX IF NOT EXISTS idx_reaction_user_movie ON reaction (user_id, movie_id);

ANALYZE;
