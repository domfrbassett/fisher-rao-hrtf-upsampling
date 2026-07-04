"""Run RANF under the shared SONICOM split and sparse masks.

This wrapper avoids the public RANF LAP-specific split and retrieval-matrix
assumptions. It leaves the RANF repository intact apart from the small optional
mask hook in `ranf.utils.util`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np


def run_module(repo_root: Path, module: str, args: list[str], env: dict[str, str]) -> None:
    cmd = [sys.executable, "-m", module, *args]
    subprocess.check_call(cmd, cwd=repo_root, env=env)


def load_protocol(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_ranf_retrieval_mats(repo_root: Path, dump_dir: Path, retention: int, protocol: dict, valid_ids: list[int]) -> None:
    sys.path.insert(0, str(repo_root))
    from ranf.utils.config import LSDFREQIDX

    npz = np.load(dump_dir / "features_and_locs_with_azimuth_calibration.npz")
    seen = np.array(protocol["sonicomDirectionIndices"][str(retention)], dtype=int)
    specs = npz["specs"][:, seen, :, :]
    itds = npz["itds"][:, seen]
    specs = 20 * np.log10(specs[..., LSDFREQIDX] + 1e-15)

    nsubjects = itds.shape[0]
    train_pool = set(int(x) - 1 for x in protocol["trainSubjectIds"])
    test_pool = set(int(x) - 1 for x in protocol["testSubjectIds"])
    valid_pool = set(int(x) - 1 for x in valid_ids)
    retrieval_candidates = sorted(train_pool | valid_pool)

    lsd_mat = np.inf * np.ones((nsubjects, nsubjects), dtype=np.float32)
    itdd_mat = np.inf * np.ones((nsubjects, nsubjects), dtype=np.float32)

    for n in range(nsubjects):
        if n in test_pool:
            candidates = retrieval_candidates
        else:
            candidates = [m for m in retrieval_candidates if m != n]
        for m in candidates:
            mse = np.mean(np.square(specs[n, ...] - specs[m, ...]), axis=-1)
            lsd_mat[n, m] = np.mean(np.sqrt(mse))
            itdd_mat[n, m] = np.mean(np.abs(itds[n, :] - itds[m, :]))

    np.savez(dump_dir / "lsd_itdd_mats.npz", lsd_mat=lsd_mat, itdd_mat=itdd_mat)


def write_ranf_config(repo_root: Path, exp_dir: Path, dump_dir: Path, sonicom_work_root: Path,
                      retention: int, protocol: dict, valid_size: int, seed: int) -> None:
    sys.path.insert(0, str(repo_root))
    from omegaconf import OmegaConf

    template = repo_root / "config_template" / "ranf" / "original_config.yaml"
    cfg = OmegaConf.load(template)
    rng = np.random.default_rng(seed)
    hu_train = np.array(protocol["trainSubjectIds"], dtype=int)
    valid_ids = sorted(int(x) for x in rng.choice(hu_train, size=valid_size, replace=False))
    train_ids = sorted(int(x) for x in hu_train if int(x) not in set(valid_ids))

    cfg.dataset.upsample = int(retention)
    cfg.dataset.train_subjects = [x - 1 for x in train_ids]
    cfg.dataset.valid_subjects = [x - 1 for x in valid_ids]
    cfg.dataset.test_subjects = [int(x) - 1 for x in protocol["testSubjectIds"]]
    cfg.dataset.features = str(dump_dir / "features_and_locs_with_azimuth_calibration.npz")
    cfg.dataset.retrieval = str(dump_dir / "lsd_itdd_mats.npz")
    cfg.dataset.azimuth_calibration = True
    cfg.model.config.azimuth_calibration = True
    cfg.seed = int(seed)

    exp_dir.mkdir(parents=True, exist_ok=True)
    OmegaConf.save(config=cfg, f=exp_dir / "config.yaml")
    (exp_dir / "hu_train_subjects.txt").write_text("\n".join(map(str, train_ids)), encoding="utf-8")
    (exp_dir / "hu_valid_subjects.txt").write_text("\n".join(map(str, valid_ids)), encoding="utf-8")
    (exp_dir / "hu_test_subjects.txt").write_text(
        "\n".join(map(str, protocol["testSubjectIds"])), encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["features", "retrieval", "config", "train", "adapt", "eval", "all"])
    parser.add_argument("--retention", type=int, required=True, choices=[3, 5, 19, 100])
    parser.add_argument("--repo-root", type=Path, default=Path("ml_comparator_research/repos/RANF_HRTF"))
    parser.add_argument("--protocol-json", type=Path, default=Path("ml_comparator_research/comparator_protocol/outputs/hu_hrtfformer_protocol.json"))
    parser.add_argument("--work-root", type=Path, default=Path("ml_comparator_research/comparator_protocol/work/ranf_sonicom"))
    parser.add_argument("--valid-size", type=int, default=9)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    args.repo_root = args.repo_root.resolve()
    args.protocol_json = args.protocol_json.resolve()
    args.work_root = args.work_root.resolve()

    protocol = load_protocol(args.protocol_json)
    dump_dir = args.work_root / f"sp_level_{args.retention:03d}"
    exp_dir = args.work_root / "experiments" / f"ranf_hu_N{args.retention:03d}"
    subjects_dir = args.work_root / "sonicom" / "subjects"
    env = os.environ.copy()
    env["PYTHONPATH"] = str(args.repo_root) + os.pathsep + env.get("PYTHONPATH", "")
    env["FISHERRAO_RANF_MASK_JSON"] = str(args.protocol_json.resolve())

    modes = ["features", "retrieval", "config", "train", "adapt", "eval"] if args.mode == "all" else [args.mode]
    for mode in modes:
        if mode == "features":
            run_module(args.repo_root, "ranf.compute_spec_ild_itd_for_sonicom_datasets", [
                str(subjects_dir), str(dump_dir), "--upsample", str(args.retention), "--calibrate_itdoffset"
            ], env)
        elif mode == "retrieval":
            rng = np.random.default_rng(args.seed)
            valid_ids = sorted(int(x) for x in rng.choice(np.array(protocol["trainSubjectIds"]), size=args.valid_size, replace=False))
            write_ranf_retrieval_mats(args.repo_root, dump_dir, args.retention, protocol, valid_ids)
        elif mode == "config":
            write_ranf_config(args.repo_root, exp_dir, dump_dir, args.work_root, args.retention, protocol, args.valid_size, args.seed)
        elif mode == "train":
            run_module(args.repo_root, "ranf.1_pretraining_neural_field", [str(exp_dir)], env)
        elif mode == "adapt":
            run_module(args.repo_root, "ranf.2_adapting_neural_field", [str(exp_dir)], env)
        elif mode == "eval":
            run_module(args.repo_root, "ranf.3_evaluating_neural_field", [str(exp_dir)], env)

    print(f"RANF experiment folder: {exp_dir}")
    print(f"RANF evaluation SOFAs: {exp_dir / 'log' / 'eval'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
