-- Build the Premier League analysis database.
--
--   Run from the repo root, after `python prepare_data.py`:
--
--       duckdb data/epl.duckdb < sql/build.sql
--
-- The paths below are relative, so the working directory must be the repo
-- root or the parquet will not be found.
--
-- Why the Python step is required first: nine referee values in the Kaggle
-- parquet carry a raw 0xa0 byte, so the file is not valid UTF-8 and DuckDB
-- refuses any query touching that column. prepare_data.py repairs them and
-- writes data/matches_clean.parquet, which is what this script reads.

-- Idempotent: safe to re-run over an existing database.
DROP VIEW  IF EXISTS season_standings;
DROP VIEW  IF EXISTS team_matches;
DROP TABLE IF EXISTS matches;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS referees;

CREATE OR REPLACE TEMP VIEW src AS
    SELECT * FROM 'data/matches_clean.parquet';


-- ---------------------------------------------------------------- dimensions

CREATE TABLE teams (
    team_id        INTEGER PRIMARY KEY,
    name           VARCHAR NOT NULL UNIQUE,
    first_season   VARCHAR NOT NULL,
    last_season    VARCHAR NOT NULL,
    seasons_played INTEGER NOT NULL
);

INSERT INTO teams
WITH sides AS (
    SELECT home_team AS name, season FROM src
    UNION ALL
    SELECT away_team AS name, season FROM src
),
aggregated AS (
    SELECT
        name,
        MIN(season)             AS first_season,
        MAX(season)             AS last_season,
        COUNT(DISTINCT season)  AS seasons_played
    FROM sides
    GROUP BY name
)
SELECT
    ROW_NUMBER() OVER (ORDER BY name) AS team_id,
    name, first_season, last_season, seasons_played
FROM aggregated;


-- Referee data begins in 2000-01, so this covers 10,219 of 12,734 matches.
CREATE TABLE referees (
    referee_id         INTEGER PRIMARY KEY,
    name               VARCHAR NOT NULL UNIQUE,
    first_season       VARCHAR NOT NULL,
    last_season        VARCHAR NOT NULL,
    matches_officiated INTEGER NOT NULL
);

INSERT INTO referees
WITH aggregated AS (
    SELECT
        referee AS name,
        MIN(season) AS first_season,
        MAX(season) AS last_season,
        COUNT(*)    AS matches_officiated
    FROM src
    WHERE referee IS NOT NULL
    GROUP BY referee
)
SELECT
    ROW_NUMBER() OVER (ORDER BY name) AS referee_id,
    name, first_season, last_season, matches_officiated
FROM aggregated;


-- ------------------------------------------------------------------- matches

-- Stays wide, one row per real-world match, mirroring the source. The
-- team_matches view below unpivots it for analysis.
CREATE TABLE matches (
    match_id     INTEGER PRIMARY KEY,
    season       VARCHAR     NOT NULL,
    kickoff      TIMESTAMPTZ NOT NULL,

    home_team_id INTEGER     NOT NULL REFERENCES teams(team_id),
    away_team_id INTEGER     NOT NULL REFERENCES teams(team_id),
    -- NULL for every match before 2000-01, where the source has no referee.
    referee_id   INTEGER              REFERENCES referees(referee_id),

    home_goals   INTEGER     NOT NULL,
    away_goals   INTEGER     NOT NULL,
    result       VARCHAR     NOT NULL,  -- 'H' home win, 'D' draw, 'A' away win

    ht_home_goals INTEGER,
    ht_away_goals INTEGER,
    ht_result     VARCHAR,

    -- Match stats: present from 2000-01 onward, NULL before.
    home_shots            INTEGER,
    away_shots            INTEGER,
    home_shots_on_target  INTEGER,
    away_shots_on_target  INTEGER,
    home_corners          INTEGER,
    away_corners          INTEGER,
    home_fouls            INTEGER,
    away_fouls            INTEGER,
    home_yellows          INTEGER,
    away_yellows          INTEGER,
    home_reds             INTEGER,
    away_reds             INTEGER,

    CHECK (result IN ('H', 'D', 'A')),
    CHECK (home_team_id <> away_team_id)
);

INSERT INTO matches
SELECT
    ROW_NUMBER() OVER (ORDER BY s.kickoff, s.home_team) AS match_id,
    s.season,
    s.kickoff,
    h.team_id,
    a.team_id,
    r.referee_id,
    s.home_goals,
    s.away_goals,
    s.result,
    s.ht_home_goals,
    s.ht_away_goals,
    s.ht_result,
    s.home_shots, s.away_shots,
    s.home_shots_on_target, s.away_shots_on_target,
    s.home_corners, s.away_corners,
    s.home_fouls, s.away_fouls,
    s.home_yellows, s.away_yellows,
    s.home_reds, s.away_reds
FROM src s
JOIN teams h ON s.home_team = h.name
JOIN teams a ON s.away_team = a.name
LEFT JOIN referees r ON s.referee = r.name;

CREATE INDEX idx_matches_season  ON matches(season);
CREATE INDEX idx_matches_referee ON matches(referee_id);
CREATE INDEX idx_matches_home    ON matches(home_team_id);
CREATE INDEX idx_matches_away    ON matches(away_team_id);


-- --------------------------------------------------------------------- views

-- One row per team per match: 2 x matches. Most questions ("how did Arsenal
-- do", "what happens under referee X") are awkward against the wide table
-- because a team appears in either home_team or away_team; here it appears
-- exactly once per match played, with its own stats and the opponent's.
CREATE VIEW team_matches AS
SELECT
    match_id, season, kickoff, referee_id,
    home_team_id AS team_id,
    away_team_id AS opponent_id,
    TRUE          AS is_home,
    home_goals    AS goals_for,
    away_goals    AS goals_against,
    CASE result WHEN 'H' THEN 'W' WHEN 'D' THEN 'D' ELSE 'L' END AS result,
    CASE result WHEN 'H' THEN 3   WHEN 'D' THEN 1   ELSE 0   END AS points,
    home_shots           AS shots,
    home_shots_on_target AS shots_on_target,
    home_corners         AS corners,
    home_fouls           AS fouls,
    home_yellows         AS yellows,
    home_reds            AS reds,
    away_shots           AS opp_shots,
    away_shots_on_target AS opp_shots_on_target,
    away_corners         AS opp_corners,
    away_fouls           AS opp_fouls,
    away_yellows         AS opp_yellows,
    away_reds            AS opp_reds
FROM matches

UNION ALL

SELECT
    match_id, season, kickoff, referee_id,
    away_team_id AS team_id,
    home_team_id AS opponent_id,
    FALSE         AS is_home,
    away_goals    AS goals_for,
    home_goals    AS goals_against,
    CASE result WHEN 'A' THEN 'W' WHEN 'D' THEN 'D' ELSE 'L' END AS result,
    CASE result WHEN 'A' THEN 3   WHEN 'D' THEN 1   ELSE 0   END AS points,
    away_shots           AS shots,
    away_shots_on_target AS shots_on_target,
    away_corners         AS corners,
    away_fouls           AS fouls,
    away_yellows         AS yellows,
    away_reds            AS reds,
    home_shots           AS opp_shots,
    home_shots_on_target AS opp_shots_on_target,
    home_corners         AS opp_corners,
    home_fouls           AS opp_fouls,
    home_yellows         AS opp_yellows,
    home_reds            AS opp_reds
FROM matches;


-- League table per season.
--
-- position orders by points, then goal difference, then goals scored. Those
-- are the real Premier League tiebreakers except the last one: teams level on
-- all three are separated by head-to-head record, which this does not apply.
-- That case is rare and has never decided a title.
--
-- Note 1993-94 and 1994-95 have 42 games per team, not 38 - the league ran 22
-- clubs before shrinking to 20 in 1995-96. Compare eras on points-per-game.
CREATE VIEW season_standings AS
WITH totals AS (
    SELECT
        season,
        team_id,
        COUNT(*)                             AS played,
        COUNT(*) FILTER (WHERE result = 'W') AS won,
        COUNT(*) FILTER (WHERE result = 'D') AS drawn,
        COUNT(*) FILTER (WHERE result = 'L') AS lost,
        -- Cast down from HUGEINT: pandas has no 128-bit integer, so an
        -- uncast SUM() surfaces as a float and points read as "84.0".
        SUM(goals_for)::INTEGER                        AS goals_for,
        SUM(goals_against)::INTEGER                    AS goals_against,
        (SUM(goals_for) - SUM(goals_against))::INTEGER AS goal_diff,
        SUM(points)::INTEGER                           AS points
    FROM team_matches
    GROUP BY season, team_id
)
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY season
        ORDER BY points DESC, goal_diff DESC, goals_for DESC
    ) AS position
FROM totals;
