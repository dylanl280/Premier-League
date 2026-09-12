-- Shooting volume and conversion over time.
--
-- Restricted to 2000-01 onward: shot data does not exist before then.
-- The in-progress final season is excluded as a partial sample.
--
-- ---------------------------------------------------------------------
-- WARNING: shots_on_target is NOT comparable across 2013-14.
--
-- The share of shots recorded as on target collapses from 56.6% in
-- 2012-13 to 33.2% in 2013-14 and stays near 33% ever since, while goals
-- per shot barely moves (11.1% -> 10.3%). Shot accuracy does not halve in
-- one summer; the source changed what it counts as on target, most likely
-- by excluding blocked shots.
--
-- So: goals_per_shot_pct is safe to compare across the whole period.
-- on_target_pct and anything derived from shots_on_target are only
-- comparable WITHIN an era, never across 2013-14.
-- ---------------------------------------------------------------------

SELECT
    season,
    CASE WHEN season < '2013-14' THEN 'pre-2013 definition'
         ELSE 'post-2013 definition' END                               AS sot_era,
    COUNT(*)                                                           AS matches,
    ROUND(AVG(home_shots + away_shots)::NUMERIC, 1)                    AS shots_per_match,
    ROUND(AVG(home_goals + away_goals)::NUMERIC, 2)                    AS goals_per_match,
    -- Safe across the whole period.
    ROUND(100.0 * SUM(home_goals + away_goals)
          / NULLIF(SUM(home_shots + away_shots), 0), 1)                AS goals_per_shot_pct,
    -- Compare within an era only.
    ROUND(100.0 * SUM(home_shots_on_target + away_shots_on_target)
          / NULLIF(SUM(home_shots + away_shots), 0), 1)                AS on_target_pct
FROM matches
WHERE season >= '2000-01'
  AND home_shots IS NOT NULL
  AND season < (SELECT MAX(season) FROM matches)
GROUP BY season
ORDER BY season;
