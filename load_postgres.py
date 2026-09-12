"""Build the PostgreSQL database end to end.

    python load_postgres.py

Runs the same three steps you can run by hand:

    python prepare_data.py                                  # repair source data
    psql -h localhost -p 5433 -U postgres -d epl -f sql/build.sql
    psql -h localhost -p 5433 -U postgres -d epl -f sql/validate.sql

Postgres cannot read parquet directly, so the cleaned rows are COPYed into a
staging_matches table and sql/build.sql models from there. All the modelling
lives in that SQL file, never here, so the manual and scripted paths cannot
drift apart.

Connection settings come from .env (see .env.example). Exits non-zero if any
validation check fails.
"""

import io
import sys
from pathlib import Path

import pandas as pd
import psycopg

import prepare_data
from db import CONNINFO, connect

ROOT = Path(__file__).parent
PARQUET = ROOT / "data" / "matches_clean.parquet"
SQL_DIR = ROOT / "sql"

STAGING_DDL = """
DROP TABLE IF EXISTS staging_matches;
CREATE TABLE staging_matches (
    season      TEXT,
    kickoff     TIMESTAMPTZ,
    home_team   TEXT,
    away_team   TEXT,
    referee     TEXT,
    home_goals  INTEGER,
    away_goals  INTEGER,
    result      TEXT,
    ht_home_goals INTEGER,
    ht_away_goals INTEGER,
    ht_result     TEXT,
    home_shots           INTEGER,
    away_shots           INTEGER,
    home_shots_on_target INTEGER,
    away_shots_on_target INTEGER,
    home_corners         INTEGER,
    away_corners         INTEGER,
    home_fouls           INTEGER,
    away_fouls           INTEGER,
    home_yellows         INTEGER,
    away_yellows         INTEGER,
    home_reds            INTEGER,
    away_reds            INTEGER
);
"""

COLUMNS = [
    "season", "kickoff", "home_team", "away_team", "referee",
    "home_goals", "away_goals", "result",
    "ht_home_goals", "ht_away_goals", "ht_result",
    "home_shots", "away_shots",
    "home_shots_on_target", "away_shots_on_target",
    "home_corners", "away_corners",
    "home_fouls", "away_fouls",
    "home_yellows", "away_yellows",
    "home_reds", "away_reds",
]


def load(cur: psycopg.Cursor, df: pd.DataFrame) -> None:
    """Stage the rows, then run the build script over them."""
    cur.execute(STAGING_DDL)

    # COPY via CSV: one round trip instead of 12,734 INSERTs.
    buffer = io.StringIO()
    df.to_csv(buffer, index=False, header=False)
    buffer.seek(0)

    with cur.copy("COPY staging_matches FROM STDIN WITH (FORMAT csv, NULL '')") as copy:
        copy.write(buffer.read())

    staged = cur.execute("SELECT COUNT(*) FROM staging_matches").fetchone()[0]
    print(f"  staged {staged:,} rows")

    print("Building schema...")
    cur.execute((SQL_DIR / "build.sql").read_text(encoding="utf-8"))

    for table in ["teams", "referees", "matches"]:
        count = cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:<10} {count:>7,}")

    # Staging has served its purpose; drop it so what DBeaver shows is only
    # the real schema.
    cur.execute("DROP TABLE staging_matches")


def validate(cur: psycopg.Cursor) -> int:
    """Run sql/validate.sql and print each check. Returns the failure count."""
    print("\nValidating...")
    cur.execute((SQL_DIR / "validate.sql").read_text(encoding="utf-8"))
    results = cur.fetchall()

    failures = 0
    for check_name, got, expected, status in results:
        if status == "PASS":
            print(f"  ok   {check_name} = {got}")
        else:
            failures += 1
            print(f"  FAIL {check_name} = {got} (expected {expected})")

    print(f"\n{len(results) - failures}/{len(results)} checks passed.")
    return failures


def main() -> None:
    prepare_data.main()

    if not PARQUET.exists():
        print(f"{PARQUET} not found.", file=sys.stderr)
        sys.exit(1)

    df = pd.read_parquet(PARQUET)[COLUMNS]

    target = f"{CONNINFO['host']}:{CONNINFO['port']}/{CONNINFO['dbname']}"
    print(f"\nConnecting to {target}...")

    try:
        con = connect()
    except ConnectionError as error:
        print(f"\n{error}", file=sys.stderr)
        sys.exit(1)

    with con, con.cursor() as cur:
        load(cur, df)
        failures = validate(cur)

    if failures:
        sys.exit(1)

    print(f"Built {target}")


if __name__ == "__main__":
    main()
