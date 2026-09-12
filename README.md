# Premier League

Premier League match results from 1993-94 to the current season, in PostgreSQL.
12,734 matches, 34 seasons, 51 teams, 164 referees.

## Setup

### Python

```powershell
python -m venv C:\venvs\premier-league          # keep it out of OneDrive
C:\venvs\premier-league\Scripts\Activate.ps1
pip install -r requirements.txt
```

The venv lives outside OneDrive deliberately. A venv is ~15,800 small files;
inside a synced folder, enumerating them took over 120 seconds against 0.38
seconds on local disk.

### PostgreSQL

The project runs its own PostgreSQL 18.6 on **port 5433**, installed from the
binaries zip so it needs no admin rights. Port 5432 belongs to a separate,
pre-existing PostgreSQL 17 service that this project never touches.

Its data directory is `C:\pgdata\epl` - outside OneDrive, for the same reason
as the venv, and because a database cluster inside a synced folder invites
corruption.

It runs as a user process, not a Windows service, so **it does not survive a
reboot**:

```powershell
.\scripts\pg-start.ps1     # start it (also after every reboot)
.\scripts\pg-stop.ps1      # stop it
```

Credentials are in `.env`, which is gitignored. See `.env.example`.

### DBeaver

DBeaver Community 26.2 is installed at `%LOCALAPPDATA%\Programs\dbeaver`
(portable, bundled JRE, no admin), with a pre-configured connection:

| Field | Value |
|---|---|
| Host | `localhost` |
| Port | **5433** |
| Database | `epl` |
| User | `postgres` |

DBeaver bundles the Postgres driver, so nothing is downloaded on first connect.

## Building the database

```bash
python load_postgres.py
```

That runs three steps you can equally run by hand:

```bash
python prepare_data.py                                          # repair source data
psql -h localhost -p 5433 -U postgres -d epl -f sql/build.sql   # tables + views
psql -h localhost -p 5433 -U postgres -d epl -f sql/validate.sql
```

All the modelling lives in `sql/build.sql`, never in Python, so the scripted
and manual paths cannot drift apart. `load_postgres.py` exits non-zero if any
of the 18 validation checks fails.

### Why the Python step exists

`prepare_data.py` is required, not a convenience. Nine referee values in the
Kaggle parquet carry a raw `0xa0` byte - a cp1252 non-breaking space - so the
file is not valid UTF-8. pandas cannot even materialise the column, and a UTF8
Postgres database rejects the bytes on `COPY`.

Each bad value is also a *duplicate of a real referee*. Repairing them collapses
174 raw names into the 164 actual referees, which matters for any per-referee
analysis: without it, nine referees are silently split across two identities.

It also nulls six team-sides whose shot counts are physically impossible - more
shots on target than shots, or goals from zero shots.

## Querying

Through DBeaver, or from Python:

```python
from db import query
query("SELECT * FROM team_matches WHERE season = '2024-25' LIMIT 10")
```

```sql
SELECT t.name, s.points, s.goal_diff
FROM season_standings s JOIN teams t USING (team_id)
WHERE s.season = '2024-25'
ORDER BY s.position;
```

## Schema

| Object | Rows | Notes |
|---|---|---|
| `teams` | 51 | name, first/last season, seasons played |
| `referees` | 164 | post-repair; data begins 2000-01 |
| `matches` | 12,734 | one row per match, wide (home/away columns) |
| `team_matches` | 25,468 | **view** - one row per team per match |
| `season_standings` | - | **view** - league table per season |

**`matches` has two foreign keys into `teams`** - `home_team_id` and
`away_team_id` - so joining team names means joining `teams` twice with
aliases. DBeaver's visual join builder will often wire up only one.

`team_matches` exists to avoid that. A club appears exactly once per match it
played, with its own stats and the opponent's, so most questions need a single
join. Reach for `matches` only when you genuinely need both sides in one row -
head-to-head records, or home-vs-away comparisons.

Column names are explicit snake_case rather than the source's `HS`/`AS`/`FTHG`
shorthand. Not cosmetic: the source's away-shots column is literally named `AS`,
a reserved SQL keyword.

## Data caveats

- **Match stats begin in 2000-01.** Shots, corners, fouls, cards and referee are
  NULL for 1993-94 to 1999-00 - 22% of matches. Filter to 2000-01 onward or
  aggregates silently average over nulls. Goals and results are complete.
- **1993-94 and 1994-95 have 462 matches, not 380.** The league ran 22 clubs
  before shrinking to 20 in 1995-96. Compare eras on points-per-game. Correct,
  not a data error.
- **51 matches show goals exceeding shots on target.** These are own goals - the
  goal counts on the scoreline but is not a shot on target for the team credited
  with it. Also correct, not a data error.
- **2020-21 starts in September**, the COVID delay.
- **The current season is partial** and fills in as matches are played.

See [data/README.md](data/README.md) for sources and licensing.

## Analysis

```bash
python analysis/referee_bias.py
```

Tests whether referees affect match outcomes, over the 9,910 matches carrying a
referee. Outcomes are compared against an Elo expectation built chronologically,
so each match is predicted only from ratings that existed before kickoff.
Everything is season-centred, and per-referee tests are Benjamini-Hochberg FDR
corrected across the 34 referees with 100+ matches.

Findings: referees differ strongly in **strictness** (8 of 34 significant,
spanning 1.58 yellow cards per match), but show **no home/away card bias** and
**no measurable effect on results** (0 of 34 on both). Results land in
`analysis/output/`.

## Refreshing

```bash
python update_data.py      # fetch latest seasons from football-data.co.uk
python load_postgres.py    # rebuild
```

## Files

| File | Purpose |
|---|---|
| `load_data.py` | Loads and merges the two parquet sources |
| `update_data.py` | Fetches recent seasons from football-data.co.uk |
| `prepare_data.py` | Repairs encoding and impossible values, writes clean parquet |
| `load_postgres.py` | Builds and validates the database end to end |
| `sql/build.sql` | Creates all tables and views |
| `sql/validate.sql` | 18 integrity checks |
| `db.py` | `query()` helper returning DataFrames |
| `queries/referees.sql` | Referee exploration queries |
| `analysis/referee_bias.py` | Phase 2a statistical analysis |
| `scripts/pg-start.ps1` / `pg-stop.ps1` | Start and stop the local server |

`data/matches_clean.parquet` is derived and gitignored - rebuild it rather than
committing it.
