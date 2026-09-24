\
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "system"
REF = ROOT / "results" / "reference"
OUT = ROOT / "figures" / "generated"
OUT.mkdir(parents=True, exist_ok=True)


def figure2():
    base = pd.read_csv(DATA/"baseline_voltage_profile.csv")
    v = pd.read_csv(DATA/"baseline_voltage_profiles_no_BESS.csv")
    fig, axes = plt.subplots(1, 2, figsize=(11.2, 4.3), sharey=True, constrained_layout=True)
    for ax, prefix, label in zip(axes,["P1","P2"],["P1","P2"]):
        ax.plot(base["Bus"],base["Voltage_pu"],linestyle="--",label="Base (no EVCS)")
        for d in ["D1","D2","D3","D4"]:
            ax.plot(v["Bus"],v[f"{prefix}_{d}"],marker="o",markevery=4,label=d)
        ax.axhline(0.95,linestyle=":",label="0.95 p.u. limit")
        ax.set_xlabel("Bus number")
        ax.set_title(label)
        ax.grid(True,alpha=0.3)
    axes[0].set_ylabel("Voltage magnitude (p.u.)")
    axes[0].legend(ncol=2,fontsize=8)
    for ext in ["png","pdf","svg"]:
        fig.savefig(OUT/f"Figure2_baseline_voltage_profiles.{ext}",dpi=300,bbox_inches="tight")
    plt.close(fig)


def figure3():
    b4p = pd.read_csv(REF/"01_branch_loading"/"B4P_FULL_freeze_summary.csv").set_index("Case")
    ds = ["D1","D2","D3","D4"]
    lam = np.array([0.6,1.0,1.3,1.6])
    p_total = 6*0.15*lam*1000
    p1 = np.array([b4p.loc[f"P1/{d}","P_BESS_total_kW"] for d in ds])
    p2 = np.array([b4p.loc[f"P2/{d}","P_BESS_total_kW"] for d in ds])
    x=np.arange(4); w=0.34
    fig,ax=plt.subplots(figsize=(6.5,3.8),constrained_layout=True)
    ax.bar(x-w/2,p_total-p1,w,label="P1 feeder-supplied")
    ax.bar(x-w/2,p1,w,bottom=p_total-p1,label="P1 BESS-supplied")
    ax.bar(x+w/2,p_total-p2,w,label="P2 feeder-supplied")
    ax.bar(x+w/2,p2,w,bottom=p_total-p2,label="P2 BESS-supplied")
    ax.set_xticks(x,ds); ax.set_ylabel("EVCS active power (kW)")
    ax.grid(axis="y",alpha=0.3); ax.legend(fontsize=7,ncol=2)
    for ext in ["png","pdf","svg"]:
        fig.savefig(OUT/f"Figure3_grid_BESS_decomposition.{ext}",dpi=300,bbox_inches="tight")
    plt.close(fig)


def main():
    figure2(); figure3()
    print(f"Generated data-driven figures in: {OUT}")

if __name__ == "__main__":
    main()
