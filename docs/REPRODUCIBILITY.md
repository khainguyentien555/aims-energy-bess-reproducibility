# Full reproduction protocol

## Environment

The frozen MATLAB provenance records **MATLAB 23.2 / R2023b** on Windows. `fmincon` is required for the centralized branch-loading optimization and both published-current-limit validation scripts.

Python is optional and is used only for integrity checks and data-driven figure regeneration.

## Step 0 — verify the repository artifacts

```bash
pip install -r requirements.txt
python python/validate_reference_results.py
```

This validates checksums and paper-facing numerical invariants without rerunning MATLAB.

## Step 1 — no-BESS baseline (optional helper)

In `matlab/01_branch_loading`, run `run_baseline_assessment_for_repo.m`. This packaging helper uses the production BFS settings (`1e-5` p.u., max 50 iterations) to regenerate the eight baseline cases. It introduces no new algorithm.

## Step 2 — canonical branch-loading-relief freeze

Run `matlab/01_branch_loading/run_B4P_freeze.m`.

Hard Gate-A production anchors:

| State | Vmin (p.u.) | Lmax (%) | Ploss (kW) |
|---|---:|---:|---:|
| Base feeder | 0.959149560 | 81.534028119 | 188.467135 |
| P2/D4, no BESS | 0.849556740 | 126.871264608 | 570.080340 |

The full canonical branch-loading BESS totals are 0, 0, 248.534779, 510.087115, 0, 205.343322, 525.473397, and 855.558619 kW for P1/D1 through P2/D4 in case order.

## Step 3 — residual voltage support and PCS capability

Run `matlab/02_voltage_pcs/run_B4PQ_replay.m`.

This script must consume the frozen B4-P allocation and must not re-optimize active power. Unity-power-factor correction remains insufficient in all eight nominal cases; the additional local capacitive support ranges from 114.770667 to 879.938422 kVAr.

## Step 4 — recharge deliverability

Run `matlab/03_recharge/run_recharge_replay_v2.m`.

For `T_peak = 4 h`, the active-rating/efficiency floor is 4.432133 h. The largest reference recharge duration is 31.192192 h (P2/D4 at `alpha_off = 1.00`). Branch loading remains below 100% in all evaluated reference recharge states.

## Step 5 — branch-rating sensitivity

Run `matlab/04_rating_sensitivity/run_B4P_rating_sensitivity_v2.m`.

The script first proves the `beta_S = 1.00` lineage before evaluating 0.90 and 1.10. For P2/D4 the corresponding BESS totals are 1343.352980, 855.558619, and 506.693279 kW.

## Step 6 — exhaustive processing-order audit

Run `matlab/05_order_audit/run_720_order_audit_FINAL.m` with `RUN_ORIGINAL_COMBINED = false`.

The thermal-only sequential rule is enumerated over all 720 processing orders. Across the five nonzero-storage nominal cases, the best-order excess spans down to 0.071679%, while the worst-order excess reaches 96.685956%.

## Step 7 — published branch-current-limit validation

Run both scripts in `matlab/06_external_current_validation/`.

- SmartGridComm 2024 multi-tier limits: no active-only current-feasible solution is admitted in any of the eight EVCS stress cases.
- Tercan et al. 2022 275/120-A limits: only P1/D4 and P2/D4 require nonzero active BESS, at 20.245228 and 158.529837 kW, respectively.

Only the external studies' published current limits are imported. Their source-system DER configuration and other assumptions are outside this reproduction boundary.

## Step 8 — regenerate data-driven figures

```bash
python python/make_figures.py
```

This regenerates Figure 2 and Figure 3 from repository CSVs. Figure 1 is conceptual; Figure 4 is retained with editable author source assets plus machine-readable bus-allocation data.

## Difference policy

Do not manually round or edit a generated artifact to make it agree with the paper. Preserve the raw run, MATLAB version, solver messages, and logs. A discrepancy is a reproducibility finding to diagnose, not a value to overwrite.
