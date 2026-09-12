"""Load English Premier League match results, 1993-94 to present.

Two sources sit behind this, both originating from football-data.co.uk:

  data/results.parquet  the Kaggle mirror (irkaal/english-premier-league-results),
                        covering 1993-94 up to 2022-04-10
  data/recent.parquet   seasons fetched directly, 2021-22 onward

They overlap on 2021-22, which the Kaggle copy holds only 309 of 380
matches of. The fetched seasons win that overlap, so any season present
in recent.parquet replaces the historical copy wholesale. Refresh the
recent file with `python update_data.py`.
"""

from pathlib import Path

import pandas as pd

DATASET = "irkaal/english-premier-league-results"

DATA_DIR = Path(__file__).parent / "data"
HISTORICAL = DATA_DIR / "results.parquet"
RECENT = DATA_DIR / "recent.parquet"

# Shots, corners, fouls and cards only start in 2000-01; earlier seasons
# carry score data alone.
FIRST_SEASON_WITH_MATCH_STATS = "2000-01"


def historical_path() -> Path:
    """Return the historical parquet, downloading from Kaggle only if absent."""
    if HISTORICAL.exists():
        return HISTORICAL

    import kagglehub  # imported lazily so the local path needs no Kaggle dep

    return Path(kagglehub.dataset_download(DATASET)) / "results.parquet"


def load_matches(stats_only: bool = False) -> pd.DataFrame:
    """Return all matches as a DataFrame, sorted oldest first.

    Reads parquet rather than CSV: it is typed, parses DateTime directly,
    and avoids the cp1252 bytes that sit in the CSV's Referee column.

    stats_only: drop seasons before 2000-01, which have no shot/card data.
    """
    df = pd.read_parquet(historical_path())

    if RECENT.exists():
        recent = pd.read_parquet(RECENT)
        # Drop whole seasons rather than deduplicating rows: the partial
        # 2021-22 in the historical file would otherwise survive alongside
        # the complete fetched one.
        df = df[~df["Season"].isin(recent["Season"].unique())]
        df = pd.concat([df, recent], ignore_index=True)

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
    print(f"{len(df):,} matches, {df.Season.nunique()} seasons")
    print(f"{df.DateTime.min():%Y-%m-%d} -> {df.DateTime.max():%Y-%m-%d}\n")
    print("2024-25 top six")
    print(season_table(df, "2024-25").head(6).to_string())
