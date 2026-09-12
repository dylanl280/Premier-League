"""Build and validate the DuckDB database in one step.

    python build_db.py

This is a convenience wrapper. It runs exactly what you would run by hand:

    python prepare_data.py
    duckdb data/epl.duckdb < sql/build.sql
    duckdb data/epl.duckdb < sql/validate.sql

All the modelling lives in sql/build.sql, not here, so the manual path and
this script cannot drift apart. Exits non-zero if any validation check fails.
"""

import sys
from pathlib import Path

import duckdb

import prepare_data

ROOT = Path(__file__).parent
DB_PATH = ROOT / "data" / "epl.duckdb"
SQL_DIR = ROOT / "sql"


def run_script(con: duckdb.DuckDBPyConnection, name: str) -> None:
    """Execute a .sql file as a script."""
    con.execute((SQL_DIR / name).read_text())


def main() -> None:
    prepare_data.main()

    print(f"\nBuilding {DB_PATH.name}...")
    # sql/build.sql reads data/matches_clean.parquet by relative path.
    con = duckdb.connect(str(DB_PATH))
    con.execute(f"SET file_search_path = '{ROOT.as_posix()}'")
    run_script(con, "build.sql")

    for table in ["teams", "referees", "matches"]:
        count = con.sql(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:<10} {count:>7,}")

    print("\nValidating...")
    results = con.sql((SQL_DIR / "validate.sql").read_text()).fetchall()
    con.close()

    failures = [row for row in results if row[3] != "PASS"]

    for check_name, got, expected, status in results:
        marker = "ok  " if status == "PASS" else "FAIL"
        detail = f"{got}" if status == "PASS" else f"{got} (expected {expected})"
        print(f"  {marker} {check_name} = {detail}")

    if failures:
        print(f"\n{len(failures)} check(s) FAILED.", file=sys.stderr)
        sys.exit(1)

    print(f"\nAll {len(results)} checks passed. Built {DB_PATH}")


if __name__ == "__main__":
    main()
