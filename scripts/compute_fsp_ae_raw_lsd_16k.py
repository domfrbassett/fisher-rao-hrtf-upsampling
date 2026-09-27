from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute FSP-AE raw SOFA HRIR-domain LSD over 20 Hz--16 kHz."
    )
    parser.add_argument("--deps", type=Path, help="Optional directory containing h5py/numpy.")
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--target-root",
        type=Path,
        default=Path("ml_comparator_research/comparator_protocol/work/ml_lap_aligned/target"),
    )
    parser.add_argument(
        "--fsp-root",
        type=Path,
        default=Path("raw/ml_lap_aligned_raw_ml/ml_lap_aligned_raw_ml/FSP_AE"),
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("results/barumerli_pge_fisher_hu_raw_ml_final/fsp_ae_lsd_20_16k.csv"),
    )
    return parser.parse_args()


def import_hdf5(deps: Path | None):
    if deps is not None:
        sys.path.insert(0, str(deps.resolve()))
    import h5py
    import numpy as np

    return h5py, np


def read_hrir_sofa(path: Path, h5py, np) -> tuple[object, float]:
    with h5py.File(path, "r") as handle:
        hrir = np.asarray(handle["Data.IR"], dtype=np.float64)
        fs = float(np.asarray(handle["Data.SamplingRate"]).reshape(-1)[0])
        if "Data.Delay" in handle:
            delay = np.asarray(handle["Data.Delay"], dtype=np.float64)
            if delay.shape[:2] == hrir.shape[:2] and np.any(np.abs(delay) > np.finfo(float).eps):
                hrir = apply_delay(hrir, delay, fs, np)
        return hrir, fs


def apply_delay(hrir, delay, fs: float, np):
    shifted = np.zeros_like(hrir)
    delay_samples = np.rint(delay * fs).astype(int)
    n_samples = hrir.shape[2]
    for i_direction in range(hrir.shape[0]):
        for i_ear in range(hrir.shape[1]):
            shift = int(delay_samples[i_direction, i_ear])
            signal = hrir[i_direction, i_ear, :]
            if shift > 0:
                shifted[i_direction, i_ear, shift:] = signal[: n_samples - shift]
            elif shift < 0:
                shift = abs(shift)
                shifted[i_direction, i_ear, : n_samples - shift] = signal[shift:]
            else:
                shifted[i_direction, i_ear, :] = signal
    return shifted


def lsd_20_16k(target_hrir, recon_hrir, fs: float, np, eps_mag: float = 1e-8) -> float:
    if target_hrir.shape[:2] != recon_hrir.shape[:2]:
        raise ValueError(f"Direction/ear grid mismatch: {target_hrir.shape} vs {recon_hrir.shape}")
    n_samples = max(target_hrir.shape[2], recon_hrir.shape[2])
    n_positive = n_samples // 2
    freqs = np.arange(n_positive, dtype=np.float64) * fs / n_samples
    freq_idx = (freqs >= 20.0) & (freqs <= 16000.0)
    if not np.any(freq_idx):
        raise ValueError("No FFT bins fall inside 20 Hz--16 kHz.")

    target_spec = np.fft.fft(target_hrir, n=n_samples, axis=2)
    recon_spec = np.fft.fft(recon_hrir, n=n_samples, axis=2)
    target_mag = np.abs(target_spec[:, :, :n_positive])[:, :, freq_idx]
    recon_mag = np.abs(recon_spec[:, :, :n_positive])[:, :, freq_idx]
    values = np.sqrt(
        np.mean((20.0 * np.log10(np.maximum(target_mag, eps_mag) / np.maximum(recon_mag, eps_mag))) ** 2, axis=2)
    )
    return float(np.mean(values))


def main() -> int:
    args = parse_args()
    h5py, np = import_hdf5(args.deps)

    project_root = args.project_root.resolve()
    target_root = (project_root / args.target_root).resolve()
    fsp_root = (project_root / args.fsp_root).resolve()
    out_path = (project_root / args.out).resolve()
    retentions = [100, 19, 5, 3]

    rows: list[dict[str, object]] = []
    for retention in retentions:
        target_dir = target_root / f"N{retention:03d}"
        fsp_dir = fsp_root / f"N{retention:03d}"
        if not target_dir.is_dir():
            raise FileNotFoundError(target_dir)
        if not fsp_dir.is_dir():
            raise FileNotFoundError(fsp_dir)
        for fsp_sofa in sorted(fsp_dir.glob("Sonicom_*.sofa")):
            subject_id = int(fsp_sofa.stem.replace("Sonicom_", ""))
            target_sofa = target_dir / f"Sonicom_{subject_id}.sofa"
            if not target_sofa.is_file():
                raise FileNotFoundError(target_sofa)
            target_hrir, target_fs = read_hrir_sofa(target_sofa, h5py, np)
            recon_hrir, recon_fs = read_hrir_sofa(fsp_sofa, h5py, np)
            if abs(target_fs - recon_fs) > 1e-9:
                raise ValueError(f"Sampling rate mismatch for subject {subject_id}: {target_fs} vs {recon_fs}")
            rows.append(
                {
                    "subjectId": subject_id,
                    "retainedDirections": retention,
                    "LSDdB_20_16k": lsd_20_16k(target_hrir, recon_hrir, target_fs, np),
                }
            )

    if len(rows) != 164:
        raise RuntimeError(f"Expected 164 FSP-AE LSD rows, found {len(rows)}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["subjectId", "retainedDirections", "LSDdB_20_16k"])
        writer.writeheader()
        writer.writerows(rows)

    by_retention: dict[int, list[float]] = {}
    for row in rows:
        by_retention.setdefault(int(row["retainedDirections"]), []).append(float(row["LSDdB_20_16k"]))
    print(f"Wrote {out_path}")
    for retention in retentions:
        values = by_retention[retention]
        print(f"N{retention:03d}: mean={np.mean(values):.6f}, median={np.median(values):.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
