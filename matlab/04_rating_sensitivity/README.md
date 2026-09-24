# 04 — Branch-rating sensitivity

```matlab
cd('matlab/04_rating_sensitivity')
run_B4P_rating_sensitivity_v2
```

The script first replays `beta_S = 1.00` as a hard lineage gate, then evaluates 0.90 and 1.10. Only `cfg.Smax_branch` changes. The structural monotonicity check must pass.
