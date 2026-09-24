# Numerical lineage and exactness boundaries

## Canonical hierarchy

1. **Production physics anchor** — the original BFS equations and original stopping settings (`tol = 1e-5`, max 50 iterations) are replayed first to prove that the packaged network/load/sign conventions match the production lineage.
2. **Canonical numerical freeze** — the same BFS equations are then evaluated at `tol = 1e-12`, max 200 iterations to avoid hiding boundary residuals behind the original stopping threshold.
3. **Frozen B4-P allocation** — later voltage/PCS and recharge workflows consume the canonical active allocation as immutable input.
4. **Sensitivity/audit layers** — branch-rating sensitivity, processing-order enumeration, and published-current validation are separate robustness analyses. They do not redefine the nominal branch-loading result.

## Important supersession note

A pre-v2 B4P-Q replay contained a MATLAB NaN-propagation expression in which `0*NaN` could still produce NaN. That superseded script is intentionally excluded. The packaged `run_B4PQ_replay.m` is the corrected replay with frozen-lineage, convergence, monotonicity, and post-support feasibility gates.

Similarly, `run_recharge_replay_v2.m` is canonical because it removes silent charging-power clipping, brackets the actual feasible recharge interval, audits monotonicity over the full interval, and checks the exact recharge-energy identity.

## Solver dependence

`fmincon` is used with 16 starts and tight feasibility/optimality tolerances in the canonical branch-loading optimization. The package records solver outputs and allocation spreads. Numerical equality across MATLAB releases is not asserted bit-for-bit; the frozen values and hard gates provide the comparison basis.
