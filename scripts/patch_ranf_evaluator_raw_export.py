from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Patch MERL RANF evaluation to also write raw no-node-replacement SOFAs."
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path("ml_comparator_research/repos/RANF_HRTF"),
        help="Path to the RANF_HRTF repository checkout.",
    )
    args = parser.parse_args()

    eval_path = args.repo_root / "ranf" / "3_evaluating_neural_field.py"
    if not eval_path.is_file():
        raise FileNotFoundError(f"RANF evaluator not found: {eval_path}")

    text = eval_path.read_text(encoding="utf-8")

    if "eval_raw_no_node_replacement" in text:
        print(f"Already patched: {eval_path}")
        return 0

    if "from copy import deepcopy" not in text:
        text = text.replace("import argparse\n", "import argparse\nfrom copy import deepcopy\n", 1)

    old_mkdir = (
        '    log.joinpath("eval").mkdir(parents=True, exist_ok=True)\n'
        '    log_name = log.joinpath("eval").joinpath("eval.log")\n'
    )
    new_mkdir = (
        '    log.joinpath("eval").mkdir(parents=True, exist_ok=True)\n'
        '    log.joinpath("eval_raw_no_node_replacement").mkdir(parents=True, exist_ok=True)\n'
        '    log_name = log.joinpath("eval").joinpath("eval.log")\n'
    )
    if old_mkdir not in text:
        raise RuntimeError("Could not find eval folder creation block.")
    text = text.replace(old_mkdir, new_mkdir, 1)

    old_export = (
        '        target_path = log.joinpath("eval").joinpath(f"target_p{data[-2][0]+1:04}.sofa")\n'
        '        pred_path = log.joinpath("eval").joinpath(f"pred_p{data[-2][0]+1:04}.sofa")\n'
        "\n"
        "        sf.write_sofa(target_path, sofa_file)\n"
        "\n"
        "        sofa_file.Data_IR[unseen_didxs, ...] = pred_hrir.astype(np.float64)[unseen_didxs, ...]\n"
        "        sf.write_sofa(pred_path, sofa_file)\n"
    )
    new_export = (
        "        subject_id = int(data[-2][0] + 1)\n"
        "\n"
        '        target_path = log.joinpath("eval").joinpath(f"target_p{subject_id:04}.sofa")\n'
        '        pred_path = log.joinpath("eval").joinpath(f"pred_p{subject_id:04}.sofa")\n'
        '        raw_pred_path = log.joinpath("eval_raw_no_node_replacement").joinpath(\n'
        '            f"pred_p{subject_id:04}.sofa"\n'
        "        )\n"
        "\n"
        "        sf.write_sofa(target_path, sofa_file)\n"
        "\n"
        "        raw_sofa = deepcopy(sofa_file)\n"
        "        raw_sofa.Data_IR = pred_hrir.astype(np.float64)\n"
        "        sf.write_sofa(raw_pred_path, raw_sofa)\n"
        "\n"
        "        node_replaced_sofa = deepcopy(sofa_file)\n"
        "        node_replaced_sofa.Data_IR[unseen_didxs, ...] = pred_hrir.astype(np.float64)[unseen_didxs, ...]\n"
        "        sf.write_sofa(pred_path, node_replaced_sofa)\n"
    )
    if old_export not in text:
        raise RuntimeError("Could not find node-replacement export block.")
    text = text.replace(old_export, new_export, 1)

    backup = eval_path.with_suffix(eval_path.suffix + ".before_raw_export_patch")
    backup.write_text(eval_path.read_text(encoding="utf-8"), encoding="utf-8")
    eval_path.write_text(text, encoding="utf-8")
    print(f"Patched: {eval_path}")
    print(f"Backup:  {backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
