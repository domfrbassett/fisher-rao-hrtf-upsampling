from __future__ import annotations

import csv
import math
import random
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRIMARY_SUMMARY = (
    ROOT
    / "results"
    / "barumerli_pge_fisher_final"
    / "full_evaluation_summary.csv"
)
FSP_AE_SUMMARY = (
    ROOT
    / "results"
    / "learning_comparator_extension"
    / "full_evaluation_summary.csv"
)
FSP_AE_LSD_16K = (
    ROOT
    / "results"
    / "learning_comparator_extension"
    / "fsp_ae_lsd_20_16k.csv"
)
AUDIT_CSV = ROOT / "results" / "audits" / "metric_correlations.csv"
TABLE_TEX = ROOT / "tables" / "evaluation" / "metric_correlation_table.tex"
TABLE_TEX_IEEE = ROOT / "tables" / "evaluation" / "metric_correlation_table_ieee.tex"

METHODS = {
    "SUpDEq_SH",
    "SUpDEq_MCA",
    "SUpDEq_NN_MCA_6dB",
    "SUpDEq_Bary_MCA_6dB",
    "RANF",
    "FSP_AE",
}

METRICS = [
    ("LSDdB", "LSD"),
    ("ILDErrorDb", "ILD"),
    ("relativeLateralRMSErrorDeg", "Relative lateral RMS"),
    ("relativeLocalPolarRMSErrorDeg", "Relative local polar RMS"),
    ("relativeQuadrantErrorPercentagePoints", "Relative quadrant error"),
]


def pearson(x: list[float], y: list[float]) -> float:
    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    dx = [value - mean_x for value in x]
    dy = [value - mean_y for value in y]
    numerator = sum(a * b for a, b in zip(dx, dy))
    denominator = math.sqrt(sum(a * a for a in dx) * sum(b * b for b in dy))
    return numerator / denominator


def average_ranks(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=values.__getitem__)
    ranks = [0.0] * len(values)
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and values[order[end]] == values[order[start]]:
            end += 1
        rank = (start + 1 + end) / 2
        for index in order[start:end]:
            ranks[index] = rank
        start = end
    return ranks


def spearman(x: list[float], y: list[float]) -> float:
    return pearson(average_ranks(x), average_ranks(y))


def correlation(rows: list[dict[str, str]], y_key: str, *, rank: bool) -> float:
    x = [float(row["meanAIRM"]) for row in rows]
    y = [float(row[y_key]) for row in rows]
    return spearman(x, y) if rank else pearson(x, y)


def read_rows() -> list[dict[str, str]]:
    fsp_lsd: dict[tuple[str, str], str] = {}
    if FSP_AE_LSD_16K.is_file():
        with FSP_AE_LSD_16K.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                key = (row["subjectId"], row["retainedDirections"])
                fsp_lsd[key] = row["LSDdB_20_16k"]

    rows: list[dict[str, str]] = []
    for path in [PRIMARY_SUMMARY, FSP_AE_SUMMARY]:
        if not path.is_file():
            continue
        with path.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                if row["status"] != "completed" or row["method"] not in METHODS:
                    continue
                if row["method"] == "FSP_AE":
                    key = (row["subjectId"], row["retainedDirections"])
                    if key in fsp_lsd:
                        row["LSDdB"] = fsp_lsd[key]
                try:
                    float(row["meanAIRM"])
                    for metric_key, _label in METRICS:
                        float(row[metric_key])
                except (KeyError, TypeError, ValueError):
                    continue
                rows.append(row)
    return rows


def collapse_method_condition(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in rows:
        key = (row["method"], row["retainedDirections"])
        grouped.setdefault(key, []).append(row)

    collapsed: list[dict[str, str]] = []
    for (method, retention), group in sorted(grouped.items()):
        out = {"method": method, "retainedDirections": retention}
        for key in ["meanAIRM", *[metric_key for metric_key, _label in METRICS]]:
            out[key] = str(sum(float(row[key]) for row in group) / len(group))
        collapsed.append(out)
    return collapsed


def subject_cluster_bootstrap_ci(
    rows: list[dict[str, str]], metric_key: str, *, iterations: int = 1000
) -> tuple[float, float]:
    subjects = sorted({row["subjectId"] for row in rows})
    by_subject = {
        subject: [row for row in rows if row["subjectId"] == subject]
        for subject in subjects
    }
    rng = random.Random(20260704)
    values: list[float] = []
    for _ in range(iterations):
        sample: list[dict[str, str]] = []
        for subject in (rng.choice(subjects) for _ in subjects):
            sample.extend(by_subject[subject])
        values.append(correlation(sample, metric_key, rank=True))
    values.sort()
    lower = values[int(0.025 * iterations)]
    upper = values[int(0.975 * iterations)]
    return lower, upper


def compute_statistics(rows: list[dict[str, str]]) -> list[dict[str, object]]:
    cell_rows = collapse_method_condition(rows)
    statistics: list[dict[str, object]] = []
    for metric_key, label in METRICS:
        lower, upper = subject_cluster_bootstrap_ci(rows, metric_key)
        statistics.append(
            {
                "metricKey": metric_key,
                "label": label,
                "rowPearson": correlation(rows, metric_key, rank=False),
                "rowSpearman": correlation(rows, metric_key, rank=True),
                "methodRetentionPearson": correlation(cell_rows, metric_key, rank=False),
                "methodRetentionSpearman": correlation(cell_rows, metric_key, rank=True),
                "rowSpearmanSubjectBootstrapCiLower": lower,
                "rowSpearmanSubjectBootstrapCiUpper": upper,
                "nRows": len(rows),
                "nSubjects": len({row["subjectId"] for row in rows}),
                "nMethodRetentionCells": len(cell_rows),
            }
        )
    return statistics


def write_tables(statistics: list[dict[str, object]]) -> None:
    lines = [
        "\\begin{table}[ht!]",
        "\\centering",
        "\\caption{Association between mean AIRM and established evaluation metrics. Correlations are reported over the 23 completed method--retention means; the final column gives a 95\\% subject-cluster bootstrap interval for the corresponding row-wise Spearman coefficient, preserving all within-subject repeated measurements.}",
        "\\label{tab:metric_correlations}",
        "\\small",
        "\\begin{tabular}{lrrr}",
        "\\toprule",
        "Metric & Pearson $r$ & Spearman $\\rho$ & Row-wise $\\rho$ 95\\% CI \\\\",
        "\\midrule",
    ]
    for row in statistics:
        lines.append(
            f"{row['label']} & {row['methodRetentionPearson']:.2f} "
            f"& {row['methodRetentionSpearman']:.2f} "
            f"& [{row['rowSpearmanSubjectBootstrapCiLower']:.2f}, "
            f"{row['rowSpearmanSubjectBootstrapCiUpper']:.2f}] \\\\"
        )
    lines.extend(["\\bottomrule", "\\end{tabular}", "\\end{table}", ""])
    TABLE_TEX.write_text("\n".join(lines), encoding="utf-8")

    ieee_lines = [
        "\\begin{table}[!t]",
        "\\centering",
        "\\caption{Association between mean AIRM and established evaluation metrics. Correlations are computed over the 23 completed method--retention means; the final column gives a 95\\% subject-cluster bootstrap interval for the corresponding row-wise Spearman coefficient.}",
        "\\label{tab:metric_correlations}",
        "\\scriptsize",
        "\\setlength{\\tabcolsep}{2.0pt}",
        "\\resizebox{\\columnwidth}{!}{%",
        "\\begin{tabular}{lrrr}",
        "\\toprule",
        "Metric & Pearson $r$ & Spearman $\\rho$ & Row-wise $\\rho$ 95\\% CI \\\\",
        "\\midrule",
    ]
    for row in statistics:
        ieee_lines.append(
            f"{row['label']} & {row['methodRetentionPearson']:.2f} "
            f"& {row['methodRetentionSpearman']:.2f} "
            f"& [{row['rowSpearmanSubjectBootstrapCiLower']:.2f}, "
            f"{row['rowSpearmanSubjectBootstrapCiUpper']:.2f}] \\\\"
        )
    ieee_lines.extend(["\\bottomrule", "\\end{tabular}%", "}", "\\end{table}", ""])
    TABLE_TEX_IEEE.write_text("\n".join(ieee_lines), encoding="utf-8")


def write_audit_csv(statistics: list[dict[str, object]]) -> None:
    AUDIT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with AUDIT_CSV.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = [
            "metric",
            "rowPearson",
            "rowSpearman",
            "methodRetentionPearson",
            "methodRetentionSpearman",
            "rowSpearmanSubjectBootstrapCiLower",
            "rowSpearmanSubjectBootstrapCiUpper",
            "nRows",
            "nSubjects",
            "nMethodRetentionCells",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in statistics:
            writer.writerow(
                {
                    "metric": row["label"],
                    "rowPearson": f"{row['rowPearson']:.8g}",
                    "rowSpearman": f"{row['rowSpearman']:.8g}",
                    "methodRetentionPearson": f"{row['methodRetentionPearson']:.8g}",
                    "methodRetentionSpearman": f"{row['methodRetentionSpearman']:.8g}",
                    "rowSpearmanSubjectBootstrapCiLower": f"{row['rowSpearmanSubjectBootstrapCiLower']:.8g}",
                    "rowSpearmanSubjectBootstrapCiUpper": f"{row['rowSpearmanSubjectBootstrapCiUpper']:.8g}",
                    "nRows": row["nRows"],
                    "nSubjects": row["nSubjects"],
                    "nMethodRetentionCells": row["nMethodRetentionCells"],
                }
            )


def main() -> None:
    rows = read_rows()
    statistics = compute_statistics(rows)
    print(f"Completed principal-set rows: {len(rows)}")
    print(f"Subjects: {len({row['subjectId'] for row in rows})}")
    print(f"Method-retention means: {len(collapse_method_condition(rows))}")
    for row in statistics:
        print(
            f"AIRM versus {row['label']}: "
            f"method-retention Pearson r={row['methodRetentionPearson']:.3f}, "
            f"Spearman rho={row['methodRetentionSpearman']:.3f}; "
            f"row-wise Spearman 95% subject-cluster CI=["
            f"{row['rowSpearmanSubjectBootstrapCiLower']:.3f}, "
            f"{row['rowSpearmanSubjectBootstrapCiUpper']:.3f}]"
        )
    write_audit_csv(statistics)
    write_tables(statistics)
    print(f"Wrote {AUDIT_CSV}")
    print(f"Wrote {TABLE_TEX}")
    print(f"Wrote {TABLE_TEX_IEEE}")


if __name__ == "__main__":
    main()
