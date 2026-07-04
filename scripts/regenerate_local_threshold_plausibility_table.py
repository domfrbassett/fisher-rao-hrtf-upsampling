from __future__ import annotations

import csv
import math
from pathlib import Path

import h5py
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
EVAL_ROOT = ROOT / "results" / "barumerli_pge_fisher_final" / "metric_tensors"
FSP_ROOT = ROOT / "results" / "barumerli_pge_fisher_fsp_ae" / "metric_tensors"

SUMMARY_CSV = ROOT / "results" / "audits" / "local_threshold_plausibility_summary.csv"
DETAIL_CSV = ROOT / "results" / "audits" / "local_threshold_plausibility_subject_detail.csv"
TABLE_TEX = ROOT / "tables" / "evaluation" / "local_threshold_plausibility_table.tex"
TABLE_TEX_IEEE = ROOT / "tables" / "evaluation" / "local_threshold_plausibility_table_ieee.tex"


METHODS = [
    ("Measured", "dense", EVAL_ROOT, "reference_metric_tensor.mat"),
    ("SUpDEq-MCA", "19", EVAL_ROOT, "SUpDEq_MCA_N019_metric_tensor.mat"),
    ("SUpDEq-MCA", "5", EVAL_ROOT, "SUpDEq_MCA_N005_metric_tensor.mat"),
    ("SUpDEq-Bary-MCA", "19", EVAL_ROOT, "SUpDEq_Bary_MCA_6dB_N019_metric_tensor.mat"),
    ("SUpDEq-Bary-MCA", "5", EVAL_ROOT, "SUpDEq_Bary_MCA_6dB_N005_metric_tensor.mat"),
    ("RANF", "19", EVAL_ROOT, "RANF_N019_metric_tensor.mat"),
    ("RANF", "5", EVAL_ROOT, "RANF_N005_metric_tensor.mat"),
    ("FSP-AE", "19", FSP_ROOT, "FSP_AE_N019_metric_tensor.mat"),
    ("FSP-AE", "5", FSP_ROOT, "FSP_AE_N005_metric_tensor.mat"),
]


PROJECTIONS = [
    ("LatAz0El0", "lateral", 0.0, 0.0),
    ("LatAz45El0", "lateral", 45.0, 0.0),
    ("LatAz90El0", "lateral", 90.0, 0.0),
    ("VertAz0El0", "vertical", 0.0, 0.0),
    ("VertAz0El45", "vertical", 0.0, 45.0),
]


def sph_to_cart(az_deg: float, el_deg: float) -> np.ndarray:
    az = math.radians(az_deg)
    el = math.radians(el_deg)
    return np.array(
        [math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)],
        dtype=float,
    )


def local_tangent_basis(r: np.ndarray) -> np.ndarray:
    if abs(r[2]) > 0.9:
        auxiliary = np.array([0.0, 1.0, 0.0])
    else:
        auxiliary = np.array([0.0, 0.0, 1.0])
    u1 = np.cross(auxiliary, r)
    u1 = u1 / np.linalg.norm(u1)
    u2 = np.cross(r, u1)
    u2 = u2 / np.linalg.norm(u2)
    return np.column_stack([u1, u2])


def projection_direction(kind: str, r: np.ndarray) -> np.ndarray:
    z = np.array([0.0, 0.0, 1.0])
    if kind == "lateral":
        u = np.cross(z, r)
    elif kind == "vertical":
        u = z - float(np.dot(z, r)) * r
    else:
        raise ValueError(kind)
    n = np.linalg.norm(u)
    if n < 1e-12:
        raise ValueError(f"Projection direction undefined for {kind} at {r}")
    return u / n


def read_tensor_file(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    with h5py.File(path, "r") as handle:
        metric = np.array(handle["metricTensor"], dtype=float)
        cart = np.array(handle["coordinatesCartesian"], dtype=float).T
        azel = np.array(handle["coordinatesAzimuthElevationDeg"], dtype=float).T
    if metric.shape[0] != cart.shape[0]:
        # MATLAB v7.3/HDF5 can expose arrays transposed depending on creation.
        metric = np.moveaxis(metric, -1, 0)
    return metric, cart, azel


def nearest_grid_index(cart: np.ndarray, target: np.ndarray) -> tuple[int, float]:
    dots = np.clip(cart @ target, -1.0, 1.0)
    idx = int(np.argmax(dots))
    err = math.degrees(math.acos(float(dots[idx])))
    return idx, err


def projected_threshold_deg(metric: np.ndarray, r_grid: np.ndarray, kind: str) -> float:
    v = local_tangent_basis(r_grid)
    u = projection_direction(kind, r_grid)
    c = v.T @ u
    fisher = float(c.T @ metric @ c)
    if not math.isfinite(fisher) or fisher <= 0:
        return math.nan
    return math.degrees(1.0 / math.sqrt(fisher))


def subject_dirs(root: Path, filename: str) -> list[Path]:
    return sorted(
        path for path in root.glob("subject_*") if (path / filename).is_file()
    )


def median(values: list[float]) -> float:
    arr = np.array(values, dtype=float)
    return float(np.nanmedian(arr))


def write_table(path: Path, star: bool) -> None:
    env = "table*" if star else "table"
    tabcolsep = "3.2pt" if star else "5pt"
    caption = (
        "Population-median Fisher-predicted local $d'=1$ angular thresholds "
        "(degrees). Coordinate pairs are $(\\mathrm{azimuth},\\mathrm{elevation})$ "
        "in degrees. Lateral columns use horizontal-plane azimuthal displacements; "
        "vertical columns use elevational displacements in the frontal plane. "
        "The error column is the mean absolute deviation from the dense-reference "
        "row across the five projected thresholds."
    )
    rows = list(csv.DictReader(SUMMARY_CSV.open(newline="", encoding="utf-8")))
    lines = [
        f"\\begin{{{env}}}[{'t' if star else 'ht!'}]",
        "\\centering",
        f"\\caption{{{caption}}}",
        "\\label{tab:local_threshold_plausibility}",
        "\\scriptsize",
        f"\\setlength{{\\tabcolsep}}{{{tabcolsep}}}",
        "\\begin{tabular}{llrrrrrr}",
        "\\toprule",
        (
            "Method & $N$ & Lat. $(0,0)$ & Lat. $(45,0)$ & Lat. $(90,0)$ "
            "& Vert. $(0,0)$ & Vert. $(0,45)$ & Mean abs. err. \\\\"
        ),
        "\\midrule",
    ]
    for row in rows:
        n_value = "--" if row["retainedDirections"] == "dense" else row["retainedDirections"]
        lines.append(
            f"{row['method']} & {n_value} & "
            f"{float(row['LatAz0El0']):.2f} & "
            f"{float(row['LatAz45El0']):.2f} & "
            f"{float(row['LatAz90El0']):.2f} & "
            f"{float(row['VertAz0El0']):.2f} & "
            f"{float(row['VertAz0El45']):.2f} & "
            f"{float(row['meanAbsErrorDeg']):.2f} \\\\"
        )
    lines.extend(["\\bottomrule", "\\end{tabular}", f"\\end{{{env}}}"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    detail_rows: list[dict[str, object]] = []
    summary_rows: list[dict[str, object]] = []

    projection_indices: dict[tuple[Path, str], dict[str, tuple[int, float, tuple[float, float]]]] = {}

    for method, retention, root, filename in METHODS:
        dirs = subject_dirs(root, filename)
        if not dirs:
            raise FileNotFoundError(f"No subjects found for {filename} under {root}")

        per_projection: dict[str, list[float]] = {name: [] for name, *_ in PROJECTIONS}

        for subject_dir in dirs:
            subject = subject_dir.name.replace("subject_", "")
            metric, cart, azel = read_tensor_file(subject_dir / filename)

            row: dict[str, object] = {
                "subject": subject,
                "method": method,
                "retainedDirections": retention,
            }

            for name, kind, az, el in PROJECTIONS:
                target = sph_to_cart(az, el)
                idx, angular_error = nearest_grid_index(cart, target)
                r_grid = cart[idx]
                value = projected_threshold_deg(metric[idx], r_grid, kind)
                row[name] = value
                row[f"{name}_nearestAzDeg"] = float(azel[idx, 0])
                row[f"{name}_nearestElDeg"] = float(azel[idx, 1])
                row[f"{name}_nearestAngularErrorDeg"] = angular_error
                per_projection[name].append(value)

            detail_rows.append(row)

        summary: dict[str, object] = {
            "method": method,
            "retainedDirections": retention,
            "nSubjects": len(dirs),
        }
        for name, *_ in PROJECTIONS:
            summary[name] = median(per_projection[name])
        summary_rows.append(summary)

    dense = summary_rows[0]
    for row in summary_rows:
        errors = [
            abs(float(row[name]) - float(dense[name]))
            for name, *_ in PROJECTIONS
        ]
        row["meanAbsErrorDeg"] = float(np.nanmean(errors))

    SUMMARY_CSV.parent.mkdir(parents=True, exist_ok=True)
    with SUMMARY_CSV.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = [
            "method",
            "retainedDirections",
            "nSubjects",
            *[name for name, *_ in PROJECTIONS],
            "meanAbsErrorDeg",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)

    with DETAIL_CSV.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = list(detail_rows[0].keys())
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(detail_rows)

    write_table(TABLE_TEX, star=False)
    write_table(TABLE_TEX_IEEE, star=True)

    for row in summary_rows:
        print(
            row["method"],
            row["retainedDirections"],
            " ".join(f"{name}={float(row[name]):.3f}" for name, *_ in PROJECTIONS),
            f"err={float(row['meanAbsErrorDeg']):.3f}",
        )


if __name__ == "__main__":
    main()

