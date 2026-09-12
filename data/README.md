# Data

English Premier League match results, **1993-94 to the current season**
(12,734 matches, 34 seasons). Two files, both originating from
football-data.co.uk:

| File | Seasons | Source |
|---|---|---|
| `results.parquet` | 1993-94 - 2021-22 (partial) | [Kaggle: irkaal/english-premier-league-results](https://www.kaggle.com/datasets/irkaal/english-premier-league-results) |
| `recent.parquet` | 2021-22 - 2026-27 | [football-data.co.uk](https://www.football-data.co.uk/englandm.php), fetched directly |

They overlap on 2021-22. The Kaggle mirror stops on 2022-04-10 with only
309 of that season's 380 matches, so `load_data.py` drops any season that
`recent.parquet` also covers and takes the fetched copy instead.

## Usage

```python
from load_data import load_matches, season_table

df = load_matches()                 # everything, oldest first
df = load_matches(stats_only=True)  # 2000-01 onward, where shot data exists

season_table(df, "2024-25")         # league table for one season
```

Refresh the recent seasons — including the in-progress one — with:

```bash
python update_data.py
```

## Caveats

- **The current season is partial** by definition; it fills in as matches
  are played and you rerun `update_data.py`.
- **No match stats before 2000-01** — shots, corners, fouls and cards are
  null for 1993-94 to 1999-00 (2,824 rows). Use `load_matches(stats_only=True)`
  to drop them.
- **1993-94 and 1994-95 have 462 matches, not 380.** That is correct: the
  league ran 22 teams before shrinking to 20 in 1995-96. Do not treat it
  as a data error.
- The upstream CSVs are cp1252-encoded, not UTF-8, and break `pd.read_csv`
  without `encoding="cp1252"`. Both parquet files are already decoded.

## Columns

`Season`, `DateTime`, `HomeTeam`, `AwayTeam`, `FTHG`/`FTAG`/`FTR` (full
time home goals / away goals / result), `HTHG`/`HTAG`/`HTR` (half time),
`Referee`, and per-side match stats: `HS`/`AS` shots, `HST`/`AST` shots on
target, `HC`/`AC` corners, `HF`/`AF` fouls, `HY`/`AY` yellows, `HR`/`AR` reds.
