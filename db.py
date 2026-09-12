"""Query helpers for the DuckDB database.

    from db import query
    query("SELECT * FROM season_standings WHERE season = '2024-25'")

Opens read-only by default, so a stray query cannot damage the database and
several processes can read at once. Build it with `python build_db.py`.
"""

from pathlib import Path

import duckdb
import pandas as pd

DB_PATH = Path(__file__).parent / "data" / "epl.duckdb"


def connect(read_only: bool = True) -> duckdb.DuckDBPyConnection:
    """Open a connection to the database."""
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} not found. Build it first:\n"
            "    python build_db.py\n"
            "or by hand:\n"
            "    python prepare_data.py\n"
            "    duckdb data/epl.duckdb < sql/build.sql"
        )
    return duckdb.connect(str(DB_PATH), read_only=read_only)


def query(sql: str) -> pd.DataFrame:
    """Run a query and return the result as a DataFrame."""
    with connect() as con:
        return con.sql(sql).df()


def run_file(path: str | Path) -> pd.DataFrame:
    """Run a .sql file and return its final result set."""
    with connect() as con:
        return con.sql(Path(path).read_text()).df()


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
