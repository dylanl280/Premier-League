-- Do fouls cost you the game?
--
-- Short answer: barely. Getting sent off does.
--
-- The raw number looks damning - the side committing more fouls wins only
-- 34.5% and loses 40.6%. Almost all of that is venue. Away sides both foul
-- more (4,925 matches to 4,192) and win less, so the headline mixes the two.
-- Split by venue in query 2 and the foul effect nearly vanishes.
--
-- Fouls data begins in 2000-01; earlier seasons carry none.
-- Causality also runs partly backwards: a team chasing a game defends more
-- and fouls more, so some of what is left is the scoreline causing fouls
-- rather than fouls causing the scoreline.

-- 1. The headline, uncontrolled.
SELECT
    COUNT(*)                                                              AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = ldr) / COUNT(*), 1)     AS fouler_won_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'D') / COUNT(*), 1)     AS drew_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result <> 'D'
                                     AND result <> ldr) / COUNT(*), 1)    AS fouler_lost_pct
FROM (
    SELECT result,
           CASE WHEN home_fouls > away_fouls THEN 'H'
                WHEN away_fouls > home_fouls THEN 'A' END AS ldr
    FROM matches WHERE home_fouls IS NOT NULL
) m
WHERE ldr IS NOT NULL;


-- 2. Controlled for venue. Base rates in this sample: home 45.7%, away 29.5%.
-- Both sides lose roughly two and a half points by fouling more - which is
-- to say, almost nothing.
SELECT
    CASE ldr WHEN 'H' THEN 'HOME fouled more' ELSE 'AWAY fouled more' END AS who,
    COUNT(*)                                                              AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = ldr) / COUNT(*), 1)     AS fouler_won_pct
FROM (
    SELECT result,
           CASE WHEN home_fouls > away_fouls THEN 'H'
                WHEN away_fouls > home_fouls THEN 'A' END AS ldr
    FROM matches WHERE home_fouls IS NOT NULL
) m
WHERE ldr IS NOT NULL
GROUP BY ldr
ORDER BY who DESC;


-- 3. Size of the foul gap barely moves the result: 35.5% at one or two
-- extra fouls, 32.7% at ten or more. Compare the same cut on shots on
-- target, which climbs from 43.8% to 92.2%.
SELECT
    CASE WHEN edge BETWEEN 1 AND 2 THEN '1-2 more fouls'
         WHEN edge BETWEEN 3 AND 5 THEN '3-5 more'
         WHEN edge BETWEEN 6 AND 9 THEN '6-9 more'
         ELSE '10+ more' END                                              AS gap,
    COUNT(*)                                                              AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = ldr) / COUNT(*), 1)     AS fouler_won_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result <> 'D'
                                     AND result <> ldr) / COUNT(*), 1)    AS fouler_lost_pct
FROM (
    SELECT result, ABS(home_fouls - away_fouls) AS edge,
           CASE WHEN home_fouls > away_fouls THEN 'H'
                WHEN away_fouls > home_fouls THEN 'A' END AS ldr
    FROM matches WHERE home_fouls IS NOT NULL
) m
WHERE ldr IS NOT NULL
GROUP BY 1
ORDER BY MIN(edge);


-- 4. The severity ladder. Each figure is the change in win rate against that
-- side's own base rate, so venue is held constant.
--
-- Fouls barely register. Bookings cost a little. A sending-off is the only
-- disciplinary event that decides matches - and unlike the others it is
-- plainly causal, since the team finishes a man short.
WITH base AS (
    SELECT 100.0 * COUNT(*) FILTER (WHERE result = 'H') / COUNT(*) AS home_base,
           100.0 * COUNT(*) FILTER (WHERE result = 'A') / COUNT(*) AS away_base
    FROM matches WHERE home_fouls IS NOT NULL
),
m AS (SELECT * FROM matches WHERE home_fouls IS NOT NULL)
SELECT 'More fouls' AS metric,
    ROUND((100.0 * COUNT(*) FILTER (WHERE home_fouls > away_fouls AND result = 'H')
         / NULLIF(COUNT(*) FILTER (WHERE home_fouls > away_fouls), 0)
         - (SELECT home_base FROM base))::NUMERIC, 1) AS home_lift,
    ROUND((100.0 * COUNT(*) FILTER (WHERE away_fouls > home_fouls AND result = 'A')
         / NULLIF(COUNT(*) FILTER (WHERE away_fouls > home_fouls), 0)
         - (SELECT away_base FROM base))::NUMERIC, 1) AS away_lift
FROM m
UNION ALL
SELECT 'More yellow cards',
    ROUND((100.0 * COUNT(*) FILTER (WHERE home_yellows > away_yellows AND result = 'H')
         / NULLIF(COUNT(*) FILTER (WHERE home_yellows > away_yellows), 0)
         - (SELECT home_base FROM base))::NUMERIC, 1),
    ROUND((100.0 * COUNT(*) FILTER (WHERE away_yellows > home_yellows AND result = 'A')
         / NULLIF(COUNT(*) FILTER (WHERE away_yellows > home_yellows), 0)
         - (SELECT away_base FROM base))::NUMERIC, 1)
FROM m
UNION ALL
SELECT 'More red cards',
    ROUND((100.0 * COUNT(*) FILTER (WHERE home_reds > away_reds AND result = 'H')
         / NULLIF(COUNT(*) FILTER (WHERE home_reds > away_reds), 0)
         - (SELECT home_base FROM base))::NUMERIC, 1),
    ROUND((100.0 * COUNT(*) FILTER (WHERE away_reds > home_reds AND result = 'A')
         / NULLIF(COUNT(*) FILTER (WHERE away_reds > home_reds), 0)
         - (SELECT away_base FROM base))::NUMERIC, 1)
FROM m;
