#!/usr/bin/env python3
"""Reproduce the headline results from the committed seed-42424 paired run.

This script reads ONLY the committed benchmark CSVs (it does not re-run the
NetLogo model), recomputes the five headline metrics exactly as the README
table defines them, asserts they match the published values, prints the table as
GitHub-flavored Markdown, and renders the unemployment-rate paths figure that the
README embeds.

Because the published numbers are hard-coded as assertions, the script doubles as
a regression test: if the committed data ever drifts, it exits non-zero instead
of silently producing a wrong table or figure.

Usage:
    python3 extras/analyze_paired_comparison.py

Requires pandas and matplotlib.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # headless, no display required
import matplotlib.pyplot as plt
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "extras" / "data"
FIG_DIR = REPO_ROOT / "docs" / "figures"
SEED = 42424

SCENARIOS = {
    "Tech-Driven": f"tech_driven_seed_{SEED}_history.csv",
    "Human-Centric": f"human_centric_seed_{SEED}_history.csv",
}

# Published values from the README headline table, used as regression guards.
# Peak unemployment is the MAX over the 200-month horizon; the other four rows
# are end-of-horizon (final-tick) values.
EXPECTED = {
    "Tech-Driven": {
        "peak_unemployment": 14.3,
        "ever_unemployed_share": 46.4,
        "avg_spell_exposed": 34.4,
        "burden_gini_exposed": 0.478,
        "total_output": 79.5,
    },
    "Human-Centric": {
        "peak_unemployment": 3.6,
        "ever_unemployed_share": 7.1,
        "avg_spell_exposed": 3.0,
        "burden_gini_exposed": 0.000,
        "total_output": 55.0,
    },
}


def load(scenario: str) -> pd.DataFrame:
    path = DATA_DIR / SCENARIOS[scenario]
    if not path.exists():
        raise SystemExit(f"Missing committed data file: {path}")
    return pd.read_csv(path)


def metrics(df: pd.DataFrame) -> dict[str, float]:
    final = df.iloc[-1]
    return {
        "peak_unemployment": round(float(df["unemployment_rate"].max()), 1),
        "ever_unemployed_share": round(float(final["ever_unemployed_share"]), 1),
        "avg_spell_exposed": round(
            float(final["avg_unemployment_time_exposed"]), 1
        ),
        "burden_gini_exposed": round(
            float(final["unemployment_burden_gini_exposed"]), 3
        ),
        "total_output": round(float(final["total_output"]), 1),
    }


ROWS = [
    ("Peak unemployment rate", "peak_unemployment", "{:.1f}%"),
    ("Share of workers ever unemployed", "ever_unemployed_share", "{:.1f}%"),
    ("Average unemployment spell among exposed workers", "avg_spell_exposed", "{:.1f} months"),
    ("Unemployment burden Gini among exposed workers", "burden_gini_exposed", "{:.3f}"),
    ("Total output at horizon", "total_output", "{:.1f}"),
]


def verify_and_print(computed: dict[str, dict[str, float]]) -> None:
    failures = []
    for scenario, vals in computed.items():
        for key, value in vals.items():
            expected = EXPECTED[scenario][key]
            if abs(value - expected) > 1e-9:
                failures.append(
                    f"{scenario}.{key}: computed {value} != published {expected}"
                )

    print(f"Headline results — seed {SEED} paired comparison\n")
    print("| Metric | Tech-Driven | Human-Centric |")
    print("| --- | --- | --- |")
    for label, key, fmt in ROWS:
        td = fmt.format(computed["Tech-Driven"][key])
        hc = fmt.format(computed["Human-Centric"][key])
        print(f"| {label} | {td} | {hc} |")
    print()

    if failures:
        print("RECONCILIATION FAILED:")
        for f in failures:
            print(f"  - {f}")
        raise SystemExit(1)
    print("All five metrics reconcile with the README table.")


def render_figure(frames: dict[str, pd.DataFrame]) -> Path:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    out = FIG_DIR / f"unemployment_paths_seed_{SEED}.png"

    colors = {"Tech-Driven": "#b2182b", "Human-Centric": "#2166ac"}
    fig, ax = plt.subplots(figsize=(8, 4.5))
    for scenario, df in frames.items():
        ax.plot(
            df["tick"],
            df["unemployment_rate"],
            label=scenario,
            color=colors[scenario],
            linewidth=2,
        )

    # Mark the Tech-Driven peak.
    td = frames["Tech-Driven"]
    peak_idx = td["unemployment_rate"].idxmax()
    peak_tick = td.loc[peak_idx, "tick"]
    peak_val = td.loc[peak_idx, "unemployment_rate"]
    ax.annotate(
        f"Tech-Driven peak {peak_val:.1f}%",
        xy=(peak_tick, peak_val),
        xytext=(peak_tick + 28, peak_val - 4.5),
        fontsize=9,
        color=colors["Tech-Driven"],
        arrowprops=dict(arrowstyle="->", color=colors["Tech-Driven"], lw=1),
    )

    ax.set_xlabel("Month")
    ax.set_ylabel("Unemployment rate (%)")
    ax.set_title(
        "Workforce transitions under AI automation — seed 42424 (one paired run)",
        pad=12,
    )
    ax.set_xlim(0, 200)
    ax.set_ylim(0, 16)
    ax.grid(True, alpha=0.25)
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)
    return out


def main() -> None:
    frames = {name: load(name) for name in SCENARIOS}
    computed = {name: metrics(df) for name, df in frames.items()}
    verify_and_print(computed)
    out = render_figure(frames)
    print(f"\nFigure written to {out.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
