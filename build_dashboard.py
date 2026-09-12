"""Regenerate the published dashboard from the database.

    python build_dashboard.py

Reads docs/_template.html, queries every figure the page shows, and writes
docs/index.html with the data inlined. GitHub Pages serves that file, so the
published page is rebuilt rather than hand-edited - rerun this after
`python load_postgres.py` and the site follows the data.
"""

import json
from pathlib import Path

import pandas as pd

from db import query

ROOT = Path(__file__).parent
TEMPLATE = ROOT / "docs" / "_template.html"
OUTPUT = ROOT / "docs" / "index.html"
REFEREE_CSV = ROOT / "analysis" / "output" / "b_strictness.csv"


def collect() -> dict:
    """Every figure the dashboard renders, in one payload."""
    data = {}

    data["home_by_season"] = query("""
        SELECT season, COUNT(*) n,
               ROUND(100.0*COUNT(*) FILTER (WHERE result='H')/COUNT(*),1) home,
               ROUND(100.0*COUNT(*) FILTER (WHERE result='D')/COUNT(*),1) draw,
               ROUND(100.0*COUNT(*) FILTER (WHERE result='A')/COUNT(*),1) away,
               ROUND(AVG(home_goals-away_goals)::NUMERIC,3) margin
        FROM matches GROUP BY season ORDER BY season
    """).to_dict("records")

    # 2019-20 was behind closed doors only from March, so it is kept apart
    # from 2020-21; combining them halves the apparent crowd effect.
    data["covid"] = query("""
        SELECT era, matches, home_win_pct, away_win_pct,
               home_margin, home_foul_edge, home_card_edge
        FROM (
          SELECT CASE WHEN season='2020-21' THEN 'Empty stadiums (2020-21)'
                      WHEN season='2019-20' THEN 'Part-empty (2019-20)'
                      WHEN season BETWEEN '2014-15' AND '2018-19' THEN 'Before (2014-19)'
                      ELSE 'Crowds back (2021-)' END era,
                 CASE WHEN season BETWEEN '2014-15' AND '2018-19' THEN 1
                      WHEN season='2019-20' THEN 2
                      WHEN season='2020-21' THEN 3 ELSE 4 END ord,
                 COUNT(*) matches,
                 ROUND(100.0*COUNT(*) FILTER (WHERE result='H')/COUNT(*),1) home_win_pct,
                 ROUND(100.0*COUNT(*) FILTER (WHERE result='A')/COUNT(*),1) away_win_pct,
                 ROUND(AVG(home_goals-away_goals)::NUMERIC,3) home_margin,
                 ROUND(AVG(home_fouls-away_fouls)::NUMERIC,3) home_foul_edge,
                 ROUND(AVG(home_yellows-away_yellows)::NUMERIC,3) home_card_edge
          FROM matches WHERE season>='2014-15' GROUP BY 1,2
        ) t ORDER BY ord
    """).to_dict("records")

    data["thresholds"] = query("""
        SELECT s.season, MAX(s.played) games,
               MAX(t.name)   FILTER (WHERE s.position=1)  champion,
               MAX(s.points) FILTER (WHERE s.position=1)  champ,
               MAX(s.points) FILTER (WHERE s.position=4)  fourth,
               MAX(s.points) FILTER (WHERE s.position=17) safe,
               MAX(s.points) FILTER (WHERE s.position=18) relegated
        FROM season_standings s
        JOIN teams t USING (team_id)
        GROUP BY s.season
        HAVING MAX(s.played) >= 38 ORDER BY s.season
    """).to_dict("records")

    # Promotion inferred from presence: a club absent the previous season
    # came up, and one absent the following season went straight back down.
    data["promoted"] = query("""
        WITH o AS (SELECT season, ROW_NUMBER() OVER (ORDER BY season) n
                   FROM (SELECT DISTINCT season FROM matches) s),
        a AS (SELECT DISTINCT tm.season, tm.team_id, o.n
              FROM team_matches tm JOIN o USING (season)),
        p AS (SELECT x.* FROM a x WHERE x.n>1
              AND NOT EXISTS (SELECT 1 FROM a y WHERE y.n=x.n-1 AND y.team_id=x.team_id))
        SELECT (LEFT(p.season,4)::INT/5)*5 era, COUNT(*) promoted,
               COUNT(*) FILTER (WHERE NOT EXISTS (
                   SELECT 1 FROM a z WHERE z.n=p.n+1 AND z.team_id=p.team_id)) relegated,
               ROUND(100.0*COUNT(*) FILTER (WHERE NOT EXISTS (
                   SELECT 1 FROM a z WHERE z.n=p.n+1 AND z.team_id=p.team_id))/COUNT(*),0) pct
        FROM p WHERE p.n < (SELECT MAX(n) FROM o)
        GROUP BY 1 ORDER BY 1
    """).to_dict("records")

    if REFEREE_CSV.exists():
        strictness = pd.read_csv(REFEREE_CSV).sort_values("vs_average")
        data["referee_strictness"] = strictness[
            ["referee", "matches", "vs_average", "ci_low", "ci_high", "p_fdr", "significant"]
        ].round(3).to_dict("records")
    else:
        data["referee_strictness"] = []

    # Compact match index for the finder: team names interned, matches as
    # flat arrays of [date, homeIdx, awayIdx, homeGoals, awayGoals].
    fixtures = query("""
        SELECT to_char(m.kickoff,'YYYY-MM-DD') d, h.name hm, a.name aw,
               m.home_goals hg, m.away_goals ag
        FROM matches m
        JOIN teams h ON m.home_team_id = h.team_id
        JOIN teams a ON m.away_team_id = a.team_id
        ORDER BY m.kickoff
    """)

    names = sorted(set(fixtures.hm) | set(fixtures.aw))
    index = {name: i for i, name in enumerate(names)}

    data["teams"] = names
    data["matches"] = [
        [r.d, index[r.hm], index[r.aw], int(r.hg), int(r.ag)]
        for r in fixtures.itertuples()
    ]

    return data


def main() -> None:
    print("Querying...")
    data = collect()
    print(f"  {len(data['matches']):,} matches, {len(data['teams'])} clubs, "
          f"{len(data['home_by_season'])} seasons")

    payload = json.dumps(data, separators=(",", ":"), default=str)
    # A literal </script> inside the JSON would close the block early, so
    # escape every "<" as < - JSON.parse turns it back into "<".
    payload = payload.replace("<", "\\u003c")
    json.loads(payload)

    html = TEMPLATE.read_text(encoding="utf-8")
    if "__DATA__" not in html:
        raise SystemExit(f"{TEMPLATE} has no __DATA__ placeholder")

    OUTPUT.write_text(html.replace("__DATA__", payload), encoding="utf-8")
    print(f"\nWrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size/1024:.0f} KB)")


if __name__ == "__main__":
    main()
