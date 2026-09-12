-- Referee exploration.
--
-- In VS Code with the DuckDB extension: put the cursor in a statement and
-- press Ctrl+Shift+Enter to run just that one. Ctrl+Enter runs the file.
--
-- Referee data starts in 2000-01 and covers 10,219 of 12,734 matches.
-- Median referee has only 11 matches, so every query here filters on a
-- minimum sample. Treat anything below ~100 matches as noise.


-- 1. Who officiates the most? Sanity check that the encoding repair worked:
-- a duplicated referee would show up here as two near-identical names.
SELECT name, matches_officiated, first_season, last_season
FROM referees
ORDER BY matches_officiated DESC
LIMIT 20;


-- 2. Home/away card asymmetry - the cleanest bias signal available.
--
-- Within a single match the same referee books both sides, so fixture
-- quality and importance largely cancel out. Negative means the referee
-- booked away players more often than home players.
SELECT
    r.name,
    r.matches_officiated                                  AS matches,
    ROUND(AVG(m.home_yellows), 2)                         AS home_yel,
    ROUND(AVG(m.away_yellows), 2)                         AS away_yel,
    ROUND(AVG(m.home_yellows - m.away_yellows), 3)        AS home_card_edge,
    ROUND(STDDEV(m.home_yellows - m.away_yellows)
          / SQRT(COUNT(*)), 3)                            AS std_error
FROM matches m
JOIN referees r USING (referee_id)
WHERE m.home_yellows IS NOT NULL
GROUP BY r.name, r.matches_officiated
HAVING COUNT(*) >= 100
ORDER BY home_card_edge;


-- 3. The league baseline the above should be read against.
SELECT
    ROUND(AVG(home_yellows), 3)                AS avg_home_yellows,
    ROUND(AVG(away_yellows), 3)                AS avg_away_yellows,
    ROUND(AVG(home_yellows - away_yellows), 3) AS league_home_card_edge
FROM matches
WHERE home_yellows IS NOT NULL;


-- 4. Strictness: cards and fouls per match, and cards per foul.
-- Cards per foul separates a strict referee from a chaotic match.
SELECT
    r.name,
    COUNT(*)                                                    AS matches,
    ROUND(AVG(m.home_yellows + m.away_yellows), 2)              AS yellows_pm,
    ROUND(AVG(m.home_reds + m.away_reds), 3)                    AS reds_pm,
    ROUND(AVG(m.home_fouls + m.away_fouls), 1)                  AS fouls_pm,
    ROUND(SUM(m.home_yellows + m.away_yellows)
          / NULLIF(SUM(m.home_fouls + m.away_fouls), 0), 4)     AS cards_per_foul
FROM matches m
JOIN referees r USING (referee_id)
WHERE m.home_yellows IS NOT NULL
GROUP BY r.name
HAVING COUNT(*) >= 100
ORDER BY yellows_pm DESC;


-- 5. Raw home-win rate by referee.
--
-- Deliberately included as the WRONG answer to "do referees affect
-- outcomes". Referees are not randomly assigned - senior referees get the
-- big fixtures - so this mostly measures which matches they were given.
-- Compare against the league rate below before drawing any conclusion.
SELECT
    r.name,
    COUNT(*)                                                       AS matches,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m.result = 'H') / COUNT(*), 1) AS home_win_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m.result = 'D') / COUNT(*), 1) AS draw_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE m.result = 'A') / COUNT(*), 1) AS away_win_pct
FROM matches m
JOIN referees r USING (referee_id)
GROUP BY r.name
HAVING COUNT(*) >= 100
ORDER BY home_win_pct DESC;


-- 6. League-wide home win rate, for the same era referees cover.
SELECT
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'H') / COUNT(*), 1) AS home_win_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'D') / COUNT(*), 1) AS draw_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'A') / COUNT(*), 1) AS away_win_pct,
    COUNT(*)                                                          AS matches
FROM matches
WHERE referee_id IS NOT NULL;


-- 7. Evidence that referee assignment is not random: how concentrated is
-- each referee's workload on the biggest clubs? A referee who draws far
-- more Big Six fixtures than average is not officiating a random sample.
WITH big_six AS (
    SELECT team_id FROM teams
    WHERE name IN ('Arsenal','Chelsea','Liverpool','Man City','Man United','Tottenham')
)
SELECT
    r.name,
    COUNT(*) AS matches,
    ROUND(100.0 * COUNT(*) FILTER (
        WHERE m.home_team_id IN (SELECT team_id FROM big_six)
           OR m.away_team_id IN (SELECT team_id FROM big_six)
    ) / COUNT(*), 1) AS pct_involving_big_six
FROM matches m
JOIN referees r USING (referee_id)
GROUP BY r.name
HAVING COUNT(*) >= 100
ORDER BY pct_involving_big_six DESC;
