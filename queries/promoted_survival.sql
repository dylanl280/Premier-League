-- Do promoted clubs still stand a chance?
--
-- Promotion is inferred from presence, not from an external source: a club
-- in season N that was absent in N-1 came up. Survival likewise - it stayed
-- up if it appears again in N+1. The final season is excluded, since nobody
-- can be observed surviving it yet.

WITH ordered AS (
    SELECT season, ROW_NUMBER() OVER (ORDER BY season) AS n
    FROM (SELECT DISTINCT season FROM matches) s
),
appearances AS (
    SELECT DISTINCT tm.season, tm.team_id, o.n
    FROM team_matches tm JOIN ordered o USING (season)
),
last_season AS (SELECT MAX(n) AS n FROM ordered),
promoted AS (
    SELECT a.season, a.team_id, a.n
    FROM appearances a
    WHERE a.n > 1
      AND NOT EXISTS (
          SELECT 1 FROM appearances p WHERE p.n = a.n - 1 AND p.team_id = a.team_id)
)
SELECT
    p.season,
    COUNT(*)                                                        AS promoted,
    ROUND(AVG(s.points), 1)                                         AS avg_points,
    ROUND(AVG(s.points)::NUMERIC / AVG(s.played), 2)                AS avg_ppg,
    ROUND(AVG(s.position), 1)                                       AS avg_position,
    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1 FROM appearances nx
        WHERE nx.n = p.n + 1 AND nx.team_id = p.team_id))           AS relegated_immediately
FROM promoted p
JOIN season_standings s ON s.season = p.season AND s.team_id = p.team_id
WHERE p.n < (SELECT n FROM last_season)
GROUP BY p.season, p.n
ORDER BY p.season;
