from __future__ import annotations

import math
from io import BytesIO
from pathlib import Path

import matplotlib
import numpy as np
from PIL import Image, ImageChops

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]
INPUT_NPZ = ROOT / "results" / "audits" / "seeded_41_median_fisher_and_covariance.npz"
OUTPUT_DIR = ROOT / "figures" / "evaluation"
OUTPUT_STEM = "median_crb_ellipses"


def nearest_spd(tensor: np.ndarray, floor: float = 1.0e-12) -> np.ndarray:
    tensor = 0.5 * (tensor + np.swapaxes(tensor, -1, -2))
    values, vectors = np.linalg.eigh(tensor)
    values = np.maximum(values, floor)
    return (vectors * values[..., None, :]) @ np.swapaxes(vectors, -1, -2)


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


def ellipse_curve(
    r: np.ndarray,
    covariance: np.ndarray,
    scale: float,
    n_points: int = 150,
) -> np.ndarray:
    covariance = nearest_spd(covariance)
    values, vectors = np.linalg.eigh(covariance)
    values = np.maximum(values, 0.0)
    theta = np.linspace(0.0, 2.0 * math.pi, n_points)
    circle = np.vstack([np.cos(theta), np.sin(theta)])
    tangent_offsets = vectors @ (np.sqrt(values)[:, None] * circle) * scale

    basis = local_tangent_basis(r)
    offsets = basis @ tangent_offsets
    curve = np.zeros((n_points, 3), dtype=float)
    for i_point in range(n_points):
        offset = offsets[:, i_point]
        distance = float(np.linalg.norm(offset))
        if distance < 1.0e-12:
            point = r
        else:
            point = math.cos(distance) * r + math.sin(distance) * offset / distance
            point = point / np.linalg.norm(point)
        curve[i_point] = point
    return curve


def azel_to_cart(azimuth_deg: float, elevation_deg: float = 0.0) -> np.ndarray:
    azimuth = math.radians(azimuth_deg)
    elevation = math.radians(elevation_deg)
    return np.array(
        [
            math.cos(elevation) * math.cos(azimuth),
            math.cos(elevation) * math.sin(azimuth),
            math.sin(elevation),
        ],
        dtype=float,
    )


def draw_sphere(ax, radius: float) -> None:
    u = np.linspace(0.0, 2.0 * math.pi, 48)
    v = np.linspace(-0.5 * math.pi, 0.5 * math.pi, 25)
    uu, vv = np.meshgrid(u, v)
    x = radius * np.cos(vv) * np.cos(uu)
    y = radius * np.cos(vv) * np.sin(uu)
    z = radius * np.sin(vv)
    ax.plot_wireframe(
        1.002 * x,
        1.002 * y,
        1.002 * z,
        color=(0.78, 0.78, 0.78),
        linewidth=0.35,
        alpha=0.45,
    )


def render_single_view(
    covariance: np.ndarray,
    cart: np.ndarray,
    indices: np.ndarray,
    scale: float,
    azimuth_view_deg: float,
    *,
    dpi: int = 700,
) -> Image.Image:
    radius = 10.0
    color_ellipse = (0.12, 0.37, 0.72)
    camera = azel_to_cart(azimuth_view_deg)

    fig = plt.figure(figsize=(4.0, 4.0), facecolor="white")
    ax = fig.add_axes([0.0, 0.0, 1.0, 1.0], projection="3d")
    ax.set_proj_type("ortho")
    draw_sphere(ax, radius)

    for idx in indices:
        r = cart[idx]
        if float(np.dot(r, camera)) <= 0.0:
            continue
        curve = ellipse_curve(r, covariance[idx], scale)
        ax.plot(
            radius * curve[:, 0],
            radius * curve[:, 1],
            radius * curve[:, 2],
            color=color_ellipse,
            linewidth=1.05,
        )

    ax.view_init(elev=0.0, azim=azimuth_view_deg)
    ax.set_xlim(-10.1, 10.1)
    ax.set_ylim(-10.1, 10.1)
    ax.set_zlim(-10.1, 10.1)
    ax.set_box_aspect((1.0, 1.0, 1.0))
    ax.set_axis_off()

    buffer = BytesIO()
    fig.savefig(buffer, dpi=dpi, facecolor="white", bbox_inches="tight", pad_inches=0.0)
    plt.close(fig)
    buffer.seek(0)
    image = Image.open(buffer).convert("RGB")

    background = Image.new("RGB", image.size, "white")
    diff = ImageChops.difference(image, background)
    bbox = diff.getbbox()
    if bbox is None:
        return image
    margin = 8
    left = max(0, bbox[0] - margin)
    top = max(0, bbox[1] - margin)
    right = min(image.size[0], bbox[2] + margin)
    bottom = min(image.size[1], bbox[3] + margin)
    return image.crop((left, top, right, bottom))


def render_contact_sheet(covariance: np.ndarray, cart: np.ndarray, indices: np.ndarray, scale: float) -> None:
    panels = [
        render_single_view(covariance, cart, indices, scale, view)
        for view in (0.0, 90.0, 180.0, 270.0)
    ]
    target_height = max(panel.height for panel in panels)
    resized = []
    for panel in panels:
        factor = target_height / panel.height
        resized.append(
            panel.resize(
                (int(round(panel.width * factor)), target_height),
                resample=Image.Resampling.LANCZOS,
            )
        )

    gap = 10
    width = sum(panel.width for panel in resized) + gap * (len(resized) - 1)
    sheet = Image.new("RGB", (width, target_height), "white")
    x = 0
    for panel in resized:
        sheet.paste(panel, (x, 0))
        x += panel.width + gap

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    png_path = OUTPUT_DIR / f"{OUTPUT_STEM}.png"
    pdf_path = OUTPUT_DIR / f"{OUTPUT_STEM}.pdf"
    sheet.save(png_path)
    sheet.save(pdf_path, "PDF", resolution=700.0)


def main() -> None:
    data = np.load(INPUT_NPZ)
    covariance = data["covariance"]
    cart = data["coordinates_cartesian"]
    indices = data["plotted_indices"].astype(int)
    chi2_2_95 = float(data["chi2_2_95"])
    render_contact_sheet(covariance, cart, indices, math.sqrt(chi2_2_95))
    print(f"Loaded median CRB data from {INPUT_NPZ}")
    print(f"Wrote {OUTPUT_DIR / (OUTPUT_STEM + '.png')}")


if __name__ == "__main__":
    main()
