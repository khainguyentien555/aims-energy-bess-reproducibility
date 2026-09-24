# 03 — Synchronous recharge deliverability

```matlab
cd('matlab/03_recharge')
run_recharge_replay_v2
```

The v2 replay preserves the explicit PCS charging-power constraint, brackets the actual feasible interval before bisection, audits monotonicity across that interval, checks the energy identity, and verifies the structural `T_rec/T_peak` invariance used to report the 4-h case compactly in the paper.
