"""Phase 2a: do referees affect match outcomes?

    python analysis/referee_bias.py

Four analyses, ordered by how much weight the evidence can bear:

  A  Home/away card asymmetry, season-centred. The strongest signal the data
     supports: the same referee books both sides within one match, so fixture
     quality and importance largely cancel.

  B  Strictness - cards and fouls per match as z-scores against the league
     mean for each season worked, so a 2003 referee is not judged by 2024
     norms.

  C  Outcome residuals against an Elo expectation. The only analysis that
     attacks the assignment confounder directly, and the one that actually
     answers the question.

  D  Raw home-win rate, computed deliberately as the WRONG answer, to show
     how much of A-C's apparent effect is really fixture assignment.

Every per-referee test is corrected with Benjamini-Hochberg FDR: with 34
referees, roughly two would clear p<0.05 by chance alone.

A null result in C is a real finding and is reported as one.
"""

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.stats.multitest import multipletests

# Run directly (python analysis/referee_bias.py) without installing the repo.
sys.path.insert(0, str(Path(__file__).parent.parent))

from db import query

ROOT = Path(__file__).parent.parent
OUT_DIR = ROOT / "analysis" / "output"

# Below this, per-referee estimates are noise: the median referee in the
# data officiated only 11 matches.
MIN_MATCHES = 100

FDR_ALPHA = 0.05

# Elo settings. HOME_ADVANTAGE is in rating points and is fitted crudely by
# the league's long-run home win rate; K controls how fast ratings move;
# SEASON_CARRY regresses ratings toward the mean between seasons, since
# squads turn over and promoted sides replace relegated ones.
ELO_BASE = 1500.0
ELO_K = 20.0
ELO_HOME_ADVANTAGE = 65.0
SEASON_CARRY = 0.75


def load_matches() -> pd.DataFrame:
    """All matches in chronological order, with referee where known."""
    return query("""
        SELECT
            m.match_id, m.season, m.kickoff,
            m.home_team_id, m.away_team_id,
            m.result, m.home_goals, m.away_goals,
            m.referee_id, r.name AS referee,
            m.home_yellows, m.away_yellows,
            m.home_reds, m.away_reds,
            m.home_fouls, m.away_fouls
        FROM matches m
        LEFT JOIN referees r USING (referee_id)
        ORDER BY m.kickoff, m.match_id
    """)


def add_elo(df: pd.DataFrame) -> pd.DataFrame:
    """Attach pre-match Elo ratings and an expected home score.

    Ratings are built chronologically over every match, including the
    pre-2000 seasons that carry no referee, so that by the time referee data
    starts the ratings are already informative. Crucially each match is
    predicted from ratings that existed *before* it was played, so nothing
    leaks from the result being predicted.
    """
    ratings: dict[int, float] = {}
    expected = np.empty(len(df))
    actual = np.empty(len(df))
    current_season = None

    for i, row in enumerate(df.itertuples(index=False)):
        if row.season != current_season:
            # Between seasons, pull every rating toward the mean.
            for team in ratings:
                ratings[team] = ELO_BASE + SEASON_CARRY * (ratings[team] - ELO_BASE)
            current_season = row.season

        home = ratings.get(row.home_team_id, ELO_BASE)
        away = ratings.get(row.away_team_id, ELO_BASE)

        exp_home = 1.0 / (1.0 + 10 ** ((away - home - ELO_HOME_ADVANTAGE) / 400.0))
        score_home = {"H": 1.0, "D": 0.5, "A": 0.0}[row.result]

        expected[i] = exp_home
        actual[i] = score_home

        ratings[row.home_team_id] = home + ELO_K * (score_home - exp_home)
        ratings[row.away_team_id] = away + ELO_K * ((1 - score_home) - (1 - exp_home))

    out = df.copy()
    out["expected_home_score"] = expected
    out["actual_home_score"] = actual
    out["residual"] = actual - expected
    return out


def test_by_referee(
    df: pd.DataFrame, value: str, label: str
) -> pd.DataFrame:
    """One-sample t-test of `value` per referee, against the overall mean.

    The column is expected to be already centred (season-adjusted), so the
    null is that a referee's mean matches everyone else's.
    """
    usable = df.dropna(subset=[value, "referee"])
    grand_mean = usable[value].mean()

    rows = []
    for referee, group in usable.groupby("referee"):
        n = len(group)
        if n < MIN_MATCHES:
            continue

        values = group[value].to_numpy(dtype=float)
        mean = values.mean()
        sem = stats.sem(values)
        t_stat, p_value = stats.ttest_1samp(values, grand_mean)
        low, high = stats.t.interval(0.95, n - 1, loc=mean, scale=sem)

        rows.append({
            "referee": referee,
            "matches": n,
            "mean": mean,
            "vs_average": mean - grand_mean,
            "ci_low": low,
            "ci_high": high,
            "t": t_stat,
            "p": p_value,
        })

    result = pd.DataFrame(rows)
    if result.empty:
        return result

    reject, p_adj, _, _ = multipletests(result["p"], alpha=FDR_ALPHA, method="fdr_bh")
    result["p_fdr"] = p_adj
    result["significant"] = reject
    result.attrs["label"] = label
    result.attrs["grand_mean"] = grand_mean

    return result.sort_values("vs_average").reset_index(drop=True)


def season_centre(df: pd.DataFrame, column: str) -> pd.Series:
    """Subtract each season's league mean, removing era drift."""
    return df[column] - df.groupby("season")[column].transform("mean")


def report(result: pd.DataFrame, title: str, unit: str, note: str = "") -> None:
    print(f"\n{'=' * 78}\n{title}\n{'=' * 78}")
    if note:
        print(note)
    print(f"League mean: {result.attrs['grand_mean']:+.4f} {unit}")

    hits = result[result["significant"]]
    print(
        f"{len(result)} referees with >= {MIN_MATCHES} matches; "
        f"{len(hits)} significant after BH-FDR at {FDR_ALPHA:.0%}"
    )

    show = pd.concat([result.head(6), result.tail(6)]).drop_duplicates("referee").copy()

    # Express the interval as a deviation from the league mean, so it is on
    # the same scale as vs_average. Without this the uncentred analyses show
    # an interval around the raw rate next to a difference, which reads as a
    # contradiction.
    grand = result.attrs["grand_mean"]
    show["ci_low"] = show["ci_low"] - grand
    show["ci_high"] = show["ci_high"] - grand

    table = show[["referee", "matches", "vs_average", "ci_low", "ci_high", "p_fdr", "significant"]]
    table = table.rename(columns={"vs_average": f"vs_avg({unit})", "significant": "sig"})
    print()
    print(table.to_string(index=False, float_format=lambda v: f"{v:8.4f}"))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Loading matches and building Elo ratings...")
    df = add_elo(load_matches())

    # Restrict to the era that actually has referees and card data.
    with_stats = df[df["referee"].notna() & df["home_yellows"].notna()].copy()
    with_ref = df[df["referee"].notna()].copy()

    print(
        f"  {len(df):,} matches total, {len(with_ref):,} with a referee, "
        f"{len(with_stats):,} with card data"
    )

    # --- A. Home/away card asymmetry -------------------------------------
    with_stats["card_diff"] = with_stats["home_yellows"] - with_stats["away_yellows"]
    with_stats["card_diff_centred"] = season_centre(with_stats, "card_diff")

    a = test_by_referee(with_stats, "card_diff_centred", "card asymmetry")
    report(
        a,
        "A. HOME/AWAY CARD ASYMMETRY (season-centred)",
        "cards",
        "Negative = books away players more than home players, relative to\n"
        "the league average for the same seasons.",
    )

    # --- B. Strictness ---------------------------------------------------
    with_stats["cards_total"] = with_stats["home_yellows"] + with_stats["away_yellows"]
    with_stats["cards_centred"] = season_centre(with_stats, "cards_total")

    b = test_by_referee(with_stats, "cards_centred", "strictness")
    report(
        b,
        "B. STRICTNESS: yellow cards per match (season-centred)",
        "cards",
        "Positive = books more than the league average for the same seasons.",
    )

    # --- C. Outcome residuals vs Elo expectation -------------------------
    with_ref["residual_centred"] = season_centre(with_ref, "residual")

    c = test_by_referee(with_ref, "residual_centred", "outcome residual")
    report(
        c,
        "C. OUTCOME RESIDUAL vs ELO EXPECTATION (season-centred)",
        "home score",
        "Home score is 1 win / 0.5 draw / 0 loss. Positive = home teams did\n"
        "better than their Elo ratings predicted. This is the analysis that\n"
        "actually tests whether referees move results.",
    )

    # --- D. Raw home-win rate, the confounded contrast -------------------
    with_ref["home_win"] = (with_ref["result"] == "H").astype(float)
    d = test_by_referee(with_ref, "home_win", "raw home win rate")
    report(
        d,
        "D. RAW HOME-WIN RATE (deliberately unadjusted)",
        "win rate",
        "NOT evidence of bias. Referees are not randomly assigned, so this\n"
        "largely reflects which fixtures each was given. Shown for contrast\n"
        "with C.",
    )

    # --- verdict ---------------------------------------------------------
    print(f"\n{'=' * 78}\nVERDICT\n{'=' * 78}")
    for name, result in [("A card asymmetry", a), ("B strictness", b),
                         ("C outcome residual", c), ("D raw home-win", d)]:
        n_sig = int(result["significant"].sum())
        spread = result["vs_average"].max() - result["vs_average"].min()
        print(f"  {name:<22} {n_sig:>2}/{len(result)} significant   spread={spread:.4f}")

    c_sig = int(c["significant"].sum())
    print()
    if c_sig == 0:
        print(
            "C finds NO referee whose matches deviate from Elo expectation once\n"
            "season effects and multiple comparisons are accounted for. On this\n"
            "evidence, referees do not measurably change who wins."
        )
    else:
        print(
            f"C flags {c_sig} referee(s). Treat with caution: non-random assignment\n"
            "can produce this even with perfectly neutral officiating."
        )

    for frame, name in [(a, "a_card_asymmetry"), (b, "b_strictness"),
                        (c, "c_outcome_residual"), (d, "d_raw_home_win")]:
        frame.to_csv(OUT_DIR / f"{name}.csv", index=False)

    summary = {
        "min_matches": MIN_MATCHES,
        "fdr_alpha": FDR_ALPHA,
        "matches_total": int(len(df)),
        "matches_with_referee": int(len(with_ref)),
        "matches_with_cards": int(len(with_stats)),
        "referees_tested": int(len(a)),
        "significant": {
            "card_asymmetry": int(a["significant"].sum()),
            "strictness": int(b["significant"].sum()),
            "outcome_residual": int(c["significant"].sum()),
            "raw_home_win": int(d["significant"].sum()),
        },
    }
    (OUT_DIR / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"\nWrote results to {OUT_DIR.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
