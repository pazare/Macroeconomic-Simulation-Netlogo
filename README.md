# Workforce Transitions Under AI Automation

An agent-based NetLogo model of a small labor market adjusting to AI automation. The model compares two policy worlds, a Tech-Driven scenario with fast automation and thin retraining support, and a Human-Centric scenario with slower adoption and stronger worker support, holding everything else fixed. Both scenarios run on the same random seed, so every difference in outcomes is attributable to policy and technology parameters rather than chance.

Built for the Agentic Technologies course at Carnegie Mellon University. One tick is one month; the full horizon is 200 months of labor-market adjustment.

## Headline result

With identical workers, identical workplace geography, and identical random draws, the two scenarios diverge sharply over 200 months:

| Metric | Tech-Driven | Human-Centric |
| --- | --- | --- |
| Peak unemployment rate | 14.3% | 3.6% |
| Share of workers ever unemployed | 46.4% | 7.1% |
| Average unemployment spell among exposed workers | 34.4 months | 3.0 months |
| Unemployment burden Gini among exposed workers | 0.478 | 0.000 |
| Total output at horizon | 79.5 | 55.0 |

The core finding is an efficiency-equity tradeoff. Faster automation raises aggregate output but concentrates long unemployment spells on a subset of routine-task workers, and a capacity-constrained training system turns that exposure into persistent queues. Modest policy differences in training seats, course length, and subsidy support produce large aggregate differences because local peer spillovers amplify whichever regime is in place.

Full write-up with figures and limitations is in `AI Workforce Odyssey Memo.pdf`.

## How the model works

Twenty-eight heterogeneous workers are the only agents. Each worker has a task type (routine-cognitive, routine-manual, creative-analytical, or hybrid), a routine share that governs automation exposure, an adaptability level, and an explicit household balance sheet with labor income, government transfers, consumption, and liquid assets.

Workers move across five labor-market states: employed, at-risk, in-training, unemployed, and re-employed. Displacement occurs when routine exposure under rising automation pressure crosses a disruption threshold. At-risk workers queue for a hard-capped number of training seats; those stuck in the queue too long fall into unemployment, where skill scarring makes recovery progressively harder.

The emergent mechanism is the interaction of the training bottleneck with local coworker spillovers. Workers sit on a fixed workplace grid, and orthogonal neighbors act as coworkers: visible training and re-employment among neighbors raises a worker's willingness to apply for training, while unemployed neighbors suppress it. Recovery clusters and persistent-unemployment pockets emerge from these local interactions; they are not programmed as outcomes.

The model also reports observer-level sector accounts each month: output, private investment, transfers, training outlays, capital stock, and a goods-market gap reported as an explicit diagnostic residual rather than a forced equilibrium identity.

## How to run it

1. Install [NetLogo](https://ccl.northwestern.edu/netlogo/) 6.4 or later.
2. Open `model.nlogo`.
3. Pick a scenario with the `scenario-choice` chooser, then press `setup` and `go`.

For reproducible benchmark runs, use the Command Center:

- `benchmark-paired-comparison` runs both scenarios on the same seed, the controlled comparison behind the memo results.
- `benchmark-tech-driven` and `benchmark-human-centric` run the canonical single-scenario benchmarks.
- `benchmark-seed-panel` runs a small multi-seed robustness panel for both scenarios.

Each benchmark run exports three CSVs (monthly history, plot series, and end-of-run worker panel) named by scenario and seed. BehaviorSpace experiment definitions for the same benchmarks are embedded in the model file.

## Repository contents

- `model.nlogo` — the full simulation, including interface, documentation tab, and BehaviorSpace experiments
- `AI Workforce Odyssey Memo.pdf` — five-page memo with model design, scenario results, and limitations
- `AI Use Appendix.pdf` — transparency appendix documenting how AI assistants were used during development, including verification practices
- `extras/data/` — exported CSV runs, including the paired seed-42424 runs reported in the memo and additional robustness seeds

## Scope and limitations

This is a stylized course model, not a forecasting tool. Firms and government are scenario settings rather than strategic agents, a single training pathway is available, workers do not relocate, and the goods-market gap is an accounting diagnostic rather than a modeled equilibrium object. The theoretical framing draws on the task-based automation literature of Acemoglu and Restrepo; the model intentionally avoids claiming search-and-matching or general-equilibrium closure because those mechanisms are not implemented.

## References

- Acemoglu, D., and Restrepo, P. (2018). The Race between Man and Machine: Implications of Technology for Growth, Factor Shares, and Employment. American Economic Review, 108(6), 1488-1542.
- Acemoglu, D., and Restrepo, P. (2019). Automation and New Tasks: How Technology Displaces and Reinstates Labor. Journal of Economic Perspectives, 33(2), 3-30.

## License

MIT
