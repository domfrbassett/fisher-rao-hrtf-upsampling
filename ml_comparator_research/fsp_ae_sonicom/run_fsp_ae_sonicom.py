"""Train and export FSP-AE under the shared SONICOM comparator protocol.

The official FSP-AE source tree is imported as an external dependency and is
not modified. This adapter preserves its feature extraction, model, losses,
minimum-phase reconstruction, and predicted-ITD assignment while replacing
the dataset split and evaluation masks with the common SONICOM protocol.
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import os
import random
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROTOCOL = (
    ROOT
    / "ml_comparator_research"
    / "comparator_protocol"
    / "outputs"
    / "hu_hrtfformer_protocol.json"
)
DEFAULT_FSP_ROOT = ROOT / "_fsp_ae_inspect"
DEFAULT_WORK_ROOT = (
    ROOT / "ml_comparator_research" / "comparator_protocol" / "work" / "fsp_ae_sonicom"
)
DEFAULT_ALIGNED_ROOT = (
    ROOT / "ml_comparator_research" / "comparator_protocol" / "work" / "ml_lap_aligned"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "smoke", "train", "test", "all"))
    parser.add_argument("--sonicom-root", type=Path, required=True)
    parser.add_argument("--fsp-root", type=Path, default=DEFAULT_FSP_ROOT)
    parser.add_argument("--protocol", type=Path, default=DEFAULT_PROTOCOL)
    parser.add_argument("--work-root", type=Path, default=DEFAULT_WORK_ROOT)
    parser.add_argument("--aligned-root", type=Path, default=DEFAULT_ALIGNED_ROOT)
    parser.add_argument("--sofa-suffix", default="FreeFieldCompMinPhase_48kHz")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--epochs", type=int, default=1400)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--validation-size", type=int, default=9)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--limit-subjects", type=int, default=0)
    return parser.parse_args()


def configure_upstream(fsp_root: Path):
    fsp_root = fsp_root.resolve()
    if not (fsp_root / "model" / "models.py").is_file():
        raise FileNotFoundError(f"Official FSP-AE source tree not found: {fsp_root}")
    sys.path.insert(0, str(fsp_root))

    import torch
    import torchaudio
    from dataset import HRTFDataset
    from loss import LSD
    from model import FreqSrcPosCondAutoEncoder
    from utils import get_hrir_with_itd, load_yaml

    return torch, torchaudio, HRTFDataset, LSD, FreqSrcPosCondAutoEncoder, get_hrir_with_itd, load_yaml


def read_protocol(path: Path) -> dict:
    protocol = json.loads(path.read_text(encoding="utf-8"))
    required = {
        "trainSubjectIds",
        "testSubjectIds",
        "retentions",
        "sonicomDirectionIndices",
    }
    missing = required - protocol.keys()
    if missing:
        raise RuntimeError(f"Protocol is missing fields: {sorted(missing)}")
    if tuple(int(x) for x in protocol["retentions"]) != (100, 19, 5, 3):
        raise RuntimeError("Expected shared retention conditions [100, 19, 5, 3].")
    return protocol


def subject_split(protocol: dict, validation_size: int, seed: int):
    training_pool = np.asarray(protocol["trainSubjectIds"], dtype=int)
    if validation_size <= 0 or validation_size >= len(training_pool):
        raise ValueError("validation-size must be between 1 and len(training pool)-1")
    rng = np.random.RandomState(seed)
    valid_ids = sorted(int(x) for x in rng.choice(training_pool, validation_size, replace=False))
    valid_set = set(valid_ids)
    train_ids = sorted(int(x) for x in training_pool if int(x) not in valid_set)
    test_ids = sorted(int(x) for x in protocol["testSubjectIds"])
    if set(train_ids) & set(valid_ids) or (set(train_ids) | set(valid_ids)) & set(test_ids):
        raise RuntimeError("Training, validation, and test subject sets are not disjoint.")
    return train_ids, valid_ids, test_ids


def find_sofa(root: Path, subject_id: int, suffix: str) -> Path:
    name = f"P{subject_id:04d}_{suffix}.sofa"
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise FileNotFoundError(f"Expected one {name} below {root}; found {len(matches)}")
    return matches[0]


def source_positions(sofa_path: Path) -> np.ndarray:
    import netCDF4

    with netCDF4.Dataset(str(sofa_path), "r") as nc:
        return np.asarray(nc.variables["SourcePosition"][:, :], dtype=np.float64)


def front_index(sofa_path: Path) -> int:
    positions = source_positions(sofa_path)
    az = ((positions[:, 0] + 180.0) % 360.0) - 180.0
    return int(np.argmin(az * az + positions[:, 1] * positions[:, 1]))


@dataclass
class DatasetBundle:
    train: object
    valid: object
    test: object
    train_ids: list[int]
    valid_ids: list[int]
    test_ids: list[int]


def make_dataset_class(torch, torchaudio, upstream_dataset):
    class SonicomDataset(upstream_dataset):
        def __init__(self, config, sofa_paths, sample_specs, front_id, fixed_masks=None):
            torch.utils.data.Dataset.__init__(self)
            self.config = config
            self.mag2db = torchaudio.transforms.AmplitudeToDB(stype="magnitude", top_db=80)
            self.sofa_paths = [str(path) for path in sofa_paths]
            self.sample_specs = list(sample_specs)
            self.num_mes_pos_list = self.sample_specs
            self.front_id = int(front_id)
            self.fixed_masks = fixed_masks or {}
            self.cache = {}

        def __len__(self):
            return len(self.sofa_paths) * len(self.sample_specs)

        def __getitem__(self, index):
            sofa_path = self.sofa_paths[index // len(self.sample_specs)]
            spec = self.sample_specs[index % len(self.sample_specs)]
            return self.get_data(sofa_path), spec

        def get_data(self, sofa_path):
            if sofa_path not in self.cache:
                self.cache[sofa_path] = self.sofa2data(
                    sofa_path,
                    False,
                    "sonicom",
                    self.front_id,
                )
            return self.cache[sofa_path]

    return SonicomDataset


def build_datasets(args, protocol, config, torch, torchaudio, upstream_dataset):
    train_ids, valid_ids, test_ids = subject_split(protocol, args.validation_size, args.seed)
    all_ids = train_ids + valid_ids + test_ids
    paths = {sid: find_sofa(args.sonicom_root, sid, args.sofa_suffix) for sid in all_ids}
    first_path = paths[all_ids[0]]
    first_positions = source_positions(first_path)
    expected_directions = len(first_positions)
    masks = {int(k): [int(x) for x in v] for k, v in protocol["sonicomDirectionIndices"].items()}
    for retention, indices in masks.items():
        if len(indices) != retention or len(set(indices)) != retention:
            raise RuntimeError(f"Invalid N={retention} mask: expected {retention} unique rows.")
        if min(indices) < 0 or max(indices) >= expected_directions:
            raise RuntimeError(f"N={retention} mask lies outside the SONICOM grid.")
        expected_az_el = np.asarray(protocol["huMaskAzElDeg"][str(retention)], dtype=float)
        actual_az_el = first_positions[indices, :2].copy()
        actual_az_el[:, 0] = ((actual_az_el[:, 0] + 180.0) % 360.0) - 180.0
        expected_az_el[:, 0] = ((expected_az_el[:, 0] + 180.0) % 360.0) - 180.0
        if not np.allclose(actual_az_el, expected_az_el, atol=1e-8):
            raise RuntimeError(f"N={retention} indices do not reproduce the declared Hu mask.")

    for sid in all_ids[1:]:
        positions = source_positions(paths[sid])
        if positions.shape != first_positions.shape or not np.allclose(
            positions[:, :2], first_positions[:, :2], atol=1e-8
        ):
            raise RuntimeError(f"Subject {sid} does not use the common SONICOM grid.")

    cls = make_dataset_class(torch, torchaudio, upstream_dataset)
    front_id = front_index(first_path)
    train = cls(
        config.data,
        [paths[sid] for sid in train_ids],
        ["all", 100, 19, 5, 3],
        front_id,
    )
    valid = cls(
        config.data,
        [paths[sid] for sid in valid_ids],
        [100, 19, 5, 3],
        front_id,
        masks,
    )
    test = cls(
        config.data,
        [paths[sid] for sid in test_ids],
        ["all"],
        front_id,
        masks,
    )
    return DatasetBundle(train, valid, test, train_ids, valid_ids, test_ids), masks, paths


def load_config(load_yaml, fsp_root: Path):
    config = load_yaml(fsp_root / "config" / "v1.yaml")
    config["data"]["max_freq"] = 16000.0
    config["data"]["num_freq_bin"] = 128
    config["data"]["fs_up"] = 384000.0
    config["architecture"]["freq_norm"] = 16000.0
    config["architecture"]["radius_norm"] = 1.5
    config["architecture"]["num_mes_norm"] = 793.0
    return config


def setup_logging(work_root: Path):
    work_root.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("fsp_ae_sonicom")
    logger.handlers.clear()
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    stream = logging.StreamHandler()
    stream.setFormatter(formatter)
    file_handler = logging.FileHandler(work_root / "train.log", encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(stream)
    logger.addHandler(file_handler)
    return logger


def seed_everything(torch, seed: int):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def stream_stats(torch, dataset):
    totals = {"hrtf_mag": [0.0, 0.0, 0], "itd": [0.0, 0.0, 0]}
    for sofa_path in dataset.sofa_paths:
        item = dataset.get_data(sofa_path)
        for key in totals:
            values = item[key].to(torch.float64)
            totals[key][0] += float(values.sum())
            totals[key][1] += float((values * values).sum())
            totals[key][2] += values.numel()
    result = {}
    for key, (total, squares, count) in totals.items():
        mean = total / count
        variance = max((squares - count * mean * mean) / (count - 1), 0.0)
        result[key] = (torch.tensor(mean), torch.tensor(math.sqrt(variance)))
    return result


def choose_indices(torch, spec, direction_count: int, masks: dict[int, list[int]], fixed: bool):
    if spec == "all":
        return list(range(direction_count))
    retention = int(spec)
    if fixed:
        return masks[retention]
    return sorted(torch.randperm(direction_count)[:retention].tolist())


def model_inputs(torch, data, indices, device):
    hrtf_mag = data["hrtf_mag"].to(device)
    itd = data["itd"].to(device)
    freq = data["frequency"].to(device)
    positions = data["srcpos_cart"].to(device)
    idx = torch.as_tensor(indices, dtype=torch.long, device=device)
    return (
        hrtf_mag[:, idx, :, :],
        itd[:, idx],
        freq,
        positions[:, idx, :],
        positions,
        hrtf_mag,
        itd,
    )


def checkpoint_state(torch, model, optimizer, scheduler, epoch, best_loss, split):
    return {
        "model": model.state_dict(),
        "stats": model.stats,
        "optimizer": optimizer.state_dict(),
        "scheduler": scheduler.state_dict(),
        "epoch": epoch,
        "best_valid_loss": best_loss,
        "subject_split": split,
        "adapter": "fsp_ae_sonicom_v1",
    }


def train(args, config, bundle, masks, torch, LSD, model_cls, logger):
    device = torch.device(args.device)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but torch.cuda.is_available() is false.")
    model = model_cls(config.architecture).to(device)
    stats = stream_stats(torch, bundle.train)
    for key, (mean, std) in stats.items():
        model.set_stats(mean, std, "sonicom", key)

    optimizer = torch.optim.Adam(model.parameters(), lr=config.training.lr)
    scheduler = torch.optim.lr_scheduler.MultiStepLR(
        optimizer,
        milestones=config.training.lr_milestones,
        gamma=config.training.lr_gamma,
    )
    start_epoch = 1
    best_loss = float("inf")
    final_path = args.work_root / "checkpoint_final.pt"
    best_path = args.work_root / "checkpoint_best.pt"
    if args.resume and final_path.is_file():
        state = torch.load(final_path, map_location=device, weights_only=False)
        model.load_state_dict(state["model"])
        model.stats = state["stats"]
        optimizer.load_state_dict(state["optimizer"])
        scheduler.load_state_dict(state["scheduler"])
        start_epoch = int(state["epoch"]) + 1
        best_loss = float(state["best_valid_loss"])
        logger.info("Resuming at epoch %d", start_epoch)
    elif (best_path.exists() or final_path.exists()) and not args.force:
        raise RuntimeError("Checkpoints already exist. Use --resume or --force.")

    loss_lsd = LSD()
    loss_itd = torch.nn.L1Loss()
    split = {
        "train": bundle.train_ids,
        "validation": bundle.valid_ids,
        "test": bundle.test_ids,
    }
    args.work_root.mkdir(parents=True, exist_ok=True)
    (args.work_root / "subject_split.json").write_text(json.dumps(split, indent=2), encoding="utf-8")

    for epoch in range(start_epoch, args.epochs + 1):
        model.train()
        train_loss = 0.0
        for index in range(len(bundle.train)):
            data, spec = bundle.train[index]
            data = {k: (v.unsqueeze(0) if hasattr(v, "ndim") else v) for k, v in data.items()}
            indices = choose_indices(torch, spec, data["hrtf_mag"].shape[1], masks, fixed=False)
            inputs = model_inputs(torch, data, indices, device)
            hrtf_pred, itd_pred = model(*inputs[:5], "sonicom", device)
            loss = (
                config.training.loss_weight.lsd * loss_lsd(hrtf_pred, inputs[5], dim=3)
                + config.training.loss_weight.ae_itd * loss_itd(itd_pred, inputs[6])
            )
            if not torch.isfinite(loss):
                raise FloatingPointError(f"Non-finite training loss at epoch {epoch}, item {index}.")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()
            train_loss += float(loss.detach())

        model.eval()
        valid_loss = 0.0
        with torch.no_grad():
            for index in range(len(bundle.valid)):
                data, spec = bundle.valid[index]
                data = {k: (v.unsqueeze(0) if hasattr(v, "ndim") else v) for k, v in data.items()}
                indices = choose_indices(torch, spec, data["hrtf_mag"].shape[1], masks, fixed=True)
                inputs = model_inputs(torch, data, indices, device)
                hrtf_pred, itd_pred = model(*inputs[:5], "sonicom", device)
                valid_loss += float(
                    config.training.loss_weight.lsd * loss_lsd(hrtf_pred, inputs[5], dim=3)
                    + config.training.loss_weight.ae_itd * loss_itd(itd_pred, inputs[6])
                )
        train_loss /= len(bundle.train)
        valid_loss /= len(bundle.valid)
        scheduler.step()
        logger.info(
            "epoch=%d/%d train=%.6f valid=%.6f lr=%.3g",
            epoch,
            args.epochs,
            train_loss,
            valid_loss,
            scheduler.get_last_lr()[0],
        )
        if valid_loss < best_loss:
            best_loss = valid_loss
            torch.save(
                checkpoint_state(torch, model, optimizer, scheduler, epoch, best_loss, split),
                best_path,
            )
        if epoch % int(config.training.save_interval) == 0:
            torch.save(
                checkpoint_state(torch, model, optimizer, scheduler, epoch, best_loss, split),
                args.work_root / f"checkpoint_epoch_{epoch:04d}.pt",
            )
        torch.save(
            checkpoint_state(torch, model, optimizer, scheduler, epoch, best_loss, split),
            final_path,
        )
    return best_path


def clone_sofa_with_ir(source: Path, destination: Path, hrir: np.ndarray, sampling_rate: float):
    import netCDF4

    destination.parent.mkdir(parents=True, exist_ok=True)
    with netCDF4.Dataset(str(source), "r") as src, netCDF4.Dataset(str(destination), "w") as dst:
        ir_var = src.variables["Data.IR"]
        sample_dim = ir_var.dimensions[-1]
        for name, dim in src.dimensions.items():
            size = hrir.shape[-1] if name == sample_dim else len(dim)
            dst.createDimension(name, None if dim.isunlimited() else size)
        dst.setncatts({name: src.getncattr(name) for name in src.ncattrs()})
        for name, variable in src.variables.items():
            fill = variable.getncattr("_FillValue") if "_FillValue" in variable.ncattrs() else None
            kwargs = {"fill_value": fill} if fill is not None else {}
            out = dst.createVariable(name, variable.datatype, variable.dimensions, **kwargs)
            out.setncatts(
                {attr: variable.getncattr(attr) for attr in variable.ncattrs() if attr != "_FillValue"}
            )
            if name == "Data.IR":
                out[:] = hrir
            elif name == "Data.SamplingRate":
                out[:] = sampling_rate
            elif name == "Data.Delay":
                out[:] = np.zeros(variable.shape, dtype=variable.dtype)
            else:
                out[:] = variable[:]


def export(args, config, bundle, masks, paths, torch, torchaudio, model_cls, get_hrir_with_itd):
    device = torch.device(args.device)
    checkpoint = args.checkpoint or (args.work_root / "checkpoint_best.pt")
    if not checkpoint.is_file():
        raise FileNotFoundError(f"Checkpoint not found: {checkpoint}")
    state = torch.load(checkpoint, map_location=device, weights_only=False)
    model = model_cls(config.architecture).to(device)
    model.load_state_dict(state["model"])
    model.stats = state["stats"]
    model.eval()
    args.aligned_root.mkdir(parents=True, exist_ok=True)
    test_ids = bundle.test_ids[: args.limit_subjects or None]

    manifest = []
    for subject_id in test_ids:
        data = bundle.test.get_data(str(paths[subject_id]))
        batch = {k: (v.unsqueeze(0) if hasattr(v, "ndim") else v) for k, v in data.items()}
        for retention in (100, 19, 5, 3):
            indices = masks[retention]
            inputs = model_inputs(torch, batch, indices, device)
            with torch.no_grad():
                hrtf_pred, itd_pred = model(*inputs[:5], "sonicom", device)
                idx = torch.as_tensor(indices, dtype=torch.long, device=device)
                hrtf_pred[:, idx, :, :] = inputs[5][:, idx, :, :]
                itd_pred[:, idx] = inputs[6][:, idx]
                hrir_32k = get_hrir_with_itd(
                    hrtf_pred,
                    itd_pred,
                    input_kind="hrtf_mag",
                    fs=32000.0,
                    fs_up=config.data.fs_up,
                )
                resampler = torchaudio.transforms.Resample(32000, 48000).to(device)
                flat = hrir_32k.reshape(-1, hrir_32k.shape[-1])
                hrir_48k = resampler(flat).reshape(
                    hrir_32k.shape[0], hrir_32k.shape[1], hrir_32k.shape[2], -1
                )
            output = args.aligned_root / "FSP_AE" / f"N{retention:03d}" / f"Sonicom_{subject_id}.sofa"
            clone_sofa_with_ir(
                paths[subject_id],
                output,
                hrir_48k[0].cpu().numpy().astype(np.float64),
                48000.0,
            )
            manifest.append(
                {
                    "subjectId": subject_id,
                    "retainedDirections": retention,
                    "sofa": str(output),
                    "nodeReplacement": "magnitude_and_predicted_itd_before_hrir_reconstruction",
                    "nativeSamplingRate": 32000,
                    "exportSamplingRate": 48000,
                }
            )
            print(f"Exported {output}")
    (args.work_root / "export_manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )


def validate(args, protocol, bundle, masks, torch):
    print(f"Protocol: {args.protocol}")
    print(f"Subjects: train={len(bundle.train_ids)}, validation={len(bundle.valid_ids)}, test={len(bundle.test_ids)}")
    print(f"Test IDs: {bundle.test_ids}")
    for retention in (100, 19, 5, 3):
        print(f"N={retention}: {len(masks[retention])} unique retained rows")
    first = bundle.train.get_data(bundle.train.sofa_paths[0])
    print(
        "First subject tensors: "
        f"magnitude={tuple(first['hrtf_mag'].shape)}, "
        f"ITD={tuple(first['itd'].shape)}, HRIR={tuple(first['hrir'].shape)}"
    )
    print(f"torch={torch.__version__}, cuda={torch.cuda.is_available()}")


def smoke(
    args,
    config,
    bundle,
    masks,
    paths,
    torch,
    torchaudio,
    LSD,
    model_cls,
    get_hrir_with_itd,
):
    device = torch.device(args.device)
    model = model_cls(config.architecture).to(device)
    stats = stream_stats(torch, make_single_subject_dataset(bundle.train))
    for key, (mean, std) in stats.items():
        model.set_stats(mean, std, "sonicom", key)
    data = bundle.train.get_data(bundle.train.sofa_paths[0])
    batch = {k: (v.unsqueeze(0) if hasattr(v, "ndim") else v) for k, v in data.items()}
    inputs = model_inputs(torch, batch, masks[3], device)
    model.train()
    optimizer = torch.optim.Adam(model.parameters(), lr=config.training.lr)
    hrtf_train, itd_train = model(*inputs[:5], "sonicom", device)
    smoke_loss = (
        config.training.loss_weight.lsd * LSD()(hrtf_train, inputs[5], dim=3)
        + config.training.loss_weight.ae_itd * torch.nn.functional.l1_loss(itd_train, inputs[6])
    )
    if not torch.isfinite(smoke_loss):
        raise FloatingPointError("Smoke training step produced a non-finite loss.")
    optimizer.zero_grad(set_to_none=True)
    smoke_loss.backward()
    if any(
        parameter.grad is not None and not torch.isfinite(parameter.grad).all()
        for parameter in model.parameters()
    ):
        raise FloatingPointError("Smoke training step produced non-finite gradients.")
    optimizer.step()
    model.eval()
    with torch.no_grad():
        hrtf_pred, itd_pred = model(*inputs[:5], "sonicom", device)
    if hrtf_pred.shape != inputs[5].shape or itd_pred.shape != inputs[6].shape:
        raise RuntimeError("Unexpected model output shape.")
    if not torch.isfinite(hrtf_pred).all() or not torch.isfinite(itd_pred).all():
        raise FloatingPointError("Smoke inference produced non-finite values.")
    idx = torch.as_tensor(masks[3], dtype=torch.long, device=device)
    hrtf_pred[:, idx, :, :] = inputs[5][:, idx, :, :]
    itd_pred[:, idx] = inputs[6][:, idx]
    with torch.no_grad():
        hrir_32k = get_hrir_with_itd(
            hrtf_pred,
            itd_pred,
            input_kind="hrtf_mag",
            fs=32000.0,
            fs_up=config.data.fs_up,
        )
        resampler = torchaudio.transforms.Resample(32000, 48000).to(device)
        flat = hrir_32k.reshape(-1, hrir_32k.shape[-1])
        hrir_48k = resampler(flat).reshape(
            hrir_32k.shape[0], hrir_32k.shape[1], hrir_32k.shape[2], -1
        )
    subject_id = bundle.train_ids[0]
    smoke_sofa = args.work_root / "smoke" / f"Sonicom_{subject_id}_N003.sofa"
    clone_sofa_with_ir(
        paths[subject_id],
        smoke_sofa,
        hrir_48k[0].cpu().numpy().astype(np.float64),
        48000.0,
    )
    print(
        f"Smoke inference passed on {device}: magnitude={tuple(hrtf_pred.shape)}, "
        f"ITD={tuple(itd_pred.shape)}, SOFA={smoke_sofa}"
    )


def make_single_subject_dataset(dataset):
    class Single:
        sofa_paths = dataset.sofa_paths[:1]

        @staticmethod
        def get_data(path):
            return dataset.get_data(path)

    return Single()


def main() -> int:
    args = parse_args()
    args.sonicom_root = args.sonicom_root.resolve()
    args.fsp_root = args.fsp_root.resolve()
    args.protocol = args.protocol.resolve()
    args.work_root = args.work_root.resolve()
    args.aligned_root = args.aligned_root.resolve()
    if not args.sonicom_root.is_dir():
        raise FileNotFoundError(f"SONICOM root does not exist: {args.sonicom_root}")

    components = configure_upstream(args.fsp_root)
    torch, torchaudio, upstream_dataset, LSD, model_cls, get_hrir_with_itd, load_yaml = components
    seed_everything(torch, args.seed)
    protocol = read_protocol(args.protocol)
    config = load_config(load_yaml, args.fsp_root)
    bundle, masks, paths = build_datasets(
        args, protocol, config, torch, torchaudio, upstream_dataset
    )
    logger = setup_logging(args.work_root)

    if args.command in ("validate", "all"):
        validate(args, protocol, bundle, masks, torch)
    if args.command == "smoke":
        smoke(
            args,
            config,
            bundle,
            masks,
            paths,
            torch,
            torchaudio,
            LSD,
            model_cls,
            get_hrir_with_itd,
        )
    if args.command in ("train", "all"):
        train(args, config, bundle, masks, torch, LSD, model_cls, logger)
    if args.command in ("test", "all"):
        export(args, config, bundle, masks, paths, torch, torchaudio, model_cls, get_hrir_with_itd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
