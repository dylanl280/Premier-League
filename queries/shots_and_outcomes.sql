-- Does the team with more shots win?
--
-- Short answer: 50.1% of the time - but that headline number is confounded
-- and understates the effect. Home sides out-shoot their opponents in 64.6%
-- of matches, so "had more shots" is partly just "was at home". Query 2
-- separates the two, and the effect survives on both sides.
--
-- Ties are excluded throughout: 464 matches had equal shots.

-- 1. The headline. What happens to the side that took more shots.
SELECT
    COUNT(*)                                                            AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = shot_leader) / COUNT(*), 1) AS leader_won_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'D') / COUNT(*), 1)   AS drew_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result <> 'D'
                                     AND result <> shot_leader) / COUNT(*), 1) AS leader_lost_pct
FROM (
    SELECT result,
           CASE WHEN home_shots > away_shots THEN 'H'
                WHEN away_shots > home_shots THEN 'A' END AS shot_leader
    FROM matches WHERE home_shots IS NOT NULL
) m
WHERE shot_leader IS NOT NULL;


-- 2. Controlling for home advantage.
--
-- Compare each row's leader_won_pct against that side's base rate: home
-- teams win 45.6% of all matches, away teams 29.5%. Out-shooting lifts both,
-- and lifts away sides more.
SELECT
    CASE shot_leader WHEN 'H' THEN 'HOME had more shots'
                     WHEN 'A' THEN 'AWAY had more shots' END           AS who,
    COUNT(*)                                                           AS matches,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                 AS pct_of_matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = shot_leader) / COUNT(*), 1) AS leader_won_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'D') / COUNT(*), 1)  AS drew_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result <> 'D'
                                     AND result <> shot_leader) / COUNT(*), 1) AS leader_lost_pct
FROM (
    SELECT result,
           CASE WHEN home_shots > away_shots THEN 'H'
                WHEN away_shots > home_shots THEN 'A' END AS shot_leader
    FROM matches WHERE home_shots IS NOT NULL
) m
WHERE shot_leader IS NOT NULL
GROUP BY shot_leader
ORDER BY who DESC;


-- 3. Shots on target is the far better predictor.
--
-- Restricted to 2013-14 onward so both metrics use one consistent
-- shots-on-target definition; the source redefined that field in 2013-14.
WITH m AS (
    SELECT result,
        CASE WHEN home_shots > away_shots THEN 'H'
             WHEN away_shots > home_shots THEN 'A' END AS shot_leader,
        CASE WHEN home_shots_on_target > away_shots_on_target THEN 'H'
             WHEN away_shots_on_target > home_shots_on_target THEN 'A' END AS sot_leader
    FROM matches
    WHERE home_shots IS NOT NULL AND season >= '2013-14'
)
SELECT 'more total shots' AS metric, COUNT(*) AS decided_matches,
       ROUND(100.0 * COUNT(*) FILTER (WHERE result = shot_leader) / COUNT(*), 1) AS leader_won_pct
FROM m WHERE shot_leader IS NOT NULL
UNION ALL
SELECT 'more shots ON TARGET', COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE result = sot_leader) / COUNT(*), 1)
FROM m WHERE sot_leader IS NOT NULL;


-- 4. Size of the advantage. A narrow shot edge is close to meaningless -
-- a side with 1-3 more shots wins only 41% of the time, below the 45.6%
-- base rate for home teams. It takes a wide margin to mean much.
SELECT
    CASE WHEN edge BETWEEN 1 AND 3  THEN '1-3 more shots'
         WHEN edge BETWEEN 4 AND 7  THEN '4-7 more'
         WHEN edge BETWEEN 8 AND 14 THEN '8-14 more'
         ELSE '15+ more' END                                           AS shot_edge,
    COUNT(*)                                                           AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = leader) / COUNT(*), 1) AS leader_won_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'D') / COUNT(*), 1)  AS drew_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result <> 'D'
                                     AND result <> leader) / COUNT(*), 1) AS leader_lost_pct
FROM (
    SELECT result, ABS(home_shots - away_shots) AS edge,
           CASE WHEN home_shots > away_shots THEN 'H'
                WHEN away_shots > home_shots THEN 'A' END AS leader
    FROM matches WHERE home_shots IS NOT NULL
) m
WHERE leader IS NOT NULL
GROUP BY 1
ORDER BY MIN(edge);
