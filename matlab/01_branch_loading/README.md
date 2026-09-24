# 01 — Canonical branch-loading-relief freeze

Run in MATLAB R2023b or compatible with Optimization Toolbox available:

```matlab
cd('matlab/01_branch_loading')
run_B4P_freeze
```

The repository copy is configured for the full eight-case run (`RUN_STRESS_ONLY = false`). Gate A first replays the production-physics anchors at the original BFS tolerance, then the centralized thermal-only optimization is solved with the tightened canonical tolerance. Compare generated outputs with `results/reference/01_branch_loading/`.
