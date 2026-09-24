# Data dictionary

## `data/system/`

- `Supplementary_Table_S1_branch_dataset.csv`: 32-branch IEEE 33-bus topology, resistance/reactance data, and adopted apparent-power planning limits used by the nominal study.
- `baseline_voltage_profile.csv`: no-EVCS / no-BESS base voltage profile.
- `baseline_voltage_profiles_no_BESS.csv`: eight placement-demand voltage profiles before BESS.
- `baseline_branch_loading_no_BESS.csv`: eight placement-demand branch-loading profiles before BESS.
- `baseline_metrics_no_BESS.csv`: case-level voltage, loading, hosting-capacity margin, and loss outputs from the original production-lineage framework.
- `b4p_bus_allocations.csv`: machine-readable form of the frozen per-bus nominal branch-loading-relief allocation.

## `data/scenarios/`

- `evcs_scenarios.csv`: fixed EVCS placements P1/P2, demand multipliers D1–D4, per-station nominal active power, and EVCS power factor.

## `data/current_limits/`

- `sosnowski_smartgridcomm2024_current_limits.csv`: external multi-tier branch-current limits used only in the independent validation.
- `tercan_2022_current_limits.csv`: 275/120-A branch-current limits used only in the independent validation.
- equivalent-MVA CSVs are diagnostics only; the external current validations enforce limits directly in amperes.

## `results/reference/`

These are frozen outputs, not inputs to be tuned. They provide the expected numerical record for independent replay comparison and are protected by SHA-256 checksums.
