from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from statistics import median


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESPONSES = ROOT / "ss" / "listening_test" / "server" / "data" / "responses.ndjson"
DEFAULT_VERSION = "adaptive-v9-lateral-psi-dprime1-raw-ml"


def parse_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    return str(value).strip().lower() in {"true", "1", "yes"}


def read_records(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            records.append(json.loads(line))
    return records


def estimate_threshold(track: list[dict]) -> float | None:
    track = sorted(track, key=lambda row: int(row.get("staircaseTrial") or 0))
    final = track[-1].get("thresholdEstimateDeg")
    if isinstance(final, (int, float)):
        return float(final)
    late = [
        float(row["separationDeg"])
        for row in track[len(track) // 2 :]
        if isinstance(row.get("separationDeg"), (int, float))
    ]
    return median(late) if late else None


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarise adaptive 2IFC response data.")
    parser.add_argument("--responses", type=Path, default=DEFAULT_RESPONSES)
    parser.add_argument("--participant", default="")
    parser.add_argument("--axis", default="")
    parser.add_argument("--manifest-version", default=DEFAULT_VERSION)
    args = parser.parse_args()

    records = [
        row for row in read_records(args.responses)
        if row.get("manifestVersion") == args.manifest_version and parse_bool(row.get("adaptive"))
    ]
    if args.participant:
        records = [row for row in records if str(row.get("participantCode", "")).upper() == args.participant.upper()]
    if args.axis:
        records = [row for row in records if str(row.get("axis", "")).lower() == args.axis.lower()]

    if not records:
        print("No matching adaptive responses found.")
        print(f"responses: {args.responses}")
        print(f"manifest:  {args.manifest_version}")
        return 1

    groups: dict[tuple, list[dict]] = defaultdict(list)
    for row in records:
        groups[(row.get("participantCode"), row.get("trackId"))].append(row)

    rows = []
    for (participant, track_id), track in sorted(groups.items()):
        track = sorted(track, key=lambda row: int(row.get("staircaseTrial") or 0))
        first = track[0]
        correct = [parse_bool(row.get("correct")) for row in track]
        rows.append({
            "participant": participant,
            "axis": first.get("axis", ""),
            "subject": first.get("virtualHrtfSubjectId", ""),
            "method": first.get("method", ""),
            "N": first.get("retainedDirections", ""),
            "threshold": estimate_threshold(track),
            "trials": len(track),
            "pc": sum(correct) / max(len(correct), 1),
            "reversals": max((row.get("reversalCount") or 0) for row in track),
            "stop": track[-1].get("staircaseStopReason", ""),
            "AIRM": first.get("localAIRM", ""),
            "dprimeRef": first.get("predictedDPrimeReference", ""),
            "dprimeRecon": first.get("predictedDPrimeField", ""),
        })

    headers = ["axis", "subject", "method", "N", "threshold", "trials", "pc", "reversals", "stop"]
    widths = {header: len(header) for header in headers}
    for row in rows:
        for header in headers:
            value = row[header]
            if isinstance(value, float):
                text = f"{value:.3f}"
            else:
                text = str(value)
            widths[header] = max(widths[header], len(text))

    print(f"Adaptive 2IFC summary ({len(rows)} completed/started tracks, {len(records)} responses)")
    print(" ".join(header.ljust(widths[header]) for header in headers))
    print(" ".join("-" * widths[header] for header in headers))
    for row in rows:
        values = []
        for header in headers:
            value = row[header]
            values.append((f"{value:.3f}" if isinstance(value, float) else str(value)).ljust(widths[header]))
        print(" ".join(values))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
