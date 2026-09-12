-- What it takes to win the league, reach Europe, or survive.
--
-- 1993-94 and 1994-95 had 22 clubs and 42 games, so raw points are not
-- comparable across eras. Points-per-game is the honest measure; raw points
-- are shown beside it as the figure people actually quote.

SELECT
    season,
    MAX(played)                                                       AS games,
    MAX(points) FILTER (WHERE position = 1)                           AS champion_pts,
    ROUND((MAX(points) FILTER (WHERE position = 1))::NUMERIC
          / MAX(played), 2)                                           AS champion_ppg,
    MAX(points) FILTER (WHERE position = 4)                           AS fourth_pts,
    MAX(points) FILTER (WHERE position = 17)                          AS survival_pts,
    ROUND((MAX(points) FILTER (WHERE position = 17))::NUMERIC
          / MAX(played), 2)                                           AS survival_ppg,
    -- The highest-placed relegated side: what was not enough that year.
    MAX(points) FILTER (WHERE position = 18)                          AS first_relegated_pts
FROM season_standings
GROUP BY season
ORDER BY season;
