"""Load the match data into PostgreSQL.

    python load_postgres.py

Postgres cannot read parquet the way DuckDB can, so this COPYs the cleaned
rows into a staging_matches table and then runs sql/postgres/build.sql,
which does all the modelling. Same division of labour as the DuckDB path:
Python moves bytes, SQL defines the schema.

Connection settings come from .env (see .env.example), defaulting to the
local instance on port 5433.
"""

import io
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).parent
PARQUET = ROOT / "data" / "matches_clean.parquet"
BUILD_SQL = ROOT / "sql" / "postgres" / "build.sql"

load_dotenv(ROOT / ".env")

# Port 5433, not the usual 5432: this machine already runs a PostgreSQL 17
# service on 5432 and that instance is left alone.
CONNINFO = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": os.getenv("PGPORT", "5433"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", "premierleague"),
    "dbname": os.getenv("PGDATABASE", "epl"),
}

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


def main() -> None:
    if not PARQUET.exists():
        print(
            f"{PARQUET} not found. Run `python prepare_data.py` first.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Reading {PARQUET.name}...")
    df = pd.read_parquet(PARQUET)[COLUMNS]
    print(f"  {len(df):,} matches")

    where = f"{CONNINFO['host']}:{CONNINFO['port']}/{CONNINFO['dbname']}"
    print(f"Connecting to {where}...")

    try:
        con = psycopg.connect(**CONNINFO, connect_timeout=10)
    except psycopg.OperationalError as error:
        print(f"\nCould not connect to {where}:\n  {error}", file=sys.stderr)
        print(
            "\nIs the server running? Start it with:\n"
            '  & "$env:LOCALAPPDATA\\Programs\\PostgreSQL18\\pgsql\\bin\\pg_ctl.exe" '
            '-D C:\\pgdata\\epl -l C:\\pgdata\\epl.log start',
            file=sys.stderr,
        )
        sys.exit(1)

    with con:
        with con.cursor() as cur:
            print("Creating staging table...")
            cur.execute(STAGING_DDL)

            # COPY via CSV: one round trip instead of 12,734 INSERTs.
            print("Copying rows...")
            buffer = io.StringIO()
            df.to_csv(buffer, index=False, header=False)
            buffer.seek(0)

            with cur.copy(
                "COPY staging_matches FROM STDIN WITH (FORMAT csv, NULL '')"
            ) as copy:
                copy.write(buffer.read())

            staged = cur.execute("SELECT COUNT(*) FROM staging_matches").fetchone()[0]
            print(f"  staged {staged:,} rows")

            print("Building schema...")
            cur.execute(BUILD_SQL.read_text(encoding="utf-8"))

            for table in ["teams", "referees", "matches"]:
                count = cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                print(f"  {table:<10} {count:>7,}")

            # Staging has served its purpose; drop it so the schema DBeaver
            # shows matches the DuckDB one exactly.
            cur.execute("DROP TABLE staging_matches")

    print(f"\nLoaded into {where}")


if __name__ == "__main__":
    main()
