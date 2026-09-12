-- Has the league stratified? Measured without assuming who the big clubs are.
--
-- Compares the top six of each season against the rest, and tracks how often
-- a side outside the traditional Big Six breaks into the top four.

-- 1. Points gap between the top six and everyone else, per season.
SELECT
    season,
    ROUND(AVG(points) FILTER (WHERE position <= 6)::NUMERIC / MAX(played), 3)  AS top6_ppg,
    ROUND(AVG(points) FILTER (WHERE position > 6)::NUMERIC / MAX(played), 3)   AS rest_ppg,
    ROUND((AVG(points) FILTER (WHERE position <= 6)
         - AVG(points) FILTER (WHERE position > 6))::NUMERIC / MAX(played), 3) AS gap_ppg,
    -- Spread of the whole league: a wider spread means less competitive balance.
    ROUND(STDDEV(points)::NUMERIC / MAX(played), 3)                            AS ppg_stddev
FROM season_standings
GROUP BY season
ORDER BY season;


-- 2. How often does a non-Big-Six club finish in the top four?
SELECT
    season,
    STRING_AGG(t.name, ', ' ORDER BY s.position) AS interlopers_in_top4
FROM season_standings s
JOIN teams t USING (team_id)
WHERE s.position <= 4
  AND t.name NOT IN ('Arsenal','Chelsea','Liverpool','Man City','Man United','Tottenham')
GROUP BY season
ORDER BY season;
