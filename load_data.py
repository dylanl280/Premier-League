"""Load the English Premier League results dataset.

Source: Kaggle irkaal/english-premier-league-results, which republishes
football-data.co.uk results. Covers 1993-94 through a partial 2021-22
(last match 2022-04-10).

A copy of the parquet lives in data/, so the repo works offline and a
clone needs no Kaggle round-trip. If that file is missing, the loader
falls back to downloading via kagglehub.
"""

from pathlib import Path

import pandas as pd

DATASET = "irkaal/english-premier-league-results"

LOCAL_DATA = Path(__file__).parent / "data" / "results.parquet"

# Shots, corners, fouls and cards only start in 2000-01; earlier seasons
# carry score data alone.
FIRST_SEASON_WITH_MATCH_STATS = "2000-01"


def data_path() -> Path:
    """Return the parquet path, downloading from Kaggle only if needed."""
    if LOCAL_DATA.exists():
        return LOCAL_DATA

    import kagglehub  # imported lazily so the local path needs no Kaggle dep

    return Path(kagglehub.dataset_download(DATASET)) / "results.parquet"


def load_matches(stats_only: bool = False) -> pd.DataFrame:
    """Return all matches as a DataFrame, sorted oldest first.

    Reads the parquet rather than the CSV: it is typed, parses DateTime
    directly, and avoids the CSV's cp1252 bytes in the Referee column.

    stats_only: drop seasons before 2000-01, which have no shot/card data.
    """
    df = pd.read_parquet(data_path())

    if stats_only:
        df = df[df["Season"] >= FIRST_SEASON_WITH_MATCH_STATS]

    return df.sort_values("DateTime").reset_index(drop=True)


def season_table(df: pd.DataFrame, season: str) -> pd.DataFrame:
    """Build a league table for one season from its match results."""
    matches = df[df["Season"] == season]

    home = matches.rename(columns={"HomeTeam": "Team", "FTHG": "GF", "FTAG": "GA"})
    away = matches.rename(columns={"AwayTeam": "Team", "FTAG": "GF", "FTHG": "GA"})
    sides = pd.concat([home[["Team", "GF", "GA"]], away[["Team", "GF", "GA"]]])

    table = sides.groupby("Team").agg(
        P=("GF", "size"), GF=("GF", "sum"), GA=("GA", "sum")
    )
    table["W"] = sides[sides.GF > sides.GA].groupby("Team").size().reindex(table.index, fill_value=0)
    table["D"] = sides[sides.GF == sides.GA].groupby("Team").size().reindex(table.index, fill_value=0)
    table["L"] = table["P"] - table["W"] - table["D"]
    table["GD"] = table["GF"] - table["GA"]
    table["Pts"] = table["W"] * 3 + table["D"]

    return table.sort_values(["Pts", "GD", "GF"], ascending=False)[
        ["P", "W", "D", "L", "GF", "GA", "GD", "Pts"]
    ]


if __name__ == "__main__":
    df = load_matches()
    print(f"source: {data_path()}")
    print(f"{len(df):,} matches, {df.Season.nunique()} seasons")
    print(f"{df.DateTime.min():%Y-%m-%d} -> {df.DateTime.max():%Y-%m-%d}\n")
    print(season_table(df, "2020-21").head(6).to_string())
