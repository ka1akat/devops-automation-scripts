-- Tables: same as V1__baseline.sql, with changes for sharding by user_id

CREATE TABLE "user" (
    user_id   UUID NOT NULL,
    device_id UUID,
    iin       VARCHAR(20),
    name      VARCHAR(100),
    email     VARCHAR(150)
);

CREATE TABLE movie (
    movie_id     UUID,
    title        VARCHAR(255),
    genre        VARCHAR(100),
    release_date DATE
);

CREATE TABLE user_recommendation (
    user_id  UUID NOT NULL,          -- NEW: added so rows can be placed by user_id
    iin      VARCHAR(12),
    movie_id UUID,
    period   TSTZRANGE
);

CREATE TABLE reaction (
    user_id       UUID NOT NULL,     -- CHANGED: was nullable
    device_id     UUID,
    movie_id      UUID,
    reaction_type VARCHAR(50) CHECK (reaction_type IN ('dislike', 'close', 'click')),
    reaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

