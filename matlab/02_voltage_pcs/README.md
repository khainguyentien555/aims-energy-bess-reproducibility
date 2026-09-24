# 02 — Residual voltage support and conditional PCS capability

This workflow consumes the **frozen** branch-loading allocation and never re-optimizes it.

```matlab
cd('matlab/02_voltage_pcs')
run_B4PQ_replay
```

It performs the frozen-lineage replay, unity-power-factor correction, monotonicity gate for additional local capacitive support, bisection for the residual voltage-support requirement, and per-bus PCS/external-resource attribution.
