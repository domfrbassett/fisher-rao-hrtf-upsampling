from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SUMMARY_CSV = ROOT / "results" / "audits" / "local_threshold_plausibility_summary.csv"
TABLE_TEX = ROOT / "tables" / "evaluation" / "local_threshold_plausibility_table.tex"
TABLE_TEX_IEEE = ROOT / "tables" / "evaluation" / "local_threshold_plausibility_table_ieee.tex"

COLUMNS = [
    ("LatAz0El0", "Lat. $(0,0)$"),
    ("LatAz45El0", "Lat. $(45,0)$"),
    ("LatAz90El0", "Lat. $(90,0)$"),
    ("VertAz0El0", "Vert. $(0,0)$"),
    ("VertAz0El45", "Vert. $(0,45)$"),
]

CAPTION = (
    "Population-median Fisher-predicted local $d'=1$ angular thresholds "
    "(degrees). Coordinate pairs are $(\\mathrm{azimuth},\\mathrm{elevation})$ "
    "in degrees. Lateral columns use horizontal-plane azimuthal displacements; "
    "vertical columns use elevational displacements in the frontal plane. "
    "The error column is the mean absolute deviation from the dense-reference "
    "row across the five projected thresholds."
)


def read_rows() -> list[dict[str, str]]:
    if not SUMMARY_CSV.is_file():
        raise FileNotFoundError(f"Missing summary CSV: {SUMMARY_CSV}")
    with SUMMARY_CSV.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_table(path: Path, rows: list[dict[str, str]], *, star: bool) -> None:
    env = "table*" if star else "table"
    placement = "t" if star else "ht!"
    tabcolsep = "3.2pt" if star else "5pt"
    header = "Method & $N$ & " + " & ".join(label for _key, label in COLUMNS)
    header += " & Mean abs. err. \\\\"

    lines = [
        f"\\begin{{{env}}}[{placement}]",
        "\\centering",
        f"\\caption{{{CAPTION}}}",
        "\\label{tab:local_threshold_plausibility}",
        "\\scriptsize",
        f"\\setlength{{\\tabcolsep}}{{{tabcolsep}}}",
        "\\begin{tabular}{llrrrrrr}",
        "\\toprule",
        header,
        "\\midrule",
    ]
    for row in rows:
        n_value = "--" if row["retainedDirections"] == "dense" else row["retainedDirections"]
        values = " & ".join(f"{float(row[key]):.2f}" for key, _label in COLUMNS)
        lines.append(
            f"{row['method']} & {n_value} & {values} & "
            f"{float(row['meanAbsErrorDeg']):.2f} \\\\"
        )
    lines.extend(["\\bottomrule", "\\end{tabular}", f"\\end{{{env}}}"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    rows = read_rows()
    write_table(TABLE_TEX, rows, star=False)
    write_table(TABLE_TEX_IEEE, rows, star=True)
    print(f"Wrote {TABLE_TEX}")
    print(f"Wrote {TABLE_TEX_IEEE}")


if __name__ == "__main__":
    main()
