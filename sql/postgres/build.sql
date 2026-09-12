-- Build the Premier League schema in PostgreSQL.
--
-- Mirrors sql/build.sql (DuckDB) so both databases hold the same shape. The
-- one structural difference: DuckDB reads the parquet directly, while
-- Postgres cannot, so load_postgres.py COPYs the rows into staging_matches
-- first and this script models from there.
--
--   python load_postgres.py        -- loads staging + runs this script
--
-- Run order matters: dimensions before matches, matches before views.

DROP VIEW  IF EXISTS season_standings;
DROP VIEW  IF EXISTS team_matches;
DROP TABLE IF EXISTS matches;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS referees;


-- ---------------------------------------------------------------- dimensions

CREATE TABLE teams (
    team_id        INTEGER PRIMARY KEY,
    name           TEXT    NOT NULL UNIQUE,
    first_season   TEXT    NOT NULL,
    last_season    TEXT    NOT NULL,
    seasons_played INTEGER NOT NULL
);

INSERT INTO teams
WITH sides AS (
    SELECT home_team AS name, season FROM staging_matches
    UNION ALL
    SELECT away_team AS name, season FROM staging_matches
),
aggregated AS (
    SELECT
        name,
        MIN(season)            AS first_season,
        MAX(season)            AS last_season,
        COUNT(DISTINCT season) AS seasons_played
    FROM sides
    GROUP BY name
)
SELECT
    ROW_NUMBER() OVER (ORDER BY name)::INTEGER AS team_id,
    name, first_season, last_season, seasons_played::INTEGER
FROM aggregated;


-- Referee data begins in 2000-01, covering 10,219 of 12,734 matches.
CREATE TABLE referees (
    referee_id         INTEGER PRIMARY KEY,
    name               TEXT    NOT NULL UNIQUE,
    first_season       TEXT    NOT NULL,
    last_season        TEXT    NOT NULL,
    matches_officiated INTEGER NOT NULL
);

INSERT INTO referees
WITH aggregated AS (
    SELECT
        referee     AS name,
        MIN(season) AS first_season,
        MAX(season) AS last_season,
        COUNT(*)    AS matches_officiated
    FROM staging_matches
    WHERE referee IS NOT NULL
    GROUP BY referee
)
SELECT
    ROW_NUMBER() OVER (ORDER BY name)::INTEGER AS referee_id,
    name, first_season, last_season, matches_officiated::INTEGER
FROM aggregated;


-- ------------------------------------------------------------------- matches

CREATE TABLE matches (
    match_id     INTEGER     PRIMARY KEY,
    season       TEXT        NOT NULL,
    kickoff      TIMESTAMPTZ NOT NULL,

    home_team_id INTEGER     NOT NULL REFERENCES teams(team_id),
    away_team_id INTEGER     NOT NULL REFERENCES teams(team_id),
    -- NULL for every match before 2000-01, where the source has no referee.
    referee_id   INTEGER              REFERENCES referees(referee_id),

    home_goals   INTEGER     NOT NULL,
    away_goals   INTEGER     NOT NULL,
    result       TEXT        NOT NULL,  -- 'H' home win, 'D' draw, 'A' away win

    ht_home_goals INTEGER,
    ht_away_goals INTEGER,
    ht_result     TEXT,

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

    CONSTRAINT result_is_valid CHECK (result IN ('H', 'D', 'A')),
    CONSTRAINT no_self_fixture CHECK (home_team_id <> away_team_id)
);

INSERT INTO matches
SELECT
    ROW_NUMBER() OVER (ORDER BY s.kickoff, s.home_team)::INTEGER AS match_id,
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
FROM staging_matches s
JOIN teams h ON s.home_team = h.name
JOIN teams a ON s.away_team = a.name
LEFT JOIN referees r ON s.referee = r.name;

CREATE INDEX idx_matches_season  ON matches(season);
CREATE INDEX idx_matches_referee ON matches(referee_id);
CREATE INDEX idx_matches_home    ON matches(home_team_id);
CREATE INDEX idx_matches_away    ON matches(away_team_id);


-- --------------------------------------------------------------------- views

-- One row per team per match: 2 x matches. Against the wide matches table a
-- club sits in either home_team_id or away_team_id, so any per-team question
-- needs a UNION; here it appears exactly once per match played.
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
-- position orders by points, then goal difference, then goals scored - the
-- real Premier League tiebreakers except head-to-head, which applies only
-- when teams are level on all three and has never decided a title.
--
-- 1993-94 and 1994-95 have 42 games per team, not 38: the league ran 22 clubs
-- before shrinking to 20 in 1995-96. Compare eras on points-per-game.
CREATE VIEW season_standings AS
WITH totals AS (
    SELECT
        season,
        team_id,
        COUNT(*)::INTEGER                             AS played,
        COUNT(*) FILTER (WHERE result = 'W')::INTEGER AS won,
        COUNT(*) FILTER (WHERE result = 'D')::INTEGER AS drawn,
        COUNT(*) FILTER (WHERE result = 'L')::INTEGER AS lost,
        SUM(goals_for)::INTEGER                       AS goals_for,
        SUM(goals_against)::INTEGER                   AS goals_against,
        (SUM(goals_for) - SUM(goals_against))::INTEGER AS goal_diff,
        SUM(points)::INTEGER                          AS points
    FROM team_matches
    GROUP BY season, team_id
)
SELECT
    *,
    ROW_NUMBER() OVER (
        PARTITION BY season
        ORDER BY points DESC, goal_diff DESC, goals_for DESC
    )::INTEGER AS position
FROM totals;
