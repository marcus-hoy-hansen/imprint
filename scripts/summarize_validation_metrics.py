#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


OUTPUT_COLUMNS = [
    "sample",
    "sample_id",
    "reference",
    "mode",
    "panel_type",
    "target_cov_q1",
    "target_cov_median",
    "target_cov_q3",
    "target_cov_mean",
    "off_target_cov_mean",
    "target_readlen_q1",
    "target_readlen_median",
    "target_readlen_q3",
    "target_readlen_n50",
    "off_target_readlen_q1",
    "off_target_readlen_median",
    "off_target_readlen_q3",
    "off_target_readlen_n50",
    "reads_total",
    "reads_mapped",
    "reads_unmapped",
    "total_bases",
    "mapping_efficiency_pct",
    "primary_mapped_reads",
    "error_rate",
    "average_read_length",
    "maximum_read_length",
]


def blank_row() -> dict[str, str]:
    return {column: "" for column in OUTPUT_COLUMNS}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize QC/validation_metrics across an analysis_v2 folder."
    )
    parser.add_argument(
        "--analysis-dir",
        default="/faststorage/project/nanopore_kga/analysis_v2",
        help="Root analysis directory containing sample folders.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output TSV path.",
    )
    return parser.parse_args()


def split_sample_name(sample: str) -> tuple[str, str, str]:
    parts = sample.split("_")
    sample_id = parts[0] if len(parts) > 0 else ""
    reference = parts[1] if len(parts) > 1 else ""
    mode = parts[2] if len(parts) > 2 else ""
    return sample_id, reference, mode


def parse_key_value_file(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data

    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        key, value = parts
        data[key.strip()] = value.strip()
    return data


def parse_target_coverage(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data

    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line == "--------------":
            break
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue
        key, value = parts
        data[key.strip()] = value.strip()
    return data


def parse_flagstat(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data

    patterns = [
        ("reads_total", re.compile(r"^(\d+) \+ \d+ in total")),
        ("reads_mapped", re.compile(r"^(\d+) \+ \d+ mapped \(([\d.]+)%")),
        ("primary_mapped_reads", re.compile(r"^(\d+) \+ \d+ primary mapped")),
    ]

    for line in path.read_text().splitlines():
        line = line.strip()
        for key, pattern in patterns:
            match = pattern.match(line)
            if not match:
                continue
            data[key] = match.group(1)
            if key == "reads_mapped" and len(match.groups()) > 1:
                data["mapping_efficiency_pct"] = match.group(2)
    return data


def build_row(sample_dir: Path) -> dict[str, str]:
    sample = sample_dir.name
    sample_id, reference, mode = split_sample_name(sample)
    metrics_dir = sample_dir / "QC" / "validation_metrics"

    target_cov = parse_target_coverage(metrics_dir / f"{sample}.target_region_mean_coverage.tsv")
    non_target_cov = parse_key_value_file(metrics_dir / f"{sample}.non_target_mean_coverage.txt")
    target_readlen = parse_key_value_file(metrics_dir / f"{sample}.target_read_length_stats.txt")
    non_target_readlen = parse_key_value_file(metrics_dir / f"{sample}.non_target_read_length_stats.txt")
    flagstat = parse_flagstat(metrics_dir / f"{sample}.flagstat.txt")
    stats = parse_key_value_file(metrics_dir / f"{sample}.stats.txt")

    panel = target_cov.get("Panel", "")
    panel_type = Path(panel).stem if panel else ""

    row = blank_row()
    row.update(
        {
            "sample": sample,
            "sample_id": sample_id,
            "reference": reference,
            "mode": mode,
            "panel_type": panel_type,
            "target_cov_q1": target_cov.get("Q1", ""),
            "target_cov_median": target_cov.get("Median", ""),
            "target_cov_q3": target_cov.get("Q3", ""),
            "target_cov_mean": target_cov.get("Mean", ""),
            "off_target_cov_mean": non_target_cov.get("mean_non_target_coverage", ""),
            "target_readlen_q1": target_readlen.get("Q1", ""),
            "target_readlen_median": target_readlen.get("Median", ""),
            "target_readlen_q3": target_readlen.get("Q3", ""),
            "target_readlen_n50": target_readlen.get("N50", ""),
            "off_target_readlen_q1": non_target_readlen.get("Q1", ""),
            "off_target_readlen_median": non_target_readlen.get("Median", ""),
            "off_target_readlen_q3": non_target_readlen.get("Q3", ""),
            "off_target_readlen_n50": non_target_readlen.get("N50", ""),
            "reads_total": flagstat.get("reads_total", stats.get("raw total sequences", "")),
            "reads_mapped": flagstat.get("reads_mapped", stats.get("reads mapped", "")),
            "reads_unmapped": stats.get("reads unmapped", ""),
            "total_bases": stats.get("total length", ""),
            "mapping_efficiency_pct": flagstat.get("mapping_efficiency_pct", ""),
            "primary_mapped_reads": flagstat.get("primary_mapped_reads", ""),
            "error_rate": stats.get("error rate", ""),
            "average_read_length": stats.get("average length", ""),
            "maximum_read_length": stats.get("maximum length", ""),
        }
    )
    return row


def main() -> int:
    args = parse_args()
    analysis_dir = Path(args.analysis_dir)
    output_path = Path(args.output)

    if not analysis_dir.is_dir():
        print(f"ERROR: analysis dir not found: {analysis_dir}", file=sys.stderr)
        return 1

    rows: list[dict[str, str]] = []
    for sample_dir in sorted(p for p in analysis_dir.iterdir() if p.is_dir()):
        metrics_dir = sample_dir / "QC" / "validation_metrics"
        if metrics_dir.is_dir():
            rows.append(build_row(sample_dir))

    rows.sort(key=lambda row: (row["panel_type"], row["sample"]))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} samples to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
