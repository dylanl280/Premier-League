-- Home advantage over time, and what happened when the crowds went away.
--
-- 2020-21 was played almost entirely behind closed doors. 2019-20 only was
-- from March 2020, so the two must be kept apart: lumping them together
-- halves the apparent effect. This is a natural experiment on crowd effect
-- that no observational study could have arranged deliberately.

-- 1. Home win rate and goal margin by season.
SELECT
    season,
    COUNT(*)                                                            AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'H') / COUNT(*), 1)   AS home_win_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'D') / COUNT(*), 1)   AS draw_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'A') / COUNT(*), 1)   AS away_win_pct,
    ROUND(AVG(home_goals - away_goals)::NUMERIC, 3)                     AS avg_home_margin,
    ROUND(AVG(CASE result WHEN 'H' THEN 3 WHEN 'D' THEN 1 ELSE 0 END)::NUMERIC, 3) AS home_ppg
FROM matches
GROUP BY season
ORDER BY season;


-- 2. The crowd effect, with the two pandemic seasons kept separate.
--
-- home_foul_edge is the mechanism test: if crowd pressure on officials is
-- part of home advantage, the foul gap should move with the crowds. It does
-- more than move - in the empty season it reverses sign.
SELECT era, matches, home_win_pct, away_win_pct, home_margin,
       home_ppg, home_card_edge, home_foul_edge
FROM (
    SELECT
        CASE
            WHEN season = '2020-21'                     THEN '2020-21 (fully empty)'
            WHEN season = '2019-20'                     THEN '2019-20 (empty from Mar)'
            WHEN season BETWEEN '2014-15' AND '2018-19' THEN 'before (5 seasons)'
            ELSE 'after (crowds back)'
        END AS era,
        CASE
            WHEN season BETWEEN '2014-15' AND '2018-19' THEN 1
            WHEN season = '2019-20'                     THEN 2
            WHEN season = '2020-21'                     THEN 3
            ELSE 4
        END AS ord,
        COUNT(*)                                                          AS matches,
        ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'H') / COUNT(*), 1) AS home_win_pct,
        ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'A') / COUNT(*), 1) AS away_win_pct,
        ROUND(AVG(home_goals - away_goals)::NUMERIC, 3)                   AS home_margin,
        ROUND(AVG(CASE result WHEN 'H' THEN 3 WHEN 'D' THEN 1 ELSE 0 END)::NUMERIC, 3) AS home_ppg,
        ROUND(AVG(home_yellows - away_yellows)::NUMERIC, 3)               AS home_card_edge,
        ROUND(AVG(home_fouls - away_fouls)::NUMERIC, 3)                   AS home_foul_edge
    FROM matches
    WHERE season >= '2014-15'
    GROUP BY 1, 2
) eras
ORDER BY ord;
