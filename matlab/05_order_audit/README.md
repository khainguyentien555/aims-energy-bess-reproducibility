# 05 — Exhaustive 720-order audit

```matlab
cd('matlab/05_order_audit')
run_720_order_audit_FINAL
```

The primary comparator is **thermal-only**, matching the revised branch-loading formulation. Leave `RUN_ORIGINAL_COMBINED = false` for the manuscript result. The script enumerates all 720 bus-processing orders for each of the five cases requiring nonzero nominal branch-loading-relief BESS.
