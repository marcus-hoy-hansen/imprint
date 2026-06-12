#!/usr/bin/env python3
"""
Keep only reciprocal Sniffles BND breakends from stdin or a Sniffles VCF.

Examples:
  zcat sample_sniffles2.vcf.gz | grep BND | python3 scripts/filter_reciprocal_bnd.py
  python3 scripts/filter_reciprocal_bnd.py sample_sniffles2.vcf.gz
  python3 scripts/filter_reciprocal_bnd.py sample --unique-pairs
  python3 scripts/filter_reciprocal_bnd.py sample --window-bp 1000
"""

import argparse
import gzip
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple


BREAKEND_RE = re.compile(r"[\[\]]([^:\[\]]+):(\d+)[\[\]]")


@dataclass(frozen=True)
class BndRecord:
    chrom: str
    pos: int
    partner_chrom: str
    partner_pos: int
    line: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter Sniffles BND records to those with a reciprocal breakend present."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="-",
        help="Sniffles VCF/VCF.GZ path, sample prefix, or '-' for stdin",
    )
    parser.add_argument(
        "--unique-pairs",
        action="store_true",
        help="Output one canonical breakpoint pair per reciprocal event",
    )
    parser.add_argument(
        "--window-bp",
        type=int,
        default=0,
        help="Allow reciprocal mate positions to differ by up to this many bp",
    )
    return parser.parse_args()


def resolve_input_path(raw_path: str) -> str:
    if raw_path == "-":
        return raw_path
    if os.path.exists(raw_path):
        return raw_path
    sniffles2_path = f"{raw_path}_sniffles2.vcf.gz"
    if os.path.exists(sniffles2_path):
        return sniffles2_path
    raise FileNotFoundError(f"Input not found: {raw_path} or {sniffles2_path}")


def open_input(path: str):
    if path == "-":
        return sys.stdin
    if path.endswith(".gz"):
        return gzip.open(path, "rt")
    return open(path, "rt", encoding="utf-8")


def parse_bnd_line(line: str) -> Optional[BndRecord]:
    if not line or line.startswith("#"):
        return None
    fields = line.rstrip("\n").split("\t")
    if len(fields) < 5:
        return None

    chrom, pos_str, _, _, alt = fields[:5]
    if "SVTYPE=BND" not in line and "[" not in alt and "]" not in alt:
        return None

    match = BREAKEND_RE.search(alt)
    if match is None:
        return None

    try:
        pos = int(pos_str)
        partner_pos = int(match.group(2))
    except ValueError:
        return None

    return BndRecord(
        chrom=chrom,
        pos=pos,
        partner_chrom=match.group(1),
        partner_pos=partner_pos,
        line=line.rstrip("\n"),
    )


def load_records(handle: Iterable[str]) -> List[BndRecord]:
    records: List[BndRecord] = []
    for line in handle:
        record = parse_bnd_line(line)
        if record is not None:
            records.append(record)
    return records


def canonical_pair(record: BndRecord) -> Tuple[str, int, str, int]:
    left = (record.chrom, record.pos)
    right = (record.partner_chrom, record.partner_pos)
    if left <= right:
        return record.chrom, record.pos, record.partner_chrom, record.partner_pos
    return record.partner_chrom, record.partner_pos, record.chrom, record.pos


def reciprocal_counts(records: List[BndRecord]) -> Dict[Tuple[str, int, str, int], int]:
    counts: Dict[Tuple[str, int, str, int], int] = {}
    for record in records:
        key = (record.chrom, record.pos, record.partner_chrom, record.partner_pos)
        counts[key] = counts.get(key, 0) + 1
    return counts


def has_reciprocal_match(record: BndRecord, records: List[BndRecord], window_bp: int) -> bool:
    for candidate in records:
        if candidate.chrom != record.partner_chrom:
            continue
        if candidate.partner_chrom != record.chrom:
            continue
        if abs(candidate.pos - record.partner_pos) > window_bp:
            continue
        if abs(candidate.partner_pos - record.pos) > window_bp:
            continue
        return True
    return False


def matching_reverse_count(record: BndRecord, records: List[BndRecord], window_bp: int) -> int:
    count = 0
    for candidate in records:
        if candidate.chrom != record.partner_chrom:
            continue
        if candidate.partner_chrom != record.chrom:
            continue
        if abs(candidate.pos - record.partner_pos) > window_bp:
            continue
        if abs(candidate.partner_pos - record.pos) > window_bp:
            continue
        count += 1
    return count


def write_matching_records(records: List[BndRecord], window_bp: int) -> None:
    for record in records:
        if has_reciprocal_match(record, records, window_bp):
            print(record.line)


def write_unique_pairs(records: List[BndRecord], window_bp: int) -> None:
    counts = reciprocal_counts(records)
    seen = set()
    for record in records:
        if not has_reciprocal_match(record, records, window_bp):
            continue
        pair = canonical_pair(record)
        if pair in seen:
            continue
        seen.add(pair)
        forward = counts.get((record.chrom, record.pos, record.partner_chrom, record.partner_pos), 0)
        reverse = matching_reverse_count(record, records, window_bp)
        print(*pair, forward, reverse, sep="\t")


def main() -> int:
    args = parse_args()
    input_path = resolve_input_path(args.input)
    with open_input(input_path) as handle:
        records = load_records(handle)

    if args.unique_pairs:
        write_unique_pairs(records, args.window_bp)
    else:
        write_matching_records(records, args.window_bp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
