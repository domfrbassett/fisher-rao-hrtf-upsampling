from __future__ import annotations

import csv
import math
from io import BytesIO
from pathlib import Path

import matplotlib
import numpy as np
from PIL import Image, ImageChops

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]
INPUT_CSV = ROOT / "results" / "audits" / "barumerli_sonicom41_median_tensor.csv"
OUTPUT_ROOT = ROOT / "figures" / "diagnostics" / "barumerli_sonicom41"

ELLIPSE_SCALE = 1.0
PLOT_ELEVATIONS = {-20.0, 0.0, 20.0, 40.0}


def nearest_spd(matrix: np.ndarray, floor: float = 1.0e-9) -> np.ndarray:
    matrix = 0.5 * (matrix + matrix.T)
    values, vectors = np.linalg.eigh(matrix)
    values = np.maximum(values, floor)
    return (vectors * values[None, :]) @ vectors.T


def read_barumerli_covariances() -> tuple[np.ndarray, np.ndarray]:
    positions = []
    covariances = []
    with INPUT_CSV.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            elevation = float(row["requested_el_deg"])
            if elevation not in PLOT_ELEVATIONS:
                continue
            azimuth = float(row["requested_az_deg"]) % 360.0
            cov = np.array(
                [
                    [float(row["cov_azaz_deg2"]), float(row["cov_azel_deg2"])],
                    [float(row["cov_azel_deg2"]), float(row["cov_elel_deg2"])],
                ],
                dtype=float,
            )
            if not np.isfinite(cov).all():
                continue
            positions.append([azimuth, elevation])
            covariances.append(nearest_spd(cov))

    if not positions:
        raise RuntimeError(f"No plottable covariance rows found in {INPUT_CSV}")
    return np.array(positions, dtype=float), np.stack(covariances, axis=0)


def azel_to_cart(azimuth_deg: float, elevation_deg: float) -> np.ndarray:
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


def azel_tangent_basis(azimuth_deg: float, elevation_deg: float) -> tuple[np.ndarray, np.ndarray]:
    azimuth = math.radians(azimuth_deg)
    elevation = math.radians(elevation_deg)
    east = np.array([-math.sin(azimuth), math.cos(azimuth), 0.0], dtype=float)
    north = np.array(
        [
            -math.sin(elevation) * math.cos(azimuth),
            -math.sin(elevation) * math.sin(azimuth),
            math.cos(elevation),
        ],
        dtype=float,
    )
    return east / np.linalg.norm(east), north / np.linalg.norm(north)


def covariance_to_physical_tangent(
    covariance_azel_deg2: np.ndarray,
    elevation_deg: float,
) -> np.ndarray:
    transform = np.diag([math.cos(math.radians(elevation_deg)), 1.0])
    covariance_physical_deg2 = transform @ covariance_azel_deg2 @ transform
    covariance_physical_deg2 = 0.5 * (covariance_physical_deg2 + covariance_physical_deg2.T)
    return nearest_spd(covariance_physical_deg2) * (math.pi / 180.0) ** 2


def ellipse_curve(
    azimuth_deg: float,
    elevation_deg: float,
    covariance_azel_deg2: np.ndarray,
    n_points: int = 150,
) -> np.ndarray:
    r = azel_to_cart(azimuth_deg, elevation_deg)
    east, north = azel_tangent_basis(azimuth_deg, elevation_deg)
    covariance = covariance_to_physical_tangent(covariance_azel_deg2, elevation_deg)

    values, vectors = np.linalg.eigh(covariance)
    values = np.maximum(values, 0.0)
    theta = np.linspace(0.0, 2.0 * math.pi, n_points)
    circle = np.vstack([np.cos(theta), np.sin(theta)])
    tangent_offsets = vectors @ (np.sqrt(values)[:, None] * circle) * ELLIPSE_SCALE

    curve = np.zeros((n_points, 3), dtype=float)
    for i_point in range(n_points):
        offset = tangent_offsets[0, i_point] * east + tangent_offsets[1, i_point] * north
        distance = float(np.linalg.norm(offset))
        if distance < 1.0e-12:
            point = r
        else:
            point = math.cos(distance) * r + math.sin(distance) * offset / distance
            point = point / np.linalg.norm(point)
        curve[i_point] = point
    return curve


def view_direction(azimuth_deg: float, elevation_deg: float = 0.0) -> np.ndarray:
    return azel_to_cart(azimuth_deg, elevation_deg)


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


def render_single_view_image(
    positions: np.ndarray,
    covariances: np.ndarray,
    azimuth_view_deg: float,
    *,
    dpi: int = 700,
) -> Image.Image:
    radius = 10.0
    color_ellipse = (0.84, 0.12, 0.12)
    camera = view_direction(azimuth_view_deg)

    fig = plt.figure(figsize=(4.0, 4.0), facecolor="white")
    ax = fig.add_axes([0.0, 0.0, 1.0, 1.0], projection="3d")
    ax.set_proj_type("ortho")
    draw_sphere(ax, radius)

    for (azimuth, elevation), covariance in zip(positions, covariances):
        centre = azel_to_cart(float(azimuth), float(elevation))
        if float(np.dot(centre, camera)) <= 0.0:
            continue
        curve = ellipse_curve(float(azimuth), float(elevation), covariance)
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


def render_contact_sheet(positions: np.ndarray, covariances: np.ndarray, output_stem: str) -> None:
    views = [0.0, 90.0, 180.0, 270.0]
    panels = [render_single_view_image(positions, covariances, view) for view in views]
    target_height = max(panel.height for panel in panels)
    resized = []
    for panel in panels:
        scale = target_height / panel.height
        resized.append(
            panel.resize(
                (int(round(panel.width * scale)), target_height),
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

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    png_path = OUTPUT_ROOT / f"{output_stem}.png"
    pdf_path = OUTPUT_ROOT / f"{output_stem}.pdf"
    sheet.save(png_path)
    sheet.save(pdf_path, "PDF", resolution=700.0)


def main() -> None:
    positions, covariances = read_barumerli_covariances()
    render_contact_sheet(
        positions,
        covariances,
        "barumerli_sonicom41_map_response_covariance",
    )
    print(f"Loaded {len(positions)} median covariance ellipses from {INPUT_CSV}")
    print(f"Wrote outputs to {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
