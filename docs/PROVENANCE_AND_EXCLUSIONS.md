# Provenance and exclusions

## Provenance

This repository was curated on 2026-09-20 from the authors' AIMS Energy in-press project archive. The final-revision manuscript title and author list are used only to label the reproducibility package. The canonical numerical material is taken from the later revision replay folders rather than from the earlier May/June draft folders.

The packaged MATLAB lineage includes:

- canonical branch-loading freeze;
- corrected B4P-Q/PCS replay;
- recharge replay v2;
- branch-rating sensitivity replay v2;
- final exhaustive 720-order audit;
- second-revision external current-limit validations.

## Intentionally excluded

The GitHub package does **not** include:

- submitted or highlighted manuscript DOCX/PDF files;
- cover letters and author-response files;
- third-party journal/conference literature PDFs;
- ANSI/IEEE standards PDFs;
- duplicate backup directories;
- superseded replay scripts known not to be canonical;
- unrelated working images and submission templates.

This keeps the public package focused, lightweight, and safer with respect to third-party copyright.

## New packaging-only utilities

The following files were added while curating the repository and are not part of the scientific algorithm:

- `python/validate_reference_results.py`;
- `python/make_figures.py`;
- `matlab/01_branch_loading/run_baseline_assessment_for_repo.m`;
- documentation, checksums, CI workflow, and citation placeholders.

These utilities do not alter the frozen MATLAB reference results.
