"""Shared SONICOM sparse-mask protocol utilities.

The split and retained-direction masks follow the public Hu/HRTFformer
SONICOM convention used as the common comparator protocol in the manuscript.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable

import numpy as np


RETENTIONS = (100, 19, 5, 3)

SONICOM_ROW_AZ_DEG = np.arange(-180.0, 180.0, 5.0)
SONICOM_COL_EL_DEG = np.array(
    [-45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0, 60.0, 75.0, 90.0]
)

HU_MASK_GRID = {
    100: [(i, j) for i in [0, 4, 8, 12, 16, 20, 24, 28, 32, 35, 37, 40, 44, 48, 52, 56, 60, 64, 68, 71]
          for j in [1, 3, 4, 6, 8]],
    19: [(row, col) for col, rows in zip(
        [1, 4, 7, 9],
        [[18, 27, 36, 45, 54], [12, 21, 27, 36, 45, 51, 60], [18, 27, 36, 45, 54], [24, 48]],
    ) for row in rows],
    5: [(24, 2), (24, 8), (36, 4), (48, 2), (48, 8)],
    3: [(24, 2), (36, 8), (48, 2)],
}


def hu_mask_az_el(retention: int) -> np.ndarray:
    """Return protocol sparse positions as [azimuth, elevation] degrees."""
    coords = HU_MASK_GRID[int(retention)]
    return np.array([[SONICOM_ROW_AZ_DEG[r], SONICOM_COL_EL_DEG[c]] for r, c in coords], dtype=float)


def hrtfformer_seeded_split(subject_ids: Iterable[int], seed: int = 0, train_ratio: float = 0.8):
    """Replicate the seeded SONICOM split convention used by the protocol."""
    subject_ids = list(subject_ids)
    rng = np.random.RandomState(seed)
    train_size = int(len(set(subject_ids)) * train_ratio)
    train = rng.choice(list(set(subject_ids)), train_size, replace=False)
    test = list(set(subject_ids) - set(train))
    return sorted(int(x) for x in train), sorted(int(x) for x in test)


def parse_subject_id(path: Path) -> int | None:
    match = re.match(r"P(\d{4})_", path.name)
    return int(match.group(1)) if match else None


def discover_subject_ids(sofa_root: Path, pattern: str) -> list[int]:
    ids = []
    for path in sofa_root.rglob(pattern):
        subject_id = parse_subject_id(path)
        if subject_id is not None:
            ids.append(subject_id)
    return sorted(set(ids))


def read_source_positions_deg(sofa_path: Path) -> np.ndarray:
    """Read SOFA SourcePosition without depending on MATLAB."""
    try:
        import netCDF4

        with netCDF4.Dataset(str(sofa_path), "r") as nc:
            return np.asarray(nc.variables["SourcePosition"][:, :2], dtype=float)
    except Exception:
        from scipy.io import netcdf_file

        with netcdf_file(str(sofa_path), "r", mmap=False) as nc:
            return np.asarray(nc.variables["SourcePosition"].data[:, :2], dtype=float).copy()


def wrap_azimuth_deg(az: np.ndarray | float) -> np.ndarray | float:
    return ((np.asarray(az) + 180.0) % 360.0) - 180.0


def nearest_source_indices(source_positions_deg: np.ndarray, mask_az_el_deg: np.ndarray) -> list[int]:
    """Map Hu grid coordinates to nearest measured SONICOM SOFA directions."""
    source = np.asarray(source_positions_deg[:, :2], dtype=float)
    source_az = wrap_azimuth_deg(source[:, 0])
    source_el = source[:, 1]
    indices = []
    for az, el in mask_az_el_deg:
        daz = wrap_azimuth_deg(source_az - az)
        delv = source_el - el
        dist2 = daz ** 2 + delv ** 2
        idx = int(np.argmin(dist2))
        if dist2[idx] > 1e-8:
            raise RuntimeError(
                f"No exact SONICOM source-position match for Hu mask coordinate "
                f"az={az}, el={el}; nearest index {idx} is {source[idx].tolist()}."
            )
        indices.append(idx)
    return indices


def write_protocol_json(
    sofa_root: Path,
    output_path: Path,
    sofa_pattern: str,
    source_positions_deg: np.ndarray | None = None,
) -> dict:
    subject_ids = discover_subject_ids(sofa_root, sofa_pattern)
    if not subject_ids:
        raise RuntimeError(f"No SOFA files matching {sofa_pattern} found below {sofa_root}")

    train_ids, test_ids = hrtfformer_seeded_split(subject_ids)
    first_sofa = next(sofa_root.rglob(sofa_pattern))
    source_positions = (
        np.asarray(source_positions_deg, dtype=float)
        if source_positions_deg is not None
        else read_source_positions_deg(first_sofa)
    )

    protocol = {
        "name": "hu_hrtfformer_seed0_80_20",
        "seed": 0,
        "trainRatio": 0.8,
        "sofaRoot": str(sofa_root),
        "sofaPattern": sofa_pattern,
        "subjectIds": subject_ids,
        "trainSubjectIds": train_ids,
        "testSubjectIds": test_ids,
        "retentions": list(RETENTIONS),
        "huMaskGrid": {str(k): [list(x) for x in v] for k, v in HU_MASK_GRID.items()},
        "huMaskAzElDeg": {str(k): hu_mask_az_el(k).tolist() for k in RETENTIONS},
        "sonicomDirectionIndices": {
            str(k): nearest_source_indices(source_positions, hu_mask_az_el(k)) for k in RETENTIONS
        },
        "notes": [
            "Masks are the hard-coded HRTFformer SONICOM masks confirmed by Hu.",
            "Subject split follows the public HRTFformer np.random.seed(0), train_samples_ratio=0.8 convention.",
            "Direction indices are zero-based SOFA SourcePosition row indices for RANF/Python.",
            "MATLAB should add one to these indices.",
        ],
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(protocol, indent=2), encoding="utf-8")
    return protocol
