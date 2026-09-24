FINAL 720-ORDER AUDIT — READY TO RUN (NOT EXECUTED HERE)

Purpose
-------
Generate MATLAB provenance for the processing-order sensitivity of the sequential BESS allocation rule.
Primary manuscript comparison is THERMAL-ONLY, matching revised Eq. (3).

Authoritative source lineage
----------------------------
- Network/BFS/load model: IEEE33_BFS_EVCS_BESS_Sizing.m
- Submitted sequential mechanics: coordinated_bisection_bess
- Canonical centralized reference/config: B4P_canonical_freeze.mat supplied by the author.

Intentional changes
-------------------
1) Permutation-enabled variants accept the bus processing order explicitly.
2) Thermal comparator changes only the feasibility predicate from combined V+L to:
     converged && LmaxPct <= Lthr
3) BFS adds info.residual_pu for reporting only. Stopping rule and physical calculations are unchanged.

Sequential settings
-------------------
The canonical centralized freeze does not carry submitted sequential-algorithm controls, so the driver uses the authoritative values from IEEE33_BFS_EVCS_BESS_Sizing.m if absent:
- bisectionTol = 1e-3
- maxOuterBisection = 8

How to run
----------
1. Copy B4P_canonical_freeze.mat into this folder (or the parent folder).
2. Open MATLAB R2023b or compatible.
3. Set Current Folder to FINAL_720_ORDER_AUDIT_READY.
4. First leave:
       RUN_ORIGINAL_COMBINED = false
5. Run:
       run_720_order_audit_FINAL
6. Wait for:
       FINAL 720-ORDER AUDIT: PASS

Expected outputs
----------------
- order_audit_thermal_all3600_FINAL.csv
- order_audit_thermal_summary_FINAL.csv
- order_audit_best_worst_FINAL.csv
- Table5a_order_sensitivity_FINAL.csv
- order_audit_thermal_FINAL.mat
- order_audit_thermal_FINAL.log

Optional provenance audit
-------------------------
After the thermal-only pass succeeds, set RUN_ORIGINAL_COMBINED = true and rerun to generate the original combined V+L audit. Do not use the combined audit as the revised Eq. (3) comparator.

Important
---------
Do not edit outputs to force agreement with prior Python checks or manuscript prose. If results differ materially, preserve outputs and diagnose.
