"""Repair the source data and write a clean parquet.

Run:  python prepare_data.py

This is the one step that cannot be done in SQL. Nine referee values in the
Kaggle parquet carry a raw 0xa0 byte - a cp1252 non-breaking space - so the
file is not valid UTF-8.

Nothing downstream tolerates that. pandas cannot even materialise the
column (both .tolist() and pyarrow's to_pylist() raise on those rows), and
a UTF8 Postgres database rejects the bytes on COPY. Each bad value is also
a duplicate of a real referee, so left alone it splits that referee into
two identities and corrupts any per-referee analysis.

So this decodes the column byte by byte, normalises the names, nulls a
handful of physically impossible shot counts, and writes
data/matches_clean.parquet with final snake_case column names. Everything
after this point is plain SQL in sql/build.sql.
"""

import sys
import unicodedata
from pathlib import Path

import pandas as pd
import pyarrow as pa

from load_data import load_matches

ROOT = Path(__file__).parent
OUT_PATH = ROOT / "data" / "matches_clean.parquet"

# Source shorthand -> explicit names. The source calls away shots "AS",
# which is a reserved SQL keyword and would need quoting in every query.
COLUMN_RENAMES = {
    "Season": "season",
    "DateTime": "kickoff",
    "HomeTeam": "home_team",
    "AwayTeam": "away_team",
    "Referee": "referee",
    "FTHG": "home_goals",
    "FTAG": "away_goals",
    "FTR": "result",
    "HTHG": "ht_home_goals",
    "HTAG": "ht_away_goals",
    "HTR": "ht_result",
    "HS": "home_shots",
    "AS": "away_shots",
    "HST": "home_shots_on_target",
    "AST": "away_shots_on_target",
    "HC": "home_corners",
    "AC": "away_corners",
    "HF": "home_fouls",
    "AF": "away_fouls",
    "HY": "home_yellows",
    "AY": "away_yellows",
    "HR": "home_reds",
    "AR": "away_reds",
}

INT_COLUMNS = [
    "ht_home_goals", "ht_away_goals",
    "home_shots", "away_shots",
    "home_shots_on_target", "away_shots_on_target",
    "home_corners", "away_corners",
    "home_fouls", "away_fouls",
    "home_yellows", "away_yellows",
    "home_reds", "away_reds",
]

# The exact malformed values, asserted as a regression test.
KNOWN_MALFORMED = 9


def repair_referees(series: pd.Series) -> tuple[list[str | None], int]:
    """Decode the referee column from raw bytes, repairing invalid UTF-8.

    Returns the cleaned names and how many values needed repair. Each bad
    value is a duplicate of a real referee, so leaving them in place splits
    that referee into two identities and corrupts per-referee analysis.
    """
    raw = series.array._pa_array.combine_chunks().cast(pa.binary())

    names: list[str | None] = []
    malformed = 0

    for value in raw.to_pylist():
        if value is None:
            names.append(None)
            continue

        try:
            name = value.decode("utf-8")
        except UnicodeDecodeError:
            name = value.decode("cp1252")
            malformed += 1

        # NBSP survives a successful cp1252 decode, so normalise it away
        # along with any other stray whitespace.
        name = unicodedata.normalize("NFKC", name)
        name = " ".join(name.split())
        names.append(name or None)

    return names, malformed


def null_impossible_shots(df: pd.DataFrame) -> tuple[pd.DataFrame, int]:
    """Null shot counts that cannot physically be true.

    Four matches in the source carry impossible values - a side with more
    shots on target than shots, or scoring goals from zero shots. Since
    there is no way to know which of the two numbers is wrong, both are
    nulled for that side rather than guessed at. Left in place they produce
    shot-accuracy rates above 100%.

    Deliberately NOT treated as errors: goals exceeding shots on target,
    which happens in 51 matches. That is own goals - the goal counts on the
    scoreline but is not a shot on target for the team credited with it.
    The gap is exactly one in 50 of those 51 matches, which is the
    signature of a single own goal rather than a data fault.
    """
    affected = 0

    for side in ("home", "away"):
        shots = f"{side}_shots"
        on_target = f"{side}_shots_on_target"
        goals = f"{side}_goals"

        impossible = (
            (df[on_target] > df[shots])
            | ((df[goals] > 0) & (df[shots] == 0))
        ).fillna(False)

        affected += int(impossible.sum())
        df.loc[impossible, [shots, on_target]] = pd.NA

    return df, affected


def main() -> None:
    print("Loading matches...")
    df = load_matches()

    print("Repairing referee names...")
    referees, malformed = repair_referees(df["Referee"])

    before = df["Referee"].nunique()
    after = len({r for r in referees if r})
    print(f"  {malformed} malformed values repaired")
    print(f"  {before} raw names -> {after} referees ({before - after} phantoms merged)")

    if malformed != KNOWN_MALFORMED:
        print(
            f"\nFAILED: expected {KNOWN_MALFORMED} malformed values, found {malformed}.\n"
            "The source data changed - check data/results.parquet before continuing.",
            file=sys.stderr,
        )
        sys.exit(1)

    df = df.rename(columns=COLUMN_RENAMES)
    df["referee"] = referees

    for column in INT_COLUMNS:
        df[column] = pd.array(df[column].to_numpy(), dtype="Float64").astype("Int64")

    df, impossible = null_impossible_shots(df)
    print(f"  nulled shot counts on {impossible} team-sides with impossible values")

    df = df[list(COLUMN_RENAMES.values())]
    df.to_parquet(OUT_PATH, index=False)

    size_kb = OUT_PATH.stat().st_size / 1024
    print(f"\nWrote {len(df):,} matches to {OUT_PATH.name} ({size_kb:.0f} KB)")
    print("Now run:  python load_postgres.py")


if __name__ == "__main__":
    main()
