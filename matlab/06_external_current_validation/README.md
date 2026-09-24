# 06 — Independent published current-limit validation

Run both scripts independently:

```matlab
cd('matlab/06_external_current_validation')
run_external_current_validation          % SmartGridComm 2024 multi-tier limits
run_external_current_validation_Tercan   % Tercan et al. 2022, 275/120-A limits
```

Only the published branch-current limits are imported from the external studies. Their other system assumptions are **not** reproduced. Current limits are enforced directly in amperes; voltage is deliberately excluded from the active-power sizing feasibility test. If active-only current feasibility is impossible, the scripts report the minimax current-ratio diagnostic instead of forcing a finite BESS size.
