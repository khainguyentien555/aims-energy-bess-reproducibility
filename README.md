# Reproducibility package — AIMS Energy

[![Validate reproducibility package](https://github.com/khainguyentien555/aims-energy-bess-reproducibility/actions/workflows/validate.yml/badge.svg)](https://github.com/khainguyentien555/aims-energy-bess-reproducibility/actions/workflows/validate.yml)

**Associated article:**  
**Feeder-constrained co-located BESS sizing for grid-interactive EV fast-charging stations: Branch-loading relief, voltage support, and recharge deliverability**  
Thi-Minh-Chau Le, Tien-Khai Nguyen, and Trong-Nghia Le  
*AIMS Energy*, 2026, **14**(5): 1033–1058. DOI: [10.3934/energy.2026042](https://doi.org/10.3934/energy.2026042)

> **Final citation:** Thi-Minh-Chau Le, Tien-Khai Nguyen, Trong-Nghia Le. “Feeder-constrained co-located BESS sizing for grid-interactive EV fast-charging stations: Branch-loading relief, voltage support, and recharge deliverability.” *AIMS Energy*, 2026, **14**(5): 1033–1058. DOI: [10.3934/energy.2026042](https://doi.org/10.3934/energy.2026042).

## What this repository reproduces

This package is curated from the final revision lineage and is designed to reproduce or independently verify the numerical evidence behind the paper's five feeder-side BESS adequacy requirements:

1. branch-loading-relief active power;
2. residual voltage support after active-power allocation;
3. conditional PCS apparent-power requirement;
4. storage-energy requirement for the prescribed stress duration; and
5. synchronous post-stress recharge deliverability.

It also contains the two reviewer-facing robustness audits used in the final revision: exhaustive **720 processing-order** enumeration and independent **published branch-current-limit** validation.

## Repository layout

```text
.
├── data/                       # system/scenario inputs and paper-facing data
├── matlab/                     # canonical MATLAB replay workflows
├── python/                     # validation and figure-regeneration helpers
├── results/reference/          # frozen canonical outputs used for verification
├── figures/                    # final author figures + editable sources where available
├── docs/                       # provenance, data dictionary, paper-to-code map
├── checksums/                  # SHA-256 manifest for canonical material
├── .github/workflows/          # lightweight GitHub Actions validation
├── CITATION.cff
└── citation.bib
```

## Fast verification without MATLAB

The Python layer does **not** replace the MATLAB simulations. It verifies the frozen reference artifacts and regenerates the data-driven figures from those artifacts.

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
python python/validate_reference_results.py
python python/make_figures.py
```

A successful reference check ends with:

```text
REFERENCE VALIDATION: PASS
```

## Full MATLAB reproduction

The canonical numerical lineage was executed in **MATLAB R2023b** on 64-bit Windows. The branch-loading optimization and current-limit validation require **Optimization Toolbox** (`fmincon`). No Octave equivalence is claimed.

Run the workflows in the order documented in [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md). The most important rule is: **do not edit outputs to force agreement with the frozen values**. If a replay differs materially, preserve the generated artifacts and diagnose the environment, solver, model-data, or stopping-rule difference.

## Reproducibility boundary

The repository reproduces the computational results and numerical checks. It does **not** redistribute the submitted manuscript, publisher files, third-party literature PDFs, standards, or duplicated revision backups. See [`docs/PROVENANCE_AND_EXCLUSIONS.md`](docs/PROVENANCE_AND_EXCLUSIONS.md).

## Citation

Please cite the associated article as: **Thi-Minh-Chau Le, Tien-Khai Nguyen, Trong-Nghia Le.** “Feeder-constrained co-located BESS sizing for grid-interactive EV fast-charging stations: Branch-loading relief, voltage support, and recharge deliverability.” *AIMS Energy*, 2026, **14**(5): 1033–1058. DOI: **[10.3934/energy.2026042](https://doi.org/10.3934/energy.2026042)**. Machine-readable metadata are provided in `CITATION.cff` and `citation.bib`.

## License status

No general open-source or open-data reuse license is granted by this package unless explicitly stated for an individual file or directory. See [`LICENSE_NOTICE.md`](LICENSE_NOTICE.md).
