# Exported benchmark data

Each run produces three CSVs named `<scenario>_seed_<seed>_{history,plots,workers}.csv`: a monthly history panel, the exported plot series, and an end-of-run worker microdata snapshot.

- `*_seed_42424_*` — the paired Tech-Driven vs Human-Centric comparison reported in the memo, produced by `benchmark-paired-comparison` (same seed in both scenarios).
- All other seeds — additional ad-hoc robustness runs exported during development, not cited in the memo. The documented robustness procedure is `benchmark-seed-panel` (seeds 10101–10105).

To regenerate any of these, run the `benchmark-*` procedures from the Command Center; exports are written to this folder.

The committed seed-42424 pair can be turned back into the README's headline table and figure with `python3 extras/analyze_paired_comparison.py` (run from the repo root; requires pandas and matplotlib). That script reads only `*_seed_42424_history.csv`.
