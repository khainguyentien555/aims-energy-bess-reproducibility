\
from pathlib import Path
import hashlib
import sys
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / "results" / "reference"


def fail(msg):
    raise AssertionError(msg)


def close(actual, expected, atol=1e-6, label="value"):
    if not np.isclose(actual, expected, atol=atol, rtol=0):
        fail(f"{label}: got {actual}, expected {expected} ± {atol}")


def verify_hash_manifest():
    manifest = ROOT / "checksums" / "REFERENCE_SHA256SUMS.txt"
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, rel = line.split("  ", 1)
        p = ROOT / rel
        if not p.exists():
            fail(f"Missing checksummed file: {rel}")
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != digest:
            fail(f"SHA-256 mismatch: {rel}")


def main():
    verify_hash_manifest()

    b4p = pd.read_csv(R/"01_branch_loading"/"B4P_FULL_freeze_summary.csv").set_index("Case")
    expected = {
        "P1/D1":0.0, "P1/D2":0.0, "P1/D3":248.534779, "P1/D4":510.087115,
        "P2/D1":0.0, "P2/D2":205.343322, "P2/D3":525.473397, "P2/D4":855.558619,
    }
    for case, val in expected.items():
        close(float(b4p.loc[case,"P_BESS_total_kW"]), val, 5e-6, f"B4P {case}")
    for case in ["P1/D3","P1/D4","P2/D2","P2/D3","P2/D4"]:
        close(float(b4p.loc[case,"Lmax_pct"]),100.0,1e-6,f"thermal boundary {case}")

    pq = pd.read_csv(R/"02_voltage_pcs"/"B4PQ_summary.csv")
    if pq["PF_sufficient"].astype(int).sum() != 0:
        fail("Unity-PF correction must be insufficient in all eight nominal cases")
    close(float(pq["Q_add_total_kVAr"].min()),114.770667,5e-6,"minimum Q_add")
    close(float(pq["Q_add_total_kVAr"].max()),879.938422,5e-6,"maximum Q_add")
    if not np.allclose(pq["Vmin_post_pu"],0.95,atol=2e-8,rtol=0):
        fail("Post-support voltage target mismatch")

    order = pd.read_csv(R/"05_order_audit"/"Table5a_order_sensitivity_FINAL.csv")
    close(float(order["Best_excess_pct"].min()),0.071679,5e-7,"minimum sequential excess")
    close(float(order["Worst_excess_pct"].max()),96.685956,5e-7,"maximum sequential excess")
    if len(order) != 5:
        fail("Order audit summary must contain five nonzero-storage nominal cases")

    sens = pd.read_csv(R/"04_rating_sensitivity"/"B4P_rating_sensitivity_compact_MATLAB.csv").set_index("Cases")
    close(float(sens.loc["P2/D4","P090"]),1343.352980,5e-6,"P2/D4 beta=0.90")
    close(float(sens.loc["P2/D4","P100"]),855.558619,5e-6,"P2/D4 beta=1.00")
    close(float(sens.loc["P2/D4","P110"]),506.693279,5e-6,"P2/D4 beta=1.10")
    for _, row in sens.iterrows():
        if not (row.P090 + 5e-5 >= row.P100 >= row.P110 - 5e-5):
            fail("Rating-sensitivity monotonicity failed")

    rec = pd.read_csv(R/"03_recharge"/"recharge_matrix_MATLAB.csv")
    rec4 = rec[rec["T_peak_h"] == 4]
    close(float(rec4["T_floor_h"].iloc[0]),4.432133,5e-6,"4-h recharge floor")
    close(float(rec4["T_rec_star_h"].max()),31.192192,5e-6,"maximum 4-h recharge duration")
    if (rec4["T_rec_star_h"] + 1e-9 < rec4["T_floor_h"]).any():
        fail("Recharge duration below analytical floor")
    if (rec4["Lmax_pct"] > 100 + 1e-6).any():
        fail("Branch loading binds/violates in reference recharge states")

    tercan = pd.read_csv(R/"06_external_current_validation"/"tercan_current_validation_summary.csv").set_index("Case")
    positive = tercan["Minimum_BESS_kW_if_feasible"].fillna(0) > 1e-6
    if set(tercan.index[positive]) != {"P1/D4","P2/D4"}:
        fail("275/120-A validation must require nonzero active BESS only for P1/D4 and P2/D4")
    close(float(tercan.loc["P1/D4","Minimum_BESS_kW_if_feasible"]),20.245228,5e-6,"Tercan P1/D4")
    close(float(tercan.loc["P2/D4","Minimum_BESS_kW_if_feasible"]),158.529837,5e-6,"Tercan P2/D4")

    multi = pd.read_csv(R/"06_external_current_validation"/"external_current_validation_summary.csv")
    if multi["Current_feasible"].astype(int).sum() != 0:
        fail("Multi-tier published current-limit set should admit no active-only current-feasible case")

    print("REFERENCE VALIDATION: PASS")
    print("- branch-loading canonical freeze: PASS")
    print("- residual voltage / Q support / PCS lineage: PASS")
    print("- 720-order audit extrema: PASS")
    print("- rating sensitivity: PASS")
    print("- recharge floor and maximum: PASS")
    print("- independent current-limit validation: PASS")
    print("- canonical SHA-256 manifest: PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"REFERENCE VALIDATION: FAIL\n{exc}", file=sys.stderr)
        raise
