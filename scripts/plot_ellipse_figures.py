"""Render the CRB and Barumerli response-covariance ellipse figures.

Both figures use the same directions, tangent basis, projection and
occlusion handling, so they differ only in the covariance being drawn.

Inputs
  results/evaluation/analysis/median_reference_tensors.npz
  results/audits/barumerli_response_covariance_16k.mat
  matlab/postprocessing/plotted_directions.csv
Outputs
  paper/figures/median_crb_ellipses.png
  paper/figures/median_barumerli_map_response_covariance.png
  paper/figures/ellipse_comparison.png (front and left views of both, used in the paper)
"""
from __future__ import annotations

import math
from io import BytesIO
from pathlib import Path

import h5py
import matplotlib
import numpy as np
from PIL import Image, ImageChops

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
TENSOR_NPZ = ROOT / "results" / "evaluation" / "analysis" / "median_reference_tensors.npz"
BARUMERLI_MAT = ROOT / "results" / "audits" / "barumerli_response_covariance_16k.mat"
PLOTTED_CSV = ROOT / "matlab" / "postprocessing" / "plotted_directions.csv"
OUT = ROOT / "paper" / "figures"
CHI2_2_95 = 5.991464547107979
COLOUR = (0.12, 0.37, 0.72)


def local_tangent_basis(r: np.ndarray) -> np.ndarray:
    aux = np.array([0.0, 1.0, 0.0]) if abs(r[2]) > 0.9 else np.array([0.0, 0.0, 1.0])
    u1 = np.cross(aux, r)
    u1 /= np.linalg.norm(u1)
    u2 = np.cross(r, u1)
    u2 /= np.linalg.norm(u2)
    return np.column_stack([u1, u2])


def azel_to_cart(az: float, el: float) -> np.ndarray:
    a, e = math.radians(az), math.radians(el)
    return np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])


def ellipse_curve(r: np.ndarray, cov_rad2: np.ndarray, scale: float, n: int = 150) -> np.ndarray:
    w, v = np.linalg.eigh(0.5 * (cov_rad2 + cov_rad2.T))
    if np.any(w <= 0):
        raise ValueError("covariance is not positive definite")
    t = np.linspace(0.0, 2.0 * math.pi, n)
    offsets = local_tangent_basis(r) @ (v @ (np.sqrt(w)[:, None] * np.vstack([np.cos(t), np.sin(t)]))) * scale
    d = np.linalg.norm(offsets, axis=0)
    pts = np.cos(d)[:, None] * r[None, :] + (np.sin(d) / np.maximum(d, 1e-12))[:, None] * offsets.T
    return pts / np.linalg.norm(pts, axis=1, keepdims=True)


def render_view(positions, covs, scale, view_az, dpi=600) -> Image.Image:
    radius = 10.0
    camera = azel_to_cart(view_az, 0.0)
    fig = plt.figure(figsize=(4.0, 4.0), facecolor="white")
    ax = fig.add_axes([0, 0, 1, 1], projection="3d")
    ax.set_proj_type("ortho")
    u = np.linspace(0, 2 * math.pi, 48)
    vv = np.linspace(-math.pi / 2, math.pi / 2, 25)
    uu, vg = np.meshgrid(u, vv)
    ax.plot_wireframe(1.002 * radius * np.cos(vg) * np.cos(uu), 1.002 * radius * np.cos(vg) * np.sin(uu),
                      1.002 * radius * np.sin(vg), color=(0.78, 0.78, 0.78), linewidth=0.35, alpha=0.45)
    for (az, el), cov in zip(positions, covs):
        curve = ellipse_curve(azel_to_cart(az, el), cov, scale)
        visible = curve @ camera > 0          # draw only the camera-facing part
        if not visible.any():
            continue
        pts = np.where(visible[:, None], radius * curve, np.nan)
        ax.plot(pts[:, 0], pts[:, 1], pts[:, 2], color=COLOUR, linewidth=1.05)
    ax.view_init(elev=0.0, azim=view_az)
    for setter in (ax.set_xlim, ax.set_ylim, ax.set_zlim):
        setter(-10.1, 10.1)
    ax.set_box_aspect((1, 1, 1))
    ax.set_axis_off()
    buf = BytesIO()
    fig.savefig(buf, dpi=dpi, facecolor="white")      # fixed canvas: identical scale in every panel
    plt.close(fig)
    buf.seek(0)
    return Image.open(buf).convert("RGB")


def contact_sheet(positions, covs, scale, path: Path, views=(0.0, 90.0, 180.0, 270.0)) -> list:
    panels = [render_view(positions, covs, scale, view) for view in views]
    union = None
    for p in panels:
        bbox = ImageChops.difference(p, Image.new("RGB", p.size, "white")).getbbox()
        union = bbox if union is None else (min(union[0], bbox[0]), min(union[1], bbox[1]),
                                            max(union[2], bbox[2]), max(union[3], bbox[3]))
    m = 8
    crop = (max(0, union[0] - m), max(0, union[1] - m), union[2] + m, union[3] + m)
    panels = [p.crop(crop) for p in panels]       # same crop for all panels
    gap = 10
    sheet = Image.new("RGB", (sum(p.width for p in panels) + gap * 3, panels[0].height), "white")
    x = 0
    for p in panels:
        sheet.paste(p, (x, 0))
        x += p.width + gap
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    return panels


def combined_sheet(rows: list[list[Image.Image]], path: Path) -> None:
    """Concatenate panel lists side by side (used for the paper's single comparison figure)."""
    panels = [p for row in rows for p in row]
    h = max(p.height for p in panels)
    gap, sep = 10, 60
    width = sum(p.width for p in panels) + gap * (len(panels) - len(rows)) + sep * (len(rows) - 1)
    sheet = Image.new("RGB", (width, h), "white")
    x = 0
    for i, row in enumerate(rows):
        for j, p in enumerate(row):
            sheet.paste(p, (x, (h - p.height) // 2))
            x += p.width + (gap if j < len(row) - 1 else sep)
    sheet.save(path)


def main() -> None:
    plotted = np.loadtxt(PLOTTED_CSV, delimiter=",", skiprows=1)
    data = np.load(TENSOR_NPZ)
    azel = data["coordinates_azimuth_elevation_deg"]
    idx = []
    for az, el in plotted:
        d = np.abs(((azel[:, 0] - az + 180) % 360) - 180) + np.abs(azel[:, 1] - el)
        idx.append(int(np.argmin(d)))
    g = data["elementwise_median_fisher"][idx]
    assert np.all(np.linalg.eigvalsh(g) > 0), "median Fisher tensor not SPD"
    crb = np.linalg.inv(g)
    crb_panels = contact_sheet(plotted, crb, math.sqrt(CHI2_2_95), OUT / "median_crb_ellipses.png")
    print("CRB figure written")

    if BARUMERLI_MAT.is_file():
        with h5py.File(BARUMERLI_MAT, "r") as f:
            cov = np.asarray(f["covariance"][()])          # (subject, dir, 2, 2) in deg^2
        med = np.nanmedian(cov, axis=0) * (math.pi / 180) ** 2
        ok = np.all(np.isfinite(med.reshape(len(med), -1)), axis=1)
        bar_panels = contact_sheet(plotted[ok], med[ok], 1.0, OUT / "median_barumerli_map_response_covariance.png")
        print(f"Barumerli figure written ({ok.sum()} of {len(ok)} directions)")
        # Paper figure: front (0 deg) and left (90 deg) views of both observers.
        combined_sheet([crb_panels[:2], bar_panels[:2]], OUT / "ellipse_comparison.png")
        print("combined figure written")


if __name__ == "__main__":
    main()
