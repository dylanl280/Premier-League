"""Fetch recent Premier League seasons from football-data.co.uk.

The Kaggle dataset in data/results.parquet stops on 2022-04-10, leaving
2021-22 incomplete and every later season missing. football-data.co.uk
is the same upstream source and publishes one CSV per season, so the
columns line up after building Season and DateTime.

Run this to refresh data/recent.parquet:

    python update_data.py
"""

import io
from pathlib import Path

import pandas as pd
import requests

BASE_URL = "https://www.football-data.co.uk/mmz4281/{code}/E0.csv"

OUT_PATH = Path(__file__).parent / "data" / "recent.parquet"

# 2021-22 is refetched in full: the Kaggle copy holds only 309 of its 380
# matches, so the fetched season replaces it rather than topping it up.
SEASON_CODES = ["2122", "2223", "2324", "2425", "2526", "2627"]

# The 23 columns the Kaggle dataset exposes, in its order.
COLUMNS = [
    "Season", "DateTime", "HomeTeam", "AwayTeam",
    "FTHG", "FTAG", "FTR", "HTHG", "HTAG", "HTR", "Referee",
    "HS", "AS", "HST", "AST", "HC", "AC", "HF", "AF", "HY", "AY", "HR", "AR",
]

# Everything except Season and DateTime, which are built per season.
STAT_COLUMNS = COLUMNS[2:]


def season_label(code: str) -> str:
    """Turn a football-data season code into a Kaggle-style label."""
    return f"20{code[:2]}-{code[2:]}"


def fetch_season(code: str) -> pd.DataFrame:
    """Download one season and normalise it to the Kaggle schema."""
    response = requests.get(BASE_URL.format(code=code), timeout=60)
    response.raise_for_status()

    # football-data serves cp1252, not UTF-8 - referee names carry
    # non-breaking spaces that break a strict UTF-8 decode.
    raw = pd.read_csv(io.BytesIO(response.content), encoding="cp1252")

    # Trailing blank rows appear in in-progress seasons.
    raw = raw.dropna(subset=["HomeTeam", "AwayTeam"])

    # Kickoff times are absent from some older files.
    times = raw["Time"].fillna("00:00") if "Time" in raw.columns else "00:00"

    # Built in one pass: the source file carries ~130 betting-odds columns
    # alongside these, and inserting into that frame one column at a time
    # fragments it badly.
    return pd.DataFrame({
        "Season": season_label(code),
        "DateTime": pd.to_datetime(
            raw["Date"] + " " + times, format="%d/%m/%Y %H:%M"
        ).dt.tz_localize("GMT"),
        **{c: raw[c] if c in raw.columns else pd.NA for c in STAT_COLUMNS},
    })[COLUMNS]


def fetch_all(codes: list[str] = SEASON_CODES) -> pd.DataFrame:
    """Fetch every configured season and return them as one frame."""
    frames = []
    for code in codes:
        season = fetch_season(code)
        print(f"  {season_label(code)}: {len(season):>3} matches")
        frames.append(season)

    return pd.concat(frames, ignore_index=True).sort_values("DateTime")


if __name__ == "__main__":
    print("Fetching from football-data.co.uk")
    recent = fetch_all()

    OUT_PATH.parent.mkdir(exist_ok=True)
    recent.to_parquet(OUT_PATH, index=False)

    print(f"\nWrote {len(recent):,} matches to {OUT_PATH.name}")
