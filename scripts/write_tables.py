"""Write the manuscript tables from the evaluation analysis.

Reads results/evaluation/analysis/*.csv (from analyse_results.py)
and writes paper/tables/*_ieee.tex.
"""
from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
ANALYSIS = Path(os.environ.get("FISHERRAO_RESULT_ROOT", ROOT / "results" / "evaluation")) / "analysis"
TABLES = ROOT / "paper" / "tables"
LABELS = {
    "SUpDEq_SH": "SUpDEq-SH", "SUpDEq_MCA": "SUpDEq-MCA",
    "SUpDEq_NN_MCA_6dB": "SUpDEq-Natural-MCA", "SUpDEq_Bary_MCA_6dB": "SUpDEq-Bary-MCA",
    "RANF": "RANF", "FSP_AE": "FSP-AE",
}
SHORT = {"SUpDEq_SH": "SH", "SUpDEq_MCA": "MCA", "SUpDEq_NN_MCA_6dB": "Nat",
         "SUpDEq_Bary_MCA_6dB": "Bary", "RANF": "RANF", "FSP_AE": "FSP"}


METRIC_NAMES = {"Relative lateral RMS": "Lateral RMS", "Relative local polar RMS": "Local polar RMS",
                "Relative quadrant error": "Quadrant error"}


def correlation_table() -> None:
    c = pd.read_csv(ANALYSIS / "correlations.csv")
    lines = [
        r"\begin{table}[!t]", r"\centering",
        r"\caption{Rank association between mean AIRM and the other metrics. "
        r"Across conditions: Spearman correlation of the method--retention means. "
        r"Row-wise: Spearman correlation over all subject--method--retention rows, with 95\% subject-bootstrap intervals. "
        r"Within condition: Kendall's \(\tau\) between the method rankings given by AIRM and by the metric, computed separately "
        r"for each subject and retention level and averaged, with 95\% subject-bootstrap intervals; it excludes agreement "
        r"that arises only because all metrics worsen with sparsity.}",
        r"\label{tab:metric_correlations}", r"\scriptsize", r"\setlength{\tabcolsep}{3pt}",
        r"\begin{tabular}{lrrr}", r"\toprule",
        r"Metric & Across cond. & Row-wise & Within cond. \(\tau\) \\", r"\midrule",
    ]
    for r in c.itertuples():
        lines.append(
            f"{METRIC_NAMES.get(r.metric, r.metric)} & {r.cellSpearman:.2f} & {r.rowSpearman:.2f} {r.rowSpearmanCI} & "
            f"{r.withinTauMean:.2f} {r.withinTauCI} \\\\")
    lines += [r"\bottomrule", r"\end{tabular}", r"\end{table}", ""]
    (TABLES / "metric_correlation_table_ieee.tex").write_text("\n".join(lines), encoding="utf-8")


def threshold_table() -> None:
    t = pd.read_csv(ANALYSIS / "thresholds_summary.csv")
    cols = [("H_az0_el0", r"H\,(0,0)"), ("H_az45_el0", r"H\,(45,0)"), ("H_az90_el0", r"H\,(90,0)"),
            ("V_az0_el0", r"V\,(0,0)"), ("V_az0_el45", r"V\,(0,45)"), ("D60_az0_el0", r"D\,(0,0)")]
    ref = t[t.method == "Measured"].iloc[0]
    rows = [("Measured", "--", ref, None)]
    alt = t[t.method.str.startswith("Measured (sigma")]
    if len(alt):
        rows.append((r"Measured, \(\sigma_{\mathrm{mon}}=2.85\)", "--", alt.iloc[0], None))
    for n in (19, 5):
        for m in LABELS:
            sel = t[(t.method == m) & (t.N == n)]
            if len(sel):
                rows.append((LABELS[m], str(n), sel.iloc[0], ref))
    lines = [
        r"\begin{table}[!t]", r"\centering",
        r"\caption{Cohort-median Fisher-predicted \(d'=1\) thresholds in degrees. Coordinate pairs give "
        r"(azimuth, elevation); H and V are horizontal (azimuthal) and vertical (elevational) displacements, and D is "
        r"the oblique displacement at \(60^\circ\) from horizontal. Err.\ is the mean absolute log ratio to the "
        r"dense reference over the six thresholds, expressed as a percentage change.}",
        r"\label{tab:local_threshold_plausibility}", r"\scriptsize", r"\setlength{\tabcolsep}{2.2pt}",
        r"\resizebox{\columnwidth}{!}{%", r"\begin{tabular}{llrrrrrrr}", r"\toprule",
        "Method & $N$ & " + " & ".join(lbl for _, lbl in cols) + r" & Err. \\", r"\midrule",
    ]
    for name, n, row, reference in rows:
        vals = " & ".join(f"{row[k]:.2f}" for k, _ in cols)
        if reference is None:
            err = "--"
        else:
            lr = np.mean([abs(np.log(row[k] / reference[k])) for k, _ in cols])
            err = f"{100 * (np.exp(lr) - 1):.0f}\\%"
        lines.append(f"{name} & {n} & {vals} & {err} \\\\")
    lines += [r"\bottomrule", r"\end{tabular}%", "}", r"\end{table}", ""]
    (TABLES / "local_threshold_plausibility_table_ieee.tex").write_text("\n".join(lines), encoding="utf-8")


def sensitivity_table() -> None:
    s = pd.read_csv(ANALYSIS / "sensitivity_rankings.csv")
    lines = [
        r"\begin{table}[!t]", r"\centering",
        r"\caption{Method ranking by cohort-mean AIRM (best first) under the primary settings and under changes "
        r"to the SH order of the cue fit and to the spectral noise weight, over the methods applicable at each "
        r"retention level. All settings: the ranking is identical under all four.}",
        r"\label{tab:sensitivity}", r"\scriptsize", r"\setlength{\tabcolsep}{2.5pt}",
        r"\begin{tabular}{rll}", r"\toprule", r"$N$ & Setting & Ranking \\", r"\midrule",
    ]
    names = {"primary (SH 6, sigma_mon 1.25 dB)": "Primary", "SH order 4": "SH order 4",
             "SH order 8": "SH order 8", "sigma_mon 2.85 dB": r"\(\sigma_{\mathrm{mon}}=2.85\)~dB"}

    def short(ranking: str) -> str:
        for k, v in SHORT.items():
            ranking = ranking.replace(k, v)
        return ranking.replace(" < ", r" \(<\) ")

    for n in (100, 19, 5, 3):
        block = s[s.N == n]
        if block.ranking.nunique() == 1:      # identical under every setting: one row
            lines.append(f"{n} & All settings & {short(block.ranking.iloc[0])} \\\\")
        else:
            for i, r in enumerate(block.itertuples()):
                lines.append(f"{n if i == 0 else ''} & {names.get(r.variant, r.variant)} & {short(r.ranking)} \\\\")
        lines.append(r"\addlinespace")
    lines[-1] = r"\bottomrule"
    lines += [r"\end{tabular}", r"\end{table}", ""]
    (TABLES / "sensitivity_ranking_table_ieee.tex").write_text("\n".join(lines), encoding="utf-8")


def signed(v: float) -> str:
    return ("+" if v >= 0 else r"\(-\)") + f"{abs(v):.2f}"


def tensor_component_table() -> None:
    """Full-width table: unsigned component errors and signed scale change per method x N."""
    c = pd.read_csv(ANALYSIS / "cell_summary.csv")
    s = pd.read_csv(ANALYSIS / "signed_scale.csv")
    ns = (100, 19, 5, 3)
    lines = [
        r"\begin{table*}[!t]", r"\centering",
        r"\caption{Cohort-mean Fisher-tensor component errors: \(\mathcal E_{\mathrm{det}}\) (det), "
        r"\(\mathcal E_{\mathrm{anis}}\) (anis), and \(\mathcal E_{\mathrm{orient}}\) (orient., degrees). "
        r"Signed: mean signed log ratio \(\log\det\widehat{\mathbf g}_\eta-\log\det\mathbf g_\eta\) over "
        r"directions and subjects; negative values indicate lost discriminability (ellipse area scales by "
        r"\(e^{-x/2}\)), positive values spurious added cue variation. In parentheses: percentage of directions "
        r"at which the reconstruction carries more information than the reference. N/A: not applicable.}",
        r"\label{tab:tensor_component_means}", r"\scriptsize", r"\setlength{\tabcolsep}{2.4pt}",
        r"\begin{tabular}{l" + "rrrr" * len(ns) + "}", r"\toprule",
        " & " + " & ".join(rf"\multicolumn{{4}}{{c}}{{\(N={n}\)}}" for n in ns) + r" \\",
        " ".join(rf"\cmidrule(lr){{{2 + 4 * i}-{5 + 4 * i}}}" for i in range(len(ns))),
        "Method & " + " & ".join(["det & anis & orient. & signed"] * len(ns)) + r" \\", r"\midrule",
    ]
    for m in LABELS:
        cells = []
        for n in ns:
            r = c[(c.method == m) & (c.N == n)]
            ss = s[(s.method == m) & (s.N == n)]
            if r.empty or not np.isfinite(r.determinant.iloc[0]) or ss.empty:
                cells += [r"\multicolumn{4}{c}{N/A}"]
                continue
            r = r.iloc[0]
            cells += [f"{r.determinant:.2f}", f"{r.anisotropy:.2f}", f"{r.orientationDeg:.0f}",
                      signed(ss.signedLogDet.iloc[0]) + f" ({100 * ss.fracMoreInfo.iloc[0]:.0f}\\%)"]
        lines.append(f"{LABELS[m]} & " + " & ".join(cells) + r" \\")
    lines += [r"\bottomrule", r"\end{tabular}", r"\end{table*}", ""]
    (TABLES / "tensor_component_signed_table_ieee.tex").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    TABLES.mkdir(parents=True, exist_ok=True)
    correlation_table()
    threshold_table()
    sensitivity_table()
    tensor_component_table()
    print("tables written")


if __name__ == "__main__":
    main()
