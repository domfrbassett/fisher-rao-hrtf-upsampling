from __future__ import annotations

import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SUMMARY = (
    ROOT
    / "results"
    / "barumerli_pge_fisher_final"
    / "full_evaluation_summary.csv"
)
FSP_AE_SUMMARY = (
    ROOT
    / "results"
    / "barumerli_pge_fisher_fsp_ae"
    / "full_evaluation_summary.csv"
)
FSP_AE_LSD_16K = (
    ROOT
    / "results"
    / "barumerli_pge_fisher_fsp_ae"
    / "fsp_ae_lsd_20_16k.csv"
)
METHODS = {
    "SUpDEq_SH",
    "SUpDEq_MCA",
    "SUpDEq_NN_MCA_6dB",
    "SUpDEq_Bary_MCA_6dB",
    "RANF",
    "FSP_AE",
}


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


def beta_continued_fraction(a: float, b: float, x: float) -> float:
    max_iterations = 200
    epsilon = 3.0e-14
    floor = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < floor:
        d = floor
    d = 1.0 / d
    h = d
    for iteration in range(1, max_iterations + 1):
        twice = 2 * iteration
        aa = iteration * (b - iteration) * x / ((qam + twice) * (a + twice))
        d = 1.0 + aa * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + aa / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        h *= d * c
        aa = -(a + iteration) * (qab + iteration) * x / (
            (a + twice) * (qap + twice)
        )
        d = 1.0 + aa * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + aa / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < epsilon:
            return h
    raise RuntimeError("Incomplete-beta continued fraction did not converge")


def regularized_incomplete_beta(a: float, b: float, x: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    log_factor = (
        math.lgamma(a + b)
        - math.lgamma(a)
        - math.lgamma(b)
        + a * math.log(x)
        + b * math.log1p(-x)
    )
    factor = math.exp(log_factor)
    if x < (a + 1.0) / (a + b + 2.0):
        return factor * beta_continued_fraction(a, b, x) / a
    return 1.0 - factor * beta_continued_fraction(b, a, 1.0 - x) / b


def correlation_p_value(r: float, count: int) -> float:
    degrees = count - 2
    x = degrees / (degrees + r * r * degrees / (1.0 - r * r))
    return regularized_incomplete_beta(degrees / 2.0, 0.5, x)


def report(x: list[float], y: list[float], label: str) -> None:
    r = pearson(x, y)
    rho = pearson(average_ranks(x), average_ranks(y))
    print(
        f"{label}: Pearson r={r:.8g}, p={correlation_p_value(r, len(x)):.8g}; "
        f"Spearman rho={rho:.8g}, p={correlation_p_value(rho, len(x)):.8g}"
    )


def main() -> None:
    fsp_lsd: dict[tuple[str, str], str] = {}
    if FSP_AE_LSD_16K.is_file():
        with FSP_AE_LSD_16K.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                key = (row["subjectId"], row["retainedDirections"])
                fsp_lsd[key] = row["LSDdB_20_16k"]

    rows: list[dict[str, str]] = []
    for path in [SUMMARY, FSP_AE_SUMMARY]:
        if not path.is_file():
            continue
        with path.open(newline="", encoding="utf-8-sig") as handle:
            for row in csv.DictReader(handle):
                if row["status"] == "completed" and row["method"] in METHODS:
                    if row["method"] == "FSP_AE":
                        key = (row["subjectId"], row["retainedDirections"])
                        if key in fsp_lsd:
                            row["LSDdB"] = fsp_lsd[key]
                    rows.append(row)

    airm = [float(row["meanAIRM"]) for row in rows]
    lsd = [float(row["LSDdB"]) for row in rows]
    polar = [float(row["relativeLocalPolarRMSErrorDeg"]) for row in rows]
    print(f"Completed principal-set rows: {len(rows)}")
    report(airm, lsd, "AIRM versus LSD")
    report(airm, polar, "AIRM versus relative local polar RMS")


if __name__ == "__main__":
    main()

