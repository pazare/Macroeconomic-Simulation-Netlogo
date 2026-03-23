extensions [csv]

;; ============================================================
;; WORKFORCE TRANSITIONS UNDER AI AUTOMATION
;; Canonical NetLogo model
;; One tick = one month
;; ============================================================
;; This file is intentionally the only simulation implementation in
;; the repository. Python audits NetLogo exports, and the browser plus
;; memo only visualize audited outputs.
;;
;; Workers are the only agents. Government policy and technology
;; conditions are represented with observer-level scenario settings.
;; This keeps the model inside the course assignment scope while still
;; allowing a more disciplined economic interpretation.
;;
;; The model tracks:
;; - worker transitions across five labor-market states
;; - household budgets with labor income, transfers, consumption,
;;   and liquid assets
;; - observer-level sector accounts for output, investment, transfers,
;;   training outlays, capital, and a goods-market gap
;;
;; Interface widgets create:
;; - scenario-choice
;; - initial-unemployment-pct
;; - initial-at-risk-pct

globals [
  ;; Scenario parameters
  ;; These are policy/technology levers that differ across the two
  ;; benchmark worlds. They are not chosen endogenously by agents.
  automation-rate
  disruption-threshold
  training-capacity
  training-duration
  subsidy-bonus
  adaptability-decay
  benefit-replacement-rate
  propensity-to-consume
  starting-savings-months
  training-cost-per-seat

  ;; Sector-account parameters
  ;; These govern the observer-level accounting block. The model does
  ;; not claim a full general equilibrium solution; instead it reports
  ;; sector flows transparently and leaves any residual as a diagnostic
  ;; goods-market gap.
  capital-stock
  next-capital-stock
  tech-efficiency
  investment-rate
  depreciation-rate
  tax-rate

  ;; Current aggregate flows
  ;; These are recomputed every month after worker states and budgets
  ;; have been updated.
  effective-automation
  labor-income-total
  transfer-income-total
  household-consumption-total
  desired-private-investment
  private-investment
  automation-output
  total-output
  training-outlays
  tax-revenue
  government-balance
  goods-market-gap

  ;; Simulation control
  ;; starting-seed is stored so an interesting run can be reproduced
  ;; exactly. run-finalized? prevents duplicate exports at the end of a
  ;; benchmark run.
  total-ticks
  starting-seed
  scenario-slug
  run-finalized?
  setup-complete?
  work-grid-min-x
  work-grid-max-x
  work-grid-min-y
  work-grid-max-y

  ;; Export buffers
  ;; History rows are accumulated in memory and written once per run so
  ;; the audit script can consume a single clean CSV per benchmark.
  history-rows
]

breed [workers worker]

workers-own [
  ;; Identity
  ;; baseline-monthly-income is a worker's pre-shock earning potential.
  ;; It is used to initialize savings and to anchor replacement income.
  task-type
  routine-share
  base-adaptability
  baseline-monthly-income

  ;; Dynamic state
  ;; total-unemployed-time and total-at-risk-time are intentionally
  ;; separate so the model does not confuse exposure with realized job
  ;; loss.
  adaptability
  current-state
  time-in-state
  total-unemployed-time
  total-at-risk-time
  times-disrupted
  training-remaining
  peer-boost
  work-patch
  work-row
  work-column

  ;; Household balance sheet
  ;; labor-income and transfer-income are separate by construction.
  ;; This avoids the original mistake of treating unemployment support
  ;; as if it were still labor earnings.
  labor-income
  transfer-income
  last-labor-income
  liquid-assets
  disposable-income
  consumption
]

;; ============================================================
;; Setup and benchmark procedures
;; ============================================================

to setup
  ;; Standard interactive entry point: create a fresh random seed so
  ;; casual runs differ unless the user explicitly asks for a fixed one.
  setup-core new-seed
end

to setup-with-fixed-seed [seed-value]
  ;; Scientific entry point: use a fixed seed to make the entire run
  ;; reproducible, including all stochastic admissions and transitions.
  setup-core seed-value
end

to benchmark-tech-driven
  ;; Canonical benchmark used by the audit pipeline and memo.
  benchmark-scenario "Tech-Driven" 10101
end

to benchmark-human-centric
  ;; Canonical benchmark used by the audit pipeline and memo.
  benchmark-scenario "Human-Centric" 20202
end

to benchmark-seed-panel
  ;; Small robustness panel: enough to show the model is not driven by
  ;; a single lucky seed, without making the assignment unmanageably
  ;; large or slow.
  foreach (list "Tech-Driven" "Human-Centric") [ scenario-name ->
    foreach (list 10101 10102 10103 10104 10105) [ seed-value ->
      benchmark-scenario scenario-name seed-value
    ]
  ]
end

to benchmark-scenario [scenario-name seed-value]
  ;; This wrapper makes benchmark runs readable from the Command Center
  ;; and ensures every exported file encodes both the scenario and seed.
  set scenario-choice scenario-name
  setup-with-fixed-seed seed-value
  run-until-complete
end

to run-until-complete
  ;; Headless-style convenience procedure for benchmarks. The while loop
  ;; mirrors repeatedly pressing the forever `go` button until the time
  ;; horizon is reached.
  while [ticks < total-ticks] [
    go
  ]
  if not run-finalized? [
    finalize-run
  ]
end

to setup-core [seed-value]
  ;; setup-core does all heavy initialization in one place so both the
  ;; GUI `setup` button and benchmark procedures share identical logic.
  clear-all
  set starting-seed seed-value
  random-seed starting-seed
  set total-ticks 200
  set run-finalized? false
  set setup-complete? false

  ;; Start from Tech-Driven defaults, then overwrite only the parameters
  ;; that differ if the chooser is set to Human-Centric. This keeps the
  ;; scenario logic compact and makes cross-scenario comparisons easier.
  apply-tech-driven
  if scenario-choice = "Human-Centric" [
    apply-human-centric
  ]
  set next-capital-stock capital-stock
  set scenario-slug scenario-slug-from-choice
  set history-rows history-header

  resize-world -7 7 -7 7
  set-patch-size 25
  set work-grid-min-x -3
  set work-grid-max-x 3
  set work-grid-min-y -1
  set work-grid-max-y 2

  ;; Create worker cohorts with heterogeneous routine exposure and
  ;; adaptability. The numbers are small enough to explain in a memo,
  ;; but heterogeneous enough to generate differentiated outcomes.
  create-workers 8 [
    set task-type "routine-cognitive"
    set routine-share 0.75 + random-float 0.20
    set base-adaptability 0.20 + random-float 0.30
    set shape "circle"
  ]
  create-workers 7 [
    set task-type "routine-manual"
    set routine-share 0.60 + random-float 0.20
    set base-adaptability 0.30 + random-float 0.30
    set shape "square"
  ]
  create-workers 6 [
    set task-type "creative-analytical"
    set routine-share 0.15 + random-float 0.20
    set base-adaptability 0.50 + random-float 0.30
    set shape "triangle"
  ]
  create-workers 7 [
    set task-type "hybrid"
    set routine-share 0.40 + random-float 0.20
    set base-adaptability 0.40 + random-float 0.30
    set shape "star"
  ]

  ask workers [
    ;; Start everyone as an employed worker with no accumulated damage,
    ;; then allow assign-initial-conditions to move the most exposed
    ;; workers into initial unemployment or at-risk status.
    set adaptability base-adaptability
    set current-state "employed"
    set time-in-state 0
    set total-unemployed-time 0
    set total-at-risk-time 0
    set times-disrupted 0
    set training-remaining 0
    set peer-boost 0
    set baseline-monthly-income (1 + base-adaptability) * task-premium
    set labor-income 0
    set transfer-income 0

    ;; last-labor-income is initialized to a worker's baseline so that
    ;; workers who begin the simulation unemployed still have a sensible
    ;; transfer base. Starting savings are set to two months of baseline
    ;; income, which creates a small but not unlimited household buffer.
    set last-labor-income baseline-monthly-income
    set liquid-assets starting-savings-months * baseline-monthly-income
    set disposable-income 0
    set consumption 0
    set work-patch nobody
    set work-row 0
    set work-column 0
    ;; Workers are placed onto a fixed workplace grid after creation.
    ;; Each patch in the grid is one desk, so orthogonal neighbors are
    ;; interpretable as direct coworkers rather than arbitrary proximity.
    setxy 0 0
    set color green
    set size 0.9
  ]

  assign-initial-conditions
  assign-workplace-grid

  ;; Start the tick counter before any procedure references `ticks`.
  ;; This allows the setup snapshot to be recorded as month 0 without
  ;; triggering NetLogo's "tick counter has not been started" error.
  reset-ticks

  ;; Record tick 0 after household budgets and sector accounts have been
  ;; computed. This makes exported histories easier to interpret because
  ;; the first row already contains a complete economic snapshot.
  update-effective-automation 0
  update-household-budgets
  update-sector-accounts false
  update-visuals
  record-history-row
  set setup-complete? true
end

to assign-initial-conditions
  ;; The initial shock is not random across workers: the most routine
  ;; exposed workers are placed into unemployment or at-risk states
  ;; first. This makes the starting condition economically interpretable.
  let n-unemp round (count workers * initial-unemployment-pct / 100)
  let n-risk round (count workers * initial-at-risk-pct / 100)
  let sorted-all sort-on [(- routine-share)] workers
  let idx 0
  foreach sorted-all [ w ->
    if idx < n-unemp [
      ask w [
        set current-state "unemployed"
        set time-in-state 0
      ]
      set idx idx + 1
    ]
  ]

  let sorted-employed sort-on [(- routine-share)] workers with [current-state = "employed"]
  set idx 0
  foreach sorted-employed [ w ->
    if idx < n-risk [
      ask w [
        set current-state "at-risk"
        set time-in-state 0
      ]
      set idx idx + 1
    ]
  ]
end

to assign-workplace-grid
  ;; The graphics window is a workplace floor rather than a random
  ;; space. Workers keep fixed desk locations, so local neighborhood
  ;; effects can be interpreted as coworker spillovers.
  let desk-patches workplace-patch-list
  let assigned-workers shuffle sort workers
  (foreach assigned-workers desk-patches [ [w p] ->
    ask w [
      set work-patch p
      set work-column [pxcor] of p
      set work-row [pycor] of p
      move-to p
    ]
  ])
end

to apply-tech-driven
  ;; High automation pressure, tight training, fast scarring.
  set automation-rate 0.80
  set disruption-threshold 0.50
  set training-capacity 5
  set training-duration 8
  set subsidy-bonus 0.00
  set adaptability-decay 0.010
  set benefit-replacement-rate 0.60
  set propensity-to-consume 0.35
  set starting-savings-months 2.0
  set training-cost-per-seat 0.60
  set capital-stock 12.0
  set tech-efficiency 1.40
  set investment-rate 0.18
  set depreciation-rate 0.03
  set tax-rate 0.18
end

to apply-human-centric
  ;; Slower automation rollout, more worker support, and gentler scarring.
  set automation-rate 0.55
  set disruption-threshold 0.50
  set training-capacity 12
  set training-duration 5
  set subsidy-bonus 0.20
  set adaptability-decay 0.005
  set benefit-replacement-rate 0.60
  set propensity-to-consume 0.35
  set starting-savings-months 2.0
  set training-cost-per-seat 0.60
  set capital-stock 12.0
  set tech-efficiency 1.00
  set investment-rate 0.12
  set depreciation-rate 0.03
  set tax-rate 0.18
end

;; ============================================================
;; Reporters
;; ============================================================

to-report scenario-slug-from-choice
  ;; File-safe scenario name for exports and the audit contract.
  if scenario-choice = "Human-Centric" [
    report "human_centric"
  ]
  report "tech_driven"
end

to-report count-in-state [state-name]
  report count workers with [current-state = state-name]
end

to-report unemployment-rate
  if not any? workers [ report 0 ]
  report (count-in-state "unemployed" / count workers) * 100
end

to-report pct-in-state [state-name]
  if not any? workers [ report 0 ]
  report (count-in-state state-name / count workers) * 100
end

to-report avg-unemployment-time
  ;; Average realized unemployment burden, not at-risk exposure.
  if not any? workers [ report 0 ]
  report mean [total-unemployed-time] of workers
end

to-report avg-at-risk-time
  ;; Separate exposure measure for workers who are still employed but vulnerable.
  if not any? workers [ report 0 ]
  report mean [total-at-risk-time] of workers
end

to-report avg-liquid-assets
  if not any? workers [ report 0 ]
  report mean [liquid-assets] of workers
end

to-report avg-consumption
  if not any? workers [ report 0 ]
  report mean [consumption] of workers
end

to-report ever-unemployed-share
  ;; Extensive margin of unemployment risk: what share of workers has
  ;; experienced any realized unemployment by the current month.
  if not any? workers [ report 0 ]
  report (count workers with [total-unemployed-time > 0] / count workers) * 100
end

to-report avg-unemployment-time-among-exposed
  ;; Intensive margin among affected workers only. This avoids mixing
  ;; never-unemployed workers with workers who have actually borne the
  ;; unemployment shock.
  let exposed workers with [total-unemployed-time > 0]
  if not any? exposed [ report 0 ]
  report mean [total-unemployed-time] of exposed
end

to-report unemployment-burden-gini-among-exposed
  ;; Dispersion among workers who have experienced unemployment. In a
  ;; small model this is more interpretable than an unconditional Gini
  ;; when only a few workers have positive duration.
  let exposed-values sort [total-unemployed-time] of workers with [total-unemployed-time > 0]
  if empty? exposed-values [ report 0 ]
  report gini-of-list exposed-values
end

to-report unemployment-duration-gini
  ;; Unconditional concentration across all workers. This is retained as
  ;; a diagnostic because it reacts sharply when only a small minority
  ;; has any unemployment history and everyone else remains at zero.
  report gini-of-list sort [total-unemployed-time] of workers
end

to-report consumption-gini
  ;; Distribution of realized monthly consumption across workers.
  report gini-of-list sort [consumption] of workers
end

to-report income-gini
  ;; Distribution of current monthly cash inflow, combining labor and transfers.
  report gini-of-list sort [labor-income + transfer-income] of workers
end

to-report task-premium
  ;; Task premia are simple reduced-form productivity multipliers. They
  ;; make workers with more complex task bundles earn more in baseline
  ;; conditions without requiring explicit firms or occupations.
  if task-type = "creative-analytical" [ report 1.30 ]
  if task-type = "hybrid" [ report 1.10 ]
  if task-type = "routine-cognitive" [ report 1.00 ]
  if task-type = "routine-manual" [ report 0.90 ]
  report 1.00
end

to-report labor-income-factor-for-state [state-name]
  ;; State factors apply only to labor income. Transfers are handled in a
  ;; separate block so the model keeps labor earnings conceptually clean.
  if state-name = "employed" [ report 1.00 ]
  if state-name = "at-risk" [ report 0.90 ]
  if state-name = "re-employed" [ report 0.95 ]
  report 0
end

to-report projected-labor-income [state-name]
  ;; Current labor income is a reduced-form function of skill and task
  ;; composition. This is intentionally simple and transparent.
  report (1 + adaptability) * task-premium * labor-income-factor-for-state state-name
end

to-report seats-in-use
  ;; A seat is occupied whenever a worker is in formal retraining or is
  ;; still completing an incumbent-worker course. This keeps capacity
  ;; accounting aligned with peer effects and program cost.
  report count workers with [current-state = "in-training" or training-remaining > 0]
end

to-report automation-task-gap
  ;; The automation block is strongest when workers have high routine
  ;; exposure but are no longer doing those tasks as paid labor.
  report mean [routine-share * (1 - labor-income-factor-for-state current-state)] of workers
end

to-report gini-of-list [values]
  ;; Generic Gini reporter used for multiple inequality concepts.
  let ordered-values sort values
  let n length ordered-values
  let total-value sum ordered-values
  if total-value = 0 [ report 0 ]
  let weighted-sum 0
  let i 1
  foreach ordered-values [ x ->
    set weighted-sum weighted-sum + (i * x)
    set i i + 1
  ]
  report max list 0 ((2 * weighted-sum) / (n * total-value) - (n + 1) / n)
end

to-report workplace-patch-list
  ;; Build a row-major list of desk patches. The 7-by-4 rectangle gives
  ;; exactly 28 desks for 28 workers, which keeps the workplace grid
  ;; visually legible and analytically tight.
  let desks []
  let y-values n-values (work-grid-max-y - work-grid-min-y + 1) [i -> work-grid-max-y - i]
  let x-values n-values (work-grid-max-x - work-grid-min-x + 1) [i -> work-grid-min-x + i]
  foreach y-values [y ->
    foreach x-values [x ->
      set desks lput (patch x y) desks
    ]
  ]
  report desks
end

to-report coworker-neighbors
  ;; Workers interact with the four desks that share an edge. This uses
  ;; NetLogo's patch-neighborhood logic in the same spirit as classic
  ;; local-interaction models such as Segregation, but here the social
  ;; meaning is "direct coworkers" rather than residential neighbors.
  report turtles-on [neighbors4] of patch-here
end

to-report avg-supportive-coworkers
  ;; System-level local-spillover measure: how many adjacent coworkers
  ;; are currently in training or recently re-employed on average?
  if not any? workers [ report 0 ]
  report mean [
    count (coworker-neighbors with [
      current-state = "in-training" or
      current-state = "re-employed" or
      training-remaining > 0
    ])
  ] of workers
end

to-report recovery-cluster-share
  ;; Emergent clustering metric: among workers who are currently in the
  ;; recovery pipeline, what share has at least one similarly recovering
  ;; coworker next to them?
  let recovering workers with [current-state = "in-training" or current-state = "re-employed"]
  if not any? recovering [ report 0 ]
  report (count recovering with [
    any? (coworker-neighbors with [current-state = "in-training" or current-state = "re-employed"])
  ] / count recovering) * 100
end

to update-coworker-peer-effects
  ;; Peer effects are recalculated from current coworker states instead
  ;; of accumulating forever. Training participation therefore depends on
  ;; observed local examples, not on an ever-rising hidden stock.
  ask workers [
    let coworkers coworker-neighbors
    let training-coworkers count coworkers with [current-state = "in-training" or training-remaining > 0]
    let reemployed-coworkers count coworkers with [current-state = "re-employed"]
    let unemployed-coworkers count coworkers with [current-state = "unemployed"]
    set peer-boost max list 0
      (min list 0.35 ((0.05 * training-coworkers) + (0.08 * reemployed-coworkers) - (0.03 * unemployed-coworkers)))
  ]
end

to refresh-visual-scaffold
  ;; The graphics window is a workplace grid. Every visible desk is
  ;; occupied by exactly one worker, which makes spatial clusters easy
  ;; to read as coworker patterns rather than random scatter.
  ask patches [
    set pcolor black
    set plabel ""
  ]

  ask patches with [
    pxcor >= work-grid-min-x and pxcor <= work-grid-max-x and
    pycor >= work-grid-min-y and pycor <= work-grid-max-y
  ] [
    ifelse ((pxcor + pycor) mod 2 = 0) [
      set pcolor gray
    ] [
      set pcolor white
    ]
  ]

  ask patch 0 (work-grid-max-y + 2) [
    set plabel "Workplace grid"
    set plabel-color white
  ]

  ask patch 0 (work-grid-max-y + 1) [
    set plabel "Adjacent desks = coworker spillovers"
    set plabel-color white
  ]

  ask patch (work-grid-min-x - 2) work-grid-max-y [
    set plabel "Team A"
    set plabel-color white
  ]
  ask patch (work-grid-min-x - 2) (work-grid-max-y - 1) [
    set plabel "Team B"
    set plabel-color white
  ]
  ask patch (work-grid-min-x - 2) (work-grid-max-y - 2) [
    set plabel "Team C"
    set plabel-color white
  ]
  ask patch (work-grid-min-x - 2) work-grid-min-y [
    set plabel "Team D"
    set plabel-color white
  ]
end

;; ============================================================
;; Household budgets and sector accounts
;; ============================================================

to update-household-budgets
  ask workers [
    ;; Step 1: compute labor income from the worker's current state.
    set labor-income projected-labor-income current-state
    if labor-income > 0 [
      ;; last-labor-income updates only when the worker is actually
      ;; earning labor income. It therefore acts like a remembered wage
      ;; base for unemployment insurance.
      set last-labor-income labor-income
    ]

    if member? current-state (list "unemployed" "in-training") [
      ;; In this first serious macro pass, training stipends are treated
      ;; the same way as unemployment benefits: both are transfers tied
      ;; to prior earnings rather than new labor income.
      set transfer-income benefit-replacement-rate * last-labor-income
    ]
    if not member? current-state (list "unemployed" "in-training") [
      set transfer-income 0
    ]

    ;; Cash-on-hand consists of last month's remaining assets plus this
    ;; month's current inflows. Consumption is a fixed share of available
    ;; resources, and the residual becomes next month's liquid assets.
    set disposable-income liquid-assets + labor-income + transfer-income
    set consumption min list disposable-income (propensity-to-consume * disposable-income)
    set liquid-assets max list 0 (disposable-income - consumption)
  ]
end

to update-effective-automation [period-index]
  ;; The automation path is indexed to the period being simulated, not
  ;; to the previously recorded tick. This keeps the current month's
  ;; transition rules and macro flows on the same time basis.
  set effective-automation automation-rate *
    (0.5 + 0.5 * (1 - exp (-0.02 * period-index))) *
    (1 + 0.2 * sin (0.15 * period-index))
end

to update-sector-accounts [stage-next-capital?]

  ;; Aggregate the worker-level flows after household budgets have been
  ;; updated. These are observer-level accounts, not market-clearing
  ;; equilibrium objects.
  set labor-income-total sum [labor-income] of workers
  set transfer-income-total sum [transfer-income] of workers
  set household-consumption-total sum [consumption] of workers
  set training-outlays training-cost-per-seat * seats-in-use

  ;; Automation output depends on installed capital, technology, the
  ;; current adoption level, and how much routine task mass has shifted
  ;; away from paid labor.
  set automation-output tech-efficiency * (capital-stock ^ 0.35) * effective-automation * automation-task-gap * count workers
  set total-output labor-income-total + automation-output

  ;; Private investment is desired as a share of automation output but
  ;; is capped by currently available output net of consumption and
  ;; training outlays. This avoids the explosive accumulation present in
  ;; the earlier version of the repo.
  set desired-private-investment investment-rate * automation-output
  set private-investment min list desired-private-investment
    (max list 0 (total-output - household-consumption-total - training-outlays))

  ;; Government balance is purely an accounting object here: tax revenue
  ;; minus transfer and training spending. The model reports the residual
  ;; goods-market gap instead of pretending that Y = C + I + G holds by
  ;; construction.
  set tax-revenue tax-rate * total-output
  set government-balance tax-revenue - transfer-income-total - training-outlays
  set goods-market-gap total-output - household-consumption-total - training-outlays - private-investment

  ifelse stage-next-capital? [
    ;; Capital used in the recorded row is the capital that actually
    ;; produced that month's automation output. The next-period stock is
    ;; staged separately and only applied at the start of the next go.
    set next-capital-stock max list 0.50 ((1 - depreciation-rate) * capital-stock + private-investment)
  ] [
    set next-capital-stock capital-stock
  ]
end

;; ============================================================
;; Simulation loop
;; ============================================================

to go
  ;; Defensive initialization: if the user presses `go` before a clean
  ;; `setup` run has completed, build the initial state first so the
  ;; tick counter and worker population both exist.
  if not is-boolean? setup-complete? [
    setup
  ]
  if not setup-complete? [
    setup
  ]

  ;; The stop test sits at the top so the final step is not partially
  ;; executed before exports are written.
  if ticks >= total-ticks [
    if not run-finalized? [
      finalize-run
    ]
    stop
  ]

  ;; Move the staged capital stock into use for the current month
  ;; before worker decisions and current-period accounting are computed.
  set capital-stock next-capital-stock

  ;; Use the period about to be simulated, so worker transitions and the
  ;; recorded macro row share the same automation intensity.
  update-effective-automation (ticks + 1)

  ;; Peer support is calculated from the current workplace grid before
  ;; workers make this month's training and transition decisions.
  update-coworker-peer-effects

  ;; Rule 1: Displacement pressure on employed workers
  ask workers with [current-state = "employed"] [
    ;; Only currently employed workers can become newly at-risk. The key
    ;; state variable is routine exposure times the current automation
    ;; pressure.
    if routine-share * effective-automation > disruption-threshold [
      set current-state "at-risk"
      set time-in-state 0
      set times-disrupted times-disrupted + 1
    ]
  ]

  ;; Rule 2: At-risk workers apply for training
  let seats-available max list 0 (training-capacity - seats-in-use)
  if seats-available > 0 [
    ;; Admission depends on worker adaptability, any local peer boost,
    ;; and scenario-level subsidy support. If demand exceeds supply,
    ;; seats go to workers with the strongest transition prospects.
    let applicants workers with [
      current-state = "at-risk" and
      training-remaining = 0 and
      random-float 1.0 < min list 0.95 (0.15 + (0.55 * adaptability) + peer-boost + subsidy-bonus)
    ]
    ifelse count applicants > seats-available [
      let ranked sort-on [(- (adaptability + peer-boost))] applicants
      let winners sublist ranked 0 seats-available
      foreach winners [ w ->
        ask w [
          set current-state "in-training"
          set time-in-state 0
        ]
      ]
    ] [
      ask applicants [
        set current-state "in-training"
        set time-in-state 0
      ]
    ]
  ]

  ;; Rule 3: Employed workers can train concurrently
  let concurrent-seats max list 0 (training-capacity - seats-in-use)
  if concurrent-seats > 0 [
    ;; Concurrent training is a worker-retention channel. It helps the
    ;; model represent upskilling before full displacement occurs, and
    ;; coworker spillovers make workers more willing to join once a
    ;; local training culture becomes visible on the grid.
    let concurrent-applicants workers with [
      current-state = "employed" and
      training-remaining = 0 and
      random-float 1.0 < min list 0.85 (0.04 + (0.12 * (1 - adaptability)) + peer-boost)
    ]
    ifelse count concurrent-applicants > concurrent-seats [
      let ranked sort-on [(- (1 - adaptability))] concurrent-applicants
      let winners sublist ranked 0 concurrent-seats
      foreach winners [ w ->
        ask w [
          set training-remaining training-duration
        ]
      ]
    ] [
      ask concurrent-applicants [
        set training-remaining training-duration
      ]
    ]
  ]

  ;; Rule 4: At-risk workers who wait too long become unemployed
  ask workers with [current-state = "at-risk" and time-in-state > 10] [
    ;; Queue delay itself can create unemployment even when the worker's
    ;; underlying adaptability is not especially low.
    set current-state "unemployed"
    set time-in-state 0
  ]

  ;; Training completion
  ask workers with [current-state = "in-training" and time-in-state >= training-duration] [
    ;; Subsidies and peer effects matter again here by changing the odds
    ;; that training translates into re-employment. Formal retraining
    ;; also raises human capital directly, even if the job match fails.
    let success-prob min list 0.95 (adaptability + peer-boost + subsidy-bonus)
    ifelse random-float 1.0 < success-prob [
      set adaptability min list 0.95 (adaptability + 0.15)
      set current-state "re-employed"
    ] [
      set adaptability min list 0.95 (adaptability + 0.05)
      set current-state "unemployed"
    ]
    set time-in-state 0
  ]

  ;; Re-employed workers stabilize into standard employment
  ask workers with [current-state = "re-employed" and time-in-state >= 15] [
    ;; Re-employed workers are treated as temporarily fragile matches,
    ;; then become fully employed after a stabilization window.
    set current-state "employed"
    set time-in-state 0
  ]

  ;; Unemployed workers can re-enter training
  let reentry-seats max list 0 (training-capacity - seats-in-use)
  if reentry-seats > 0 [
    ;; This allows the training system to work as a re-entry channel for
    ;; displaced workers, not just as a preemptive support tool.
    let reentry-applicants workers with [
      current-state = "unemployed" and
      training-remaining = 0 and
      random-float 1.0 < min list 0.80 (0.03 + (0.12 * adaptability) + peer-boost)
    ]
    ifelse count reentry-applicants > reentry-seats [
      let ranked sort-on [(- (adaptability + peer-boost))] reentry-applicants
      let winners sublist ranked 0 reentry-seats
      foreach winners [ w ->
        ask w [
          set current-state "in-training"
          set time-in-state 0
        ]
      ]
    ] [
      ask reentry-applicants [
        set current-state "in-training"
        set time-in-state 0
      ]
    ]
  ]

  ;; Direct hire from unemployment
  ask workers with [current-state = "unemployed"] [
    ;; Some workers skip formal training and return directly to work.
    ;; This gives the labor market a limited spontaneous recovery path.
    if random-float 1.0 < min list 0.30 (0.01 + (0.05 * adaptability) + (0.25 * peer-boost)) [
      set current-state "re-employed"
      set time-in-state 0
    ]
  ]

  ;; Skill atrophy and exposure accounting
  ask workers with [current-state = "unemployed"] [
    ;; Only realized unemployment causes skill scarring and counts
    ;; toward unemployment duration.
    set adaptability max list 0.05 (adaptability - adaptability-decay)
    set total-unemployed-time total-unemployed-time + 1
  ]
  ask workers with [current-state = "at-risk"] [
    ;; Exposure is tracked separately so the memo can distinguish
    ;; vulnerability from realized job loss.
    set total-at-risk-time total-at-risk-time + 1
  ]

  ;; In-progress incumbent-worker training continues even if a worker is
  ;; displaced while the course is underway. That avoids "ghost
  ;; training" where course signals remain visible to coworkers but
  ;; seats, timing, and skill accumulation stop moving.
  ask workers with [training-remaining > 0] [
    set training-remaining training-remaining - 1
    if training-remaining = 0 [
      set adaptability min list 0.95 (adaptability + 0.10)
    ]
  ]

  ;; Recompute coworker support after state changes so the graphics
  ;; window and exported row reflect the post-transition neighborhood.
  update-coworker-peer-effects

  ask workers [
    ;; Timers are incremented after all transitions so duration tests are
    ;; measured in completed months spent in a state.
    set time-in-state time-in-state + 1
  ]

  ;; Economic accounting is performed after the state transitions so the
  ;; recorded row reflects the post-transition economy for that month.
  update-household-budgets
  update-sector-accounts true
  update-visuals
  tick
  record-history-row
end

to update-visuals
  ;; The graphics window is a workplace floor. Patch location is fixed
  ;; by desk assignment. Colors encode labor-market state:
  ;; green = employed, yellow = at-risk, orange = in-training,
  ;; red = unemployed, sky = re-employed. Shapes encode task type:
  ;; circle = routine-cognitive, square = routine-manual,
  ;; triangle = creative-analytical, star = hybrid. Clusters of orange
  ;; and sky agents therefore indicate genuine local spillovers rather
  ;; than random overlap.
  refresh-visual-scaffold
  ask workers [
    if current-state = "employed" [ set color green ]
    if current-state = "at-risk" [ set color yellow ]
    if current-state = "in-training" [ set color orange ]
    if current-state = "unemployed" [ set color red ]
    if current-state = "re-employed" [ set color sky ]
    set size 0.9
    move-to work-patch
  ]
end

;; ============================================================
;; Export and reporting
;; ============================================================

to finalize-run
  ;; finalize-run is intentionally idempotent through run-finalized? so
  ;; benchmarks and manual runs do not write duplicate exports.
  set run-finalized? true
  export-run-data
  print-summary
end

to export-run-data
  ;; Every benchmark run exports a full monthly history, a final worker
  ;; microdata snapshot, and plot data. The Python audit script reads the
  ;; first two; the plots file is there for manual inspection if needed.
  let history-file (word "extras/data/" scenario-slug "_seed_" starting-seed "_history.csv")
  let worker-file (word "extras/data/" scenario-slug "_seed_" starting-seed "_workers.csv")
  let plot-file (word "extras/data/" scenario-slug "_seed_" starting-seed "_plots.csv")

  if file-exists? history-file [ file-delete history-file ]
  if file-exists? worker-file [ file-delete worker-file ]
  if file-exists? plot-file [ file-delete plot-file ]

  csv:to-file history-file history-rows
  csv:to-file worker-file final-worker-rows
  export-all-plots plot-file
end

to-report history-header
  ;; The audit script depends on these exact column names. If you change
  ;; them, you must update verify_model.py and downstream consumers too.
  report (list
    (list
      "tick" "scenario" "seed" "employed" "at_risk" "in_training" "unemployed" "re_employed"
      "seats_in_use"
      "unemployment_rate" "ever_unemployed_share" "avg_unemployment_time" "avg_unemployment_time_exposed" "avg_at_risk_time"
      "unemployment_burden_gini_exposed" "unemployment_duration_gini" "consumption_gini" "income_gini"
      "avg_supportive_coworkers" "recovery_cluster_share"
      "avg_liquid_assets" "min_liquid_assets" "avg_consumption" "min_consumption"
      "labor_income_total" "transfer_income_total" "training_outlays"
      "tax_revenue" "government_balance"
      "automation_output" "desired_private_investment" "private_investment"
      "total_output" "capital_stock" "goods_market_gap"))
end

to record-history-row
  ;; One row per month, including tick 0. These histories are what allow
  ;; the downstream pipeline to compute audited scenario summaries.
  let row (list
    ticks
    scenario-slug
    starting-seed
    count-in-state "employed"
    count-in-state "at-risk"
    count-in-state "in-training"
    count-in-state "unemployed"
    count-in-state "re-employed"
    seats-in-use
    unemployment-rate
    ever-unemployed-share
    avg-unemployment-time
    avg-unemployment-time-among-exposed
    avg-at-risk-time
    unemployment-burden-gini-among-exposed
    unemployment-duration-gini
    consumption-gini
    income-gini
    avg-supportive-coworkers
    recovery-cluster-share
    avg-liquid-assets
    min [liquid-assets] of workers
    avg-consumption
    min [consumption] of workers
    labor-income-total
    transfer-income-total
    training-outlays
    tax-revenue
    government-balance
    automation-output
    desired-private-investment
    private-investment
    total-output
    capital-stock
    goods-market-gap)
  set history-rows lput row history-rows
end

to-report final-worker-rows
  ;; Final worker-level microdata supports richer post-run diagnosis,
  ;; such as checking which task groups remain unemployed.
  let rows (list
    (list
      "scenario" "seed" "who" "task_type" "routine_share" "base_adaptability"
      "work_row" "work_column"
      "adaptability" "current_state" "time_in_state"
      "total_unemployed_time" "total_at_risk_time" "times_disrupted"
      "labor_income" "transfer_income" "last_labor_income"
      "liquid_assets" "disposable_income" "consumption" "peer_boost"))
  foreach sort-on [who] workers [ w ->
    set rows lput
      (list
        scenario-slug
        starting-seed
        [who] of w
        [task-type] of w
        [routine-share] of w
        [base-adaptability] of w
        [work-row] of w
        [work-column] of w
        [adaptability] of w
        [current-state] of w
        [time-in-state] of w
        [total-unemployed-time] of w
        [total-at-risk-time] of w
        [times-disrupted] of w
        [labor-income] of w
        [transfer-income] of w
        [last-labor-income] of w
        [liquid-assets] of w
        [disposable-income] of w
        [consumption] of w
        [peer-boost] of w)
      rows
  ]
  report rows
end

to print-summary
  ;; Human-readable console summary for classroom demos and quick checks.
  print "=== SIMULATION COMPLETE ==="
  print (word "Scenario: " scenario-choice " | Seed: " starting-seed)
  print (word
    "Employed: " count-in-state "employed"
    "  At-Risk: " count-in-state "at-risk"
    "  In-Training: " count-in-state "in-training"
    "  Unemployed: " count-in-state "unemployed"
    "  Re-Employed: " count-in-state "re-employed")
  print (word
    "Avg Unemp Time: " precision avg-unemployment-time 2
    "  Exposed Avg: " precision avg-unemployment-time-among-exposed 2
    "  Ever Unemployed: " precision ever-unemployed-share 1 "%")
  print (word
    "Avg At-Risk Time: " precision avg-at-risk-time 2
    "  Burden Gini (Exposed): " precision unemployment-burden-gini-among-exposed 3
    "  Uncond Duration Gini: " precision unemployment-duration-gini 3
    "  Consumption Gini: " precision consumption-gini 3)
  print (word
    "Avg Supportive Coworkers: " precision avg-supportive-coworkers 2
    "  Recovery Cluster Share: " precision recovery-cluster-share 1 "%")
  print (word
    "Output: " precision total-output 2
    "  Consumption: " precision household-consumption-total 2
    "  Investment: " precision private-investment 2
    "  Transfers: " precision transfer-income-total 2
    "  Training Outlays: " precision training-outlays 2)
  print (word
    "Capital Stock: " precision capital-stock 2
    "  Gov Balance: " precision government-balance 2
    "  Goods Gap: " precision goods-market-gap 2)
end
@#$#@#$#@
GRAPHICS-WINDOW
215
10
590
385
-1
-1
25.0
1
10
1
1
1
0
1
1
1
-7
7
-7
7
0
0
1
ticks
30.0

BUTTON
15
10
95
50
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
100
10
195
50
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
15
60
195
105
scenario-choice
scenario-choice
"Tech-Driven" "Human-Centric"
0

SLIDER
15
115
195
148
initial-unemployment-pct
initial-unemployment-pct
0
20
5.0
1
1
%
HORIZONTAL

SLIDER
15
155
195
188
initial-at-risk-pct
initial-at-risk-pct
0
20
10.0
1
1
%
HORIZONTAL

MONITOR
215
395
290
440
Tick
ticks
0
1
11

MONITOR
295
395
395
440
Unemployed
count-in-state "unemployed"
0
1
11

MONITOR
400
395
510
440
Re-Employed
count-in-state "re-employed"
0
1
11

MONITOR
515
395
630
440
In Training
count-in-state "in-training"
0
1
11

MONITOR
215
450
370
495
Avg Unemp Time
avg-unemployment-time
2
1
11

MONITOR
375
450
480
495
Burden Gini
unemployment-burden-gini-among-exposed
3
1
11

MONITOR
485
450
590
495
Output
total-output
2
1
11

MONITOR
15
200
100
245
Capital
capital-stock
2
1
11

MONITOR
105
200
195
245
Seed
starting-seed
0
1
11

PLOT
600
10
970
170
"Unemployment Rate"
"Month"
"% of Workers"
0.0
200.0
0.0
100.0
true
true
"" ""
PENS
"Unemployed" 1.0 0 15 true "" "plot unemployment-rate"
"At-Risk" 1.0 0 45 true "" "plot pct-in-state \"at-risk\""

PLOT
600
175
970
345
"State Distribution"
"Month"
"Count"
0.0
200.0
0.0
30.0
true
true
"" ""
PENS
"Employed" 1.0 0 55 true "" "plot count-in-state \"employed\""
"At-Risk" 1.0 0 45 true "" "plot count-in-state \"at-risk\""
"In Training" 1.0 0 25 true "" "plot count-in-state \"in-training\""
"Unemployed" 1.0 0 15 true "" "plot count-in-state \"unemployed\""
"Re-Employed" 1.0 0 105 true "" "plot count-in-state \"re-employed\""

PLOT
600
350
970
490
"Distributional Burden"
"Month"
"Gini"
0.0
200.0
0.0
1.0
true
true
"" ""
PENS
"Burden (Exposed)" 1.0 0 125 true "" "plot unemployment-burden-gini-among-exposed"
"Consumption" 1.0 0 55 true "" "plot consumption-gini"
"Income" 1.0 0 15 true "" "plot income-gini"

PLOT
600
495
970
640
"Sector Accounts"
"Month"
"Flow"
0.0
200.0
0.0
60.0
true
true
"" ""
PENS
"Output" 1.0 0 0 true "" "plot total-output"
"Consumption" 1.0 0 55 true "" "plot household-consumption-total"
"Transfers" 1.0 0 15 true "" "plot transfer-income-total"
"Investment" 1.0 0 25 true "" "plot private-investment"
"Training" 1.0 0 105 true "" "plot training-outlays"
@#$#@#$#@
## WHAT IS IT?

This model simulates workforce transitions under AI pressure in a small labor market with 28 workers. It keeps the assignment scope intentionally narrow: workers are the only agents, while policy and technology are represented through scenario settings.

Each tick is one month. The canonical logic lives in this NetLogo model. Downstream Python, preview, and memo artifacts are intended to audit and present NetLogo outputs rather than reproduce the model independently.

## HOW IT WORKS

Workers differ by:

- task type
- routine share
- adaptability
- current labor-market state
- liquid assets

The five worker states are:

- employed
- at-risk
- in-training
- unemployed
- re-employed

Programmed transitions include:

- displacement when routine exposure times effective automation crosses a threshold
- admission to limited training seats
- timeout from at-risk to unemployed
- training completion to re-employed or unemployed
- direct re-hire from unemployment

The emergent mechanism is the interaction of training bottlenecks with local coworker spillovers on the workplace grid.
Workers are assigned to a fixed workplace grid, and orthogonal neighbors on that grid are treated as direct coworkers. This means local training and re-employment clusters can emerge visibly when coworker spillovers reinforce each other.

## VISUAL LEGEND

The main graphics window is not decorative. It is a workplace floor:

- one patch = one desk
- location = fixed coworker neighborhood
- color = current labor-market state
- shape = task type

Colors:

- green = employed
- yellow = at-risk
- orange = in-training
- red = unemployed
- sky blue = re-employed

Shapes:

- circle = routine-cognitive
- square = routine-manual
- triangle = creative-analytical
- star = hybrid

## HOUSEHOLD FINANCE

Workers who remain employed, at-risk, or re-employed earn labor income. Workers who are unemployed or in-training receive government transfers equal to a replacement share of their most recent labor income.

Formal retraining also raises adaptability directly. Successful completion gives a larger adaptability gain than unsuccessful completion, but both outcomes represent some human-capital accumulation rather than a pure state-transition lottery.

Household cash-on-hand each month is:

- beginning liquid assets
- plus current labor income
- plus government transfers

Consumption is a fixed share of cash-on-hand. Remaining resources become end-of-month liquid assets. Assets cannot go below zero in this version of the model.

## SECTOR ACCOUNTS

The model reports observer-level aggregates:

- labor income
- transfers
- training outlays
- automation output
- private investment
- total output
- capital stock
- a goods-market gap

The goods-market gap is reported explicitly instead of forcing a false equilibrium identity.

The exported monthly rows are time-indexed so that month `t` uses month-`t` automation pressure for both worker transitions and macro flows. The `capital stock` shown in a row is the beginning-of-month stock used to produce that month's automation output; the next-period stock is staged for the following month.

## HOW TO USE IT

1. Choose a scenario.
2. Set initial unemployment and at-risk shares if you want to change the baseline.
3. Press `setup`, then `go`.
4. Use `benchmark-tech-driven`, `benchmark-human-centric`, or `benchmark-seed-panel` from the Command Center to generate CSV exports in `extras/data/`.

## THINGS TO NOTICE

- Whether training capacity becomes a binding bottleneck.
- How quickly unemployed workers deplete liquid assets.
- How unemployment incidence differs from burden dispersion among workers who were actually exposed.
- Why the unconditional unemployment-duration Gini is best treated as a diagnostic in a small model.
- Whether clusters of in-training or re-employed workers appear on the workplace grid.
- Whether adjacent coworker spillovers create pockets of faster recovery or persistent unemployment.
- Whether the tech-driven scenario produces larger transfer dependence and asset depletion.

## THINGS TO TRY

- Compare the two built-in scenarios with the same seed.
- Increase initial unemployment and study transfer pressure.
- Lower training capacity and watch the bottleneck intensify.
- Change the disruption threshold and compare displacement timing.

## EXTENDING THE MODEL

- Add richer household finance with borrowing constraints.
- Endogenize firm investment and AI adoption decisions.
- Add richer geography or worker mobility.
- Introduce multiple training pathways with different duration and cost.

## NETLOGO FEATURES

- `csv` extension for canonical exports
- seeded setup procedures for reproducibility
- embedded BehaviorSpace experiment definitions

## RELATED MODELS

This model is a course assignment model rather than a library model. It is closest to stylized labor-transition ABMs and task-based automation thought experiments.

## CREDITS AND REFERENCES

- Official NetLogo documentation: https://docs.netlogo.org/
- Task-based automation framing: Acemoglu and Restrepo
- This version intentionally avoids claiming DMP matching or general-equilibrium closure because those mechanisms are not implemented directly.
@#$#@#$#@
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@

@#$#@#$#@

@#$#@#$#@
<experiments>
  <experiment name="Tech-Driven Benchmark" repetitions="1" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup-with-fixed-seed 10101</setup>
    <go>go</go>
    <final>finalize-run</final>
    <timeLimit steps="200"/>
    <metric>count-in-state "employed"</metric>
    <metric>count-in-state "unemployed"</metric>
    <metric>ever-unemployed-share</metric>
    <metric>avg-unemployment-time</metric>
    <metric>avg-unemployment-time-among-exposed</metric>
    <metric>unemployment-burden-gini-among-exposed</metric>
    <metric>avg-supportive-coworkers</metric>
    <metric>recovery-cluster-share</metric>
    <metric>unemployment-duration-gini</metric>
    <metric>consumption-gini</metric>
    <metric>total-output</metric>
    <metric>capital-stock</metric>
    <metric>goods-market-gap</metric>
    <enumeratedValueSet variable="scenario-choice">
      <value value="&quot;Tech-Driven&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-unemployment-pct">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-at-risk-pct">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Human-Centric Benchmark" repetitions="1" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup-with-fixed-seed 20202</setup>
    <go>go</go>
    <final>finalize-run</final>
    <timeLimit steps="200"/>
    <metric>count-in-state "employed"</metric>
    <metric>count-in-state "unemployed"</metric>
    <metric>ever-unemployed-share</metric>
    <metric>avg-unemployment-time</metric>
    <metric>avg-unemployment-time-among-exposed</metric>
    <metric>unemployment-burden-gini-among-exposed</metric>
    <metric>avg-supportive-coworkers</metric>
    <metric>recovery-cluster-share</metric>
    <metric>unemployment-duration-gini</metric>
    <metric>consumption-gini</metric>
    <metric>total-output</metric>
    <metric>capital-stock</metric>
    <metric>goods-market-gap</metric>
    <enumeratedValueSet variable="scenario-choice">
      <value value="&quot;Human-Centric&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-unemployment-pct">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-at-risk-pct">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Scenario Seed Panel" repetitions="1" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup-with-fixed-seed (10000 + behaviorspace-run-number)</setup>
    <go>go</go>
    <timeLimit steps="200"/>
    <metric>count-in-state "employed"</metric>
    <metric>count-in-state "unemployed"</metric>
    <metric>ever-unemployed-share</metric>
    <metric>avg-unemployment-time</metric>
    <metric>avg-unemployment-time-among-exposed</metric>
    <metric>unemployment-burden-gini-among-exposed</metric>
    <metric>avg-supportive-coworkers</metric>
    <metric>recovery-cluster-share</metric>
    <metric>unemployment-duration-gini</metric>
    <metric>consumption-gini</metric>
    <metric>total-output</metric>
    <metric>capital-stock</metric>
    <metric>goods-market-gap</metric>
    <enumeratedValueSet variable="scenario-choice">
      <value value="&quot;Tech-Driven&quot;"/>
      <value value="&quot;Human-Centric&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-unemployment-pct">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-at-risk-pct">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
