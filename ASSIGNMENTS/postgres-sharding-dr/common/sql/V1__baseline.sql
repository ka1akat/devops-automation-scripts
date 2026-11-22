CREATE TABLE public."user" (
    user_id UUID,
    device_id UUID,
    iin VARCHAR(20),
    name VARCHAR(100),
    email VARCHAR(150)
);

INSERT INTO public."user" (user_id, device_id, iin, name, email)
SELECT gen_random_uuid(),
       gen_random_uuid(),
       LPAD((100000000000 + i)::text, 12, '0'),
       'User ' || i,
       'user' || i || '@kbtu.devops'
FROM generate_series(1, 10000) AS i;

CREATE TABLE public.movie (
    movie_id uuid,
    title VARCHAR(255),
    genre VARCHAR(100),
    release_date DATE
);

INSERT INTO public.movie (movie_id, title, genre, release_date)
SELECT gen_random_uuid(),
       'Movie ' || i,
       CASE WHEN i % 3 = 0 THEN 'Action'
            WHEN i % 3 = 1 THEN 'Drama'
            ELSE 'Comedy'
       END,
       CURRENT_DATE - (i % 365) * INTERVAL '1 day'
FROM generate_series(1, 100000) AS i;

CREATE TABLE public.user_recommendation (
    iin VARCHAR(12),
    movie_id UUID,
    period TSTZRANGE
);

INSERT INTO public.user_recommendation (iin, movie_id, period)
SELECT
    u.iin,
    m.movie_id,
    tstzrange(
        NOW() - ((random() * 365)::int * INTERVAL '1 day'),
        NOW() + ((random() * 30)::int * INTERVAL '1 day')
    )
FROM "user" u
CROSS JOIN LATERAL (
    SELECT movie_id
    FROM movie
    ORDER BY random()
    LIMIT 1
) m
WHERE random() < 0.5;

CREATE TABLE public.reaction (
    user_id UUID,
    device_id UUID,
    movie_id UUID,
    reaction_type VARCHAR(50) CHECK (reaction_type IN ('dislike', 'close', 'click')),
    reaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (user_id IS NOT NULL OR device_id IS NOT NULL)
);

DO $$
DECLARE
    batch_size INT := 1000;
    start_index INT := 1;
    end_index INT;
BEGIN
    WHILE start_index <= 100000 LOOP
        end_index := start_index + batch_size - 1;

        INSERT INTO public.reaction (user_id, device_id, movie_id, reaction_type, reaction_date)
        SELECT
            u.user_id,
            u.device_id,
            (SELECT movie_id FROM movie ORDER BY random() LIMIT 1),
            CASE WHEN random() < 0.33 THEN 'dislike'
                 WHEN random() < 0.66 THEN 'close'
                 ELSE 'click'
            END,
            NOW() - (random() * INTERVAL '180 days')
        FROM "user" u
        WHERE random() < 0.5
        LIMIT batch_size;

        start_index := end_index + 1;
    END LOOP;
END $$;
