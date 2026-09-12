# Data

`results.parquet` — English Premier League match results, 1993-94 to a
partial 2021-22 (11,113 matches, 29 seasons, last match 2022-04-10).

## Source

Kaggle: [irkaal/english-premier-league-results](https://www.kaggle.com/datasets/irkaal/english-premier-league-results),
which republishes match data from [football-data.co.uk](https://www.football-data.co.uk/englandm.php).

Committed here so the repo works offline; `load_data.py` falls back to
downloading via `kagglehub` if the file is absent.

## Caveats

- **2021-22 is incomplete** — 309 of 380 matches. The dataset stops on
  2022-04-10, so seasons from 2022-23 onward are missing entirely.
- **No match stats before 2000-01** — shots, corners, fouls and cards are
  null for the 1993-94 to 1999-00 seasons (2,824 rows). Use
  `load_matches(stats_only=True)` to drop them.
- The upstream CSV is cp1252-encoded, not UTF-8, and breaks `pd.read_csv`
  without `encoding="cp1252"`. The parquet has no such issue.

## Columns

`Season`, `DateTime`, `HomeTeam`, `AwayTeam`, `FTHG`/`FTAG`/`FTR` (full
time home goals / away goals / result), `HTHG`/`HTAG`/`HTR` (half time),
`Referee`, and per-side match stats: `HS`/`AS` shots, `HST`/`AST` shots on
target, `HC`/`AC` corners, `HF`/`AF` fouls, `HY`/`AY` yellows, `HR`/`AR` reds.
