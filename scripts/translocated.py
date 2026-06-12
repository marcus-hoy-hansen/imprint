#!/usr/bin/env python3
"""
Find candidate interchromosomal translocations from Nanopore BAM alignments.

This script uses primary/supplementary split-read evidence from ONT alignments.
It reports clusters of reads where one read maps to two different chromosomes
and the inferred breakpoints are within a configurable window on both sides.
"""

import argparse
import csv
import statistics
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple

try:
    import pysam
except ImportError as exc:  # pragma: no cover
    sys.stderr.write("pysam is required: pip install pysam\n")
    raise


@dataclass(frozen=True)
class Segment:
    chrom: str
    start: int
    end: int
    strand: str
    mapq: int
    source: str


@dataclass(frozen=True)
class Evidence:
    read_name: str
    chrom1: str
    bp1: int
    strand1: str
    chrom2: str
    bp2: int
    strand2: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect split-read supported interchromosomal translocation candidates from ONT BAM data",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--bam", required=True, help="Input BAM/CRAM path")
    parser.add_argument("--window", type=int, default=100, help="Breakpoint clustering tolerance in bp")
    parser.add_argument("--min-support", type=int, default=2, help="Minimum supporting reads per cluster")
    parser.add_argument("--min-mapq", type=int, default=20, help="Minimum MAPQ for both alignments")
    parser.add_argument("--output", help="Output TSV path (default: stdout)")
    parser.add_argument(
        "--include-read-names",
        action="store_true",
        help="Include comma-separated read names in the TSV output",
    )
    return parser.parse_args()


def alignment_end(aln: pysam.AlignedSegment) -> int:
    return aln.reference_end if aln.reference_end is not None else aln.reference_start


def segment_from_alignment(aln: pysam.AlignedSegment) -> Optional[Segment]:
    if aln.reference_name is None or aln.is_unmapped:
        return None
    return Segment(
        chrom=aln.reference_name,
        start=aln.reference_start + 1,
        end=alignment_end(aln),
        strand="-" if aln.is_reverse else "+",
        mapq=aln.mapping_quality,
        source="aln",
    )


def segment_from_sa(entry: str) -> Optional[Segment]:
    fields = entry.split(",")
    if len(fields) < 6:
        return None
    chrom = fields[0]
    try:
        pos = int(fields[1])
        strand = fields[2]
        cigar = fields[3]
        mapq = int(fields[4])
    except ValueError:
        return None
    ref_len = cigar_reference_length(cigar)
    end = pos + ref_len - 1 if ref_len > 0 else pos
    return Segment(
        chrom=chrom,
        start=pos,
        end=end,
        strand=strand,
        mapq=mapq,
        source="sa",
    )


def cigar_reference_length(cigar: str) -> int:
    total = 0
    number = []
    ref_ops = {"M", "D", "N", "=", "X"}
    for char in cigar:
        if char.isdigit():
            number.append(char)
            continue
        if not number:
            return 0
        length = int("".join(number))
        if char in ref_ops:
            total += length
        number = []
    return total


def breakpoint_for_segment(seg: Segment) -> int:
    return seg.start if seg.strand == "+" else seg.end


def canonical_pair(seg1: Segment, seg2: Segment) -> Tuple[str, int, str, str, int, str]:
    bp1 = breakpoint_for_segment(seg1)
    bp2 = breakpoint_for_segment(seg2)
    first = (seg1.chrom, bp1, seg1.strand)
    second = (seg2.chrom, bp2, seg2.strand)
    if first <= second:
        return seg1.chrom, bp1, seg1.strand, seg2.chrom, bp2, seg2.strand
    return seg2.chrom, bp2, seg2.strand, seg1.chrom, bp1, seg1.strand


def evidence_from_read(aln: pysam.AlignedSegment, min_mapq: int) -> Iterable[Evidence]:
    primary = segment_from_alignment(aln)
    if primary is None or primary.mapq < min_mapq:
        return []

    sa_tag = aln.get_tag("SA") if aln.has_tag("SA") else ""
    evidences: List[Evidence] = []
    seen = set()
    for entry in sa_tag.rstrip(";").split(";"):
        if not entry:
            continue
        seg = segment_from_sa(entry)
        if seg is None or seg.mapq < min_mapq:
            continue
        if seg.chrom == primary.chrom:
            continue
        key = canonical_pair(primary, seg)
        if key in seen:
            continue
        seen.add(key)
        evidences.append(
            Evidence(
                read_name=aln.query_name,
                chrom1=key[0],
                bp1=key[1],
                strand1=key[2],
                chrom2=key[3],
                bp2=key[4],
                strand2=key[5],
            )
        )
    return evidences


def cluster_evidence(evidence_list: List[Evidence], window: int) -> List[Dict[str, object]]:
    grouped: Dict[Tuple[str, str, str, str], List[Evidence]] = {}
    for ev in evidence_list:
        key = (ev.chrom1, ev.strand1, ev.chrom2, ev.strand2)
        grouped.setdefault(key, []).append(ev)

    clusters: List[Dict[str, object]] = []
    for key, items in grouped.items():
        items.sort(key=lambda ev: (ev.bp1, ev.bp2, ev.read_name))
        local_clusters: List[List[Evidence]] = []
        for ev in items:
            placed = False
            for cluster in local_clusters:
                bp1s = [x.bp1 for x in cluster]
                bp2s = [x.bp2 for x in cluster]
                if abs(ev.bp1 - round(statistics.mean(bp1s))) <= window and abs(ev.bp2 - round(statistics.mean(bp2s))) <= window:
                    cluster.append(ev)
                    placed = True
                    break
            if not placed:
                local_clusters.append([ev])

        for cluster in local_clusters:
            bp1_values = [ev.bp1 for ev in cluster]
            bp2_values = [ev.bp2 for ev in cluster]
            clusters.append(
                {
                    "chrom1": key[0],
                    "strand1": key[1],
                    "breakpoint1": round(statistics.mean(bp1_values)),
                    "chrom2": key[2],
                    "strand2": key[3],
                    "breakpoint2": round(statistics.mean(bp2_values)),
                    "support": len(cluster),
                    "read_names": sorted({ev.read_name for ev in cluster}),
                }
            )
    clusters.sort(key=lambda row: (-int(row["support"]), row["chrom1"], int(row["breakpoint1"]), row["chrom2"], int(row["breakpoint2"])))
    return clusters


def write_tsv(rows: List[Dict[str, object]], handle, include_read_names: bool) -> None:
    fieldnames = ["chrom1", "breakpoint1", "strand1", "chrom2", "breakpoint2", "strand2", "support"]
    if include_read_names:
        fieldnames.append("read_names")
    writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    for row in rows:
        out = dict(row)
        if include_read_names:
            out["read_names"] = ",".join(out["read_names"])
        else:
            out.pop("read_names", None)
        writer.writerow(out)


def main() -> None:
    args = parse_args()

    evidence_list: List[Evidence] = []
    with pysam.AlignmentFile(args.bam, "rb", check_sq=False) as bam:
        for aln in bam:
            if aln.is_unmapped or aln.is_secondary or aln.is_supplementary:
                continue
            evidence_list.extend(evidence_from_read(aln, args.min_mapq))

    clusters = cluster_evidence(evidence_list, args.window)
    clusters = [row for row in clusters if int(row["support"]) >= args.min_support]

    if args.output:
        with open(args.output, "w", encoding="ascii", newline="") as handle:
            write_tsv(clusters, handle, args.include_read_names)
    else:
        write_tsv(clusters, sys.stdout, args.include_read_names)


if __name__ == "__main__":
    main()
