"""Query helpers for the PostgreSQL database.

    from db import query
    query("SELECT * FROM season_standings WHERE season = '2024-25'")

Connection settings come from .env (see .env.example), defaulting to the
local instance on port 5433 - 5432 belongs to a separate, pre-existing
PostgreSQL 17 service that this project does not touch.

Build the database with `python load_postgres.py`.
"""

import os
from pathlib import Path

import pandas as pd
import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).parent

load_dotenv(ROOT / ".env")

CONNINFO = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": os.getenv("PGPORT", "5433"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", "premierleague"),
    "dbname": os.getenv("PGDATABASE", "epl"),
}

_START_HINT = (
    "Is the server running? It is a user process, not a service, so it stops\n"
    "on reboot. Start it with:\n"
    "    .\\scripts\\pg-start.ps1"
)


def connect(**overrides) -> psycopg.Connection:
    """Open a connection, raising a useful error if the server is down."""
    try:
        return psycopg.connect(**{**CONNINFO, **overrides}, connect_timeout=10)
    except psycopg.OperationalError as error:
        target = f"{CONNINFO['host']}:{CONNINFO['port']}/{CONNINFO['dbname']}"
        raise ConnectionError(
            f"Could not connect to {target}:\n  {error}\n\n{_START_HINT}"
        ) from error


def query(sql: str, params: tuple | None = None) -> pd.DataFrame:
    """Run a query and return the result as a DataFrame."""
    with connect() as con, con.cursor() as cur:
        cur.execute(sql, params)
        columns = [c.name for c in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=columns)


def run_file(path: str | Path) -> pd.DataFrame:
    """Run a .sql file and return its final result set."""
    return query(Path(path).read_text(encoding="utf-8"))


if __name__ == "__main__":
    print(query("""
        SELECT t.name AS team, s.played, s.won, s.drawn, s.lost,
               s.goal_diff, s.points
        FROM season_standings s
        JOIN teams t USING (team_id)
        WHERE s.season = '2024-25'
        ORDER BY s.position
        LIMIT 6
    """).to_string(index=False))
