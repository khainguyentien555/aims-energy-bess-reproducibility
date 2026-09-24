# Paper-to-code/data map

| Paper item | Primary reproducibility source | Reference artifact |
|---|---|---|
| Figure 1 — five-part adequacy decomposition | Author schematic | `figures/source/Figure1_decomposition.svg`, editable PPTX |
| Table 1 — system/model parameters | `data/parameters/model_parameters.csv`; MATLAB workflow configs | — |
| Table 2 — IEEE 33-bus branch data / planning limits | `data/system/Supplementary_Table_S1_branch_dataset.csv`; `ieee33_data.m` | — |
| Table 3 — placements and demand scenarios | `data/scenarios/evcs_scenarios.csv`; `run_B4P_freeze.m` | — |
| Figure 2 — baseline voltage profiles | `data/system/baseline_voltage_profiles_no_BESS.csv`; `python/make_figures.py` | `figures/reference/Figure2_baseline_voltage_profiles.png` |
| Table 4 — baseline grid-impact indices | baseline MATLAB lineage / `data/system/baseline_metrics_no_BESS.csv` | same CSV |
| Figure 3 — grid/BESS active-power decomposition | canonical B4-P totals; `python/make_figures.py` | `figures/reference/Figure3_grid_BESS_decomposition.png` |
| Table 5 — processing-order sensitivity | `matlab/05_order_audit/run_720_order_audit_FINAL.m` | `results/reference/05_order_audit/Table5a_order_sensitivity_FINAL.csv` |
| Figure 4 — bus-level D4 BESS allocation | `data/system/b4p_bus_allocations.csv` + author vector source | `figures/reference/Figure4_bus_level_BESS_allocation.png` |
| Table 6 — ±10% planning-limit sensitivity | `matlab/04_rating_sensitivity/run_B4P_rating_sensitivity_v2.m` | `results/reference/04_rating_sensitivity/B4P_rating_sensitivity_compact_MATLAB.csv` |
| Table 7 — residual voltage support | `matlab/02_voltage_pcs/run_B4PQ_replay.m` | `results/reference/02_voltage_pcs/B4PQ_summary.csv` |
| Table 8 — conditional PCS requirement | same B4P-Q replay | `results/reference/02_voltage_pcs/B4PQ_per_bus_PCS.csv` |
| Table 9 — synchronous recharge duration | `matlab/03_recharge/run_recharge_replay_v2.m` | `results/reference/03_recharge/recharge_matrix_MATLAB.csv` |
| External current-limit validation | `matlab/06_external_current_validation/` | `results/reference/06_external_current_validation/*summary.csv` |
