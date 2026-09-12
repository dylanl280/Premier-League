# Premier League

Premier League match results from 1993-94 to the current season, as a queryable
DuckDB database. 12,734 matches, 34 seasons, 51 teams, 164 referees.

## Setup

Python 3.13 and the DuckDB CLI. Both are already installed on this machine; on a
fresh one:

```powershell
winget install Python.Python.3.13
winget install DuckDB.cli
```

Both winget packages install machine-wide and trigger a UAC prompt. If that is
inconvenient, the DuckDB CLI also ships as a portable zip that needs no admin —
extract `duckdb.exe` anywhere on `PATH`. That is how it is installed here, at
`%LOCALAPPDATA%\Programs\DuckDB`.

```powershell
python -m venv C:\venvs\premier-league          # keep it out of OneDrive
C:\venvs\premier-league\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Building the database

Two commands. The first is Python, the second is plain SQL you can read and edit:

```bash
python prepare_data.py                      # repairs source data -> data/matches_clean.parquet
duckdb data/epl.duckdb < sql/build.sql      # creates tables + views
duckdb data/epl.duckdb < sql/validate.sql   # 16 integrity checks, all should read PASS
```

Run them from the repo root — `sql/build.sql` uses relative paths.

Or do all three at once:

```bash
python build_db.py
```

`build_db.py` runs exactly those commands, so the two paths cannot drift apart.
All the modelling lives in `sql/build.sql`, never in Python.

### Why the Python step exists

`prepare_data.py` is not a convenience wrapper — it is required. Nine referee
values in the Kaggle parquet carry a raw `0xa0` byte (a cp1252 non-breaking
space), so the file is not valid UTF-8 and DuckDB refuses it:

```
Invalid Input Error: Invalid string encoding found in Parquet file
"data/results.parquet": value "\xA0U Rennie" is not valid UTF8!
```

`COUNT(*)` still works because it never touches the column, but any query
referencing `Referee` fails outright. Each bad value is also a *duplicate of a
real referee* — repairing them collapses 174 raw names into 164 actual referees,
which matters for any per-referee analysis.

## Querying

From the CLI:

```bash
duckdb data/epl.duckdb
```

```sql
SELECT t.name, s.points, s.goal_diff
FROM season_standings s JOIN teams t USING (team_id)
WHERE s.season = '2024-25'
ORDER BY s.position;
```

From Python:

```python
from db import query
query("SELECT * FROM team_matches WHERE season = '2024-25' LIMIT 10")
```

## Schema

| Object | Rows | Notes |
|---|---|---|
| `teams` | 51 | name, first/last season, seasons played |
| `referees` | 164 | post-repair; data begins 2000-01 |
| `matches` | 12,734 | one row per match, wide (home/away columns) |
| `team_matches` | 25,468 | **view** — one row per team per match |
| `season_standings` | — | **view** — league table per season |

`team_matches` is the one to reach for. Against the wide `matches` table a club
appears in either `home_team_id` or `away_team_id`, so "how did Arsenal do" needs
a UNION every time; in `team_matches` it appears exactly once per match played,
with its own stats and the opponent's.

Column names are explicit snake_case rather than the source's `HS`/`AS`/`FTHG`
shorthand. That is not cosmetic: the source's away-shots column is literally named
`AS`, a reserved SQL keyword.

## PostgreSQL and DBeaver

The same data also lives in PostgreSQL, for querying through DBeaver. DuckDB
stays the analysis engine; Postgres is the GUI-friendly copy.

### Why port 5433

This machine already runs a **PostgreSQL 17 Windows service on 5432**. That
instance is left completely alone. The project instance is a separate
PostgreSQL 18.6 on **5433**, with its data directory at `C:\pgdata\epl`,
installed from the binaries zip so it needs no admin rights.

It runs as a user process, not a service, so **it does not survive a reboot**:

```powershell
.\scripts\pg-start.ps1     # start it (also after every reboot)
.\scripts\pg-stop.ps1      # stop it
```

The data directory deliberately sits outside OneDrive. A Postgres cluster
inside a synced folder invites corruption, for the same reason the venv is
kept out.

### Loading

```bash
python prepare_data.py     # if not already run
python load_postgres.py    # COPY into staging, then run sql/postgres/build.sql
```

Verify with the same 16 checks:

```bash
psql -h localhost -p 5433 -U postgres -d epl -f sql/postgres/validate.sql
```

All 16 pass against both engines. Since the DuckDB and Postgres schemas are
built by separate SQL files, their agreement cross-checks the modelling.

### Connecting DBeaver

DBeaver Community 26.2 is installed at `%LOCALAPPDATA%\Programs\dbeaver`
(portable, bundled JRE, no admin). Two connections are pre-configured:

| Connection | URL |
|---|---|
| EPL (PostgreSQL 18) | `jdbc:postgresql://localhost:5433/epl` |
| EPL (DuckDB) | `jdbc:duckdb:.../data/epl.duckdb` (read-only) |

Passwords are not saved in the DBeaver config, so it prompts on first
connect. Credentials live in `.env`, which is gitignored; see `.env.example`.

If a connection does not appear, add it by hand: **Database → New Database
Connection → PostgreSQL**, host `localhost`, port `5433`, database `epl`,
user `postgres`. DBeaver bundles the Postgres driver; for DuckDB it fetches
the JDBC driver from Maven on first connect.

## Data caveats

- **Match stats begin in 2000-01.** Shots, corners, fouls, cards and referee are
  NULL for 1993-94 to 1999-00 — 22% of matches. Filter to 2000-01 onward or
  aggregates silently average over nulls. Goals and results are complete.
- **1993-94 and 1994-95 have 462 matches, not 380.** The league ran 22 clubs
  before shrinking to 20 in 1995-96. Compare eras on points-per-game, not raw
  points. This is correct, not a data error.
- **The current season is partial** and fills in as matches are played.

See [data/README.md](data/README.md) for sources and licensing.

## Refreshing

```bash
python update_data.py    # fetch latest seasons from football-data.co.uk
python build_db.py       # rebuild
```

## Files

| File | Purpose |
|---|---|
| `load_data.py` | Loads and merges the two parquet sources |
| `update_data.py` | Fetches recent seasons from football-data.co.uk |
| `prepare_data.py` | Repairs the referee encoding, writes clean parquet |
| `sql/build.sql` | Creates all tables and views |
| `sql/validate.sql` | 16 integrity checks |
| `build_db.py` | Runs the above end to end |
| `db.py` | `query()` helper returning DataFrames |
| `load_postgres.py` | Loads the same data into PostgreSQL |
| `sql/postgres/build.sql` | Postgres schema and views |
| `sql/postgres/validate.sql` | The same 16 checks, Postgres dialect |
| `scripts/pg-start.ps1` | Start the local Postgres instance |
| `scripts/pg-stop.ps1` | Stop it |
| `queries/referees.sql` | Referee exploration queries |

`data/epl.duckdb` and `data/matches_clean.parquet` are derived and gitignored —
rebuild them rather than committing them.
