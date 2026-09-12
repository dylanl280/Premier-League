-- Integrity checks for the built database.
--
--   psql -h localhost -p 5433 -U postgres -d epl -f sql/validate.sql
--
-- Every row should read PASS. Each check is written so that "expected" is a
-- fact about Premier League history, not a number copied from the data.

WITH checks AS (

    SELECT 1 AS seq, 'matches loaded' AS check_name,
           (SELECT COUNT(*) FROM matches)::VARCHAR AS got,
           '12734' AS expected

    UNION ALL SELECT 2, 'team_matches is exactly 2x matches',
           (SELECT COUNT(*) FROM team_matches)::VARCHAR,
           (SELECT (2 * COUNT(*))::VARCHAR FROM matches)

    UNION ALL SELECT 3, 'teams',
           (SELECT COUNT(*) FROM teams)::VARCHAR, '51'

    -- Phantom referees from the 0xa0 corruption would inflate this past 164.
    UNION ALL SELECT 4, 'referees (post-repair)',
           (SELECT COUNT(*) FROM referees)::VARCHAR, '164'

    UNION ALL SELECT 5, 'no referee name has stray whitespace or non-ASCII',
           (SELECT COUNT(*) FROM referees
            WHERE name <> trim(name) OR NOT (name ~ '^[ -~]+$'))::VARCHAR,
           '0'

    -- 380 per completed season, except the 22-team era and the season in progress.
    UNION ALL SELECT 6, 'seasons with unexpected match counts',
           (SELECT COUNT(*) FROM (
                SELECT season FROM matches
                GROUP BY season
                HAVING COUNT(*) <> 380
                   AND season NOT IN ('1993-94', '1994-95')
                   AND season <> (SELECT MAX(season) FROM matches)
            ))::VARCHAR,
           '0'

    -- 22 clubs playing each other twice = 462 matches per season.
    UNION ALL SELECT 7, '22-team seasons at 462 matches each',
           (SELECT COUNT(*) FROM matches WHERE season IN ('1993-94','1994-95'))::VARCHAR,
           '924'

    UNION ALL SELECT 8, 'no orphaned team references',
           (SELECT COUNT(*) FROM matches m
            LEFT JOIN teams h ON m.home_team_id = h.team_id
            LEFT JOIN teams a ON m.away_team_id = a.team_id
            WHERE h.team_id IS NULL OR a.team_id IS NULL)::VARCHAR,
           '0'

    UNION ALL SELECT 9, 'no orphaned referee references',
           (SELECT COUNT(*) FROM matches m
            LEFT JOIN referees r ON m.referee_id = r.referee_id
            WHERE m.referee_id IS NOT NULL AND r.referee_id IS NULL)::VARCHAR,
           '0'

    -- A team never plays itself.
    UNION ALL SELECT 10, 'no self-fixtures',
           (SELECT COUNT(*) FROM matches WHERE home_team_id = away_team_id)::VARCHAR,
           '0'

    UNION ALL SELECT 11, 'points identity (3*won + drawn)',
           (SELECT COUNT(*) FROM season_standings WHERE points <> 3 * won + drawn)::VARCHAR,
           '0'

    -- Every goal scored is a goal conceded by someone else.
    UNION ALL SELECT 12, 'goals balance within each season',
           (SELECT COUNT(*) FROM (
                SELECT season FROM season_standings
                GROUP BY season
                HAVING SUM(goals_for) <> SUM(goals_against)
            ))::VARCHAR,
           '0'

    UNION ALL SELECT 13, 'played = won + drawn + lost',
           (SELECT COUNT(*) FROM season_standings
            WHERE played <> won + drawn + lost)::VARCHAR,
           '0'

    -- Known final tables, as an external reality check.
    UNION ALL SELECT 14, '2020-21 champion',
           (SELECT t.name || ' ' || s.points FROM season_standings s
            JOIN teams t USING (team_id)
            WHERE s.season = '2020-21' AND s.position = 1),
           'Man City 86'

    UNION ALL SELECT 15, '2024-25 champion',
           (SELECT t.name || ' ' || s.points FROM season_standings s
            JOIN teams t USING (team_id)
            WHERE s.season = '2024-25' AND s.position = 1),
           'Liverpool 84'

    -- Referee coverage starts in 2000-01; nothing earlier should have one.
    UNION ALL SELECT 16, 'no referee attached before 2000-01',
           (SELECT COUNT(*) FROM matches
            WHERE referee_id IS NOT NULL AND season < '2000-01')::VARCHAR,
           '0'

    -- Physically impossible: you cannot hit the target more often than you
    -- shoot. Four source matches did; prepare_data.py nulls those counts.
    UNION ALL SELECT 17, 'shots on target never exceed shots',
           (SELECT COUNT(*) FROM matches
            WHERE home_shots_on_target > home_shots
               OR away_shots_on_target > away_shots)::VARCHAR,
           '0'

    -- Equally impossible: goals without a single shot.
    UNION ALL SELECT 18, 'no goals scored from zero shots',
           (SELECT COUNT(*) FROM matches
            WHERE home_shots IS NOT NULL
              AND ((home_goals > 0 AND home_shots = 0)
                OR (away_goals > 0 AND away_shots = 0)))::VARCHAR,
           '0'
)

SELECT
    check_name,
    got,
    expected,
    CASE WHEN got = expected THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY seq;
