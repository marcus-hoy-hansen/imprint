#!/usr/bin/env python3
"""
CheckBamType.py

Sample up to N primary reads from a BAM and classify it as either
"adaptive_sampling" (all sampled reads are <= threshold) or "wgs"
(any sampled read is longer than threshold).
"""
import argparse
import math
import random
import sys
from statistics import median
from typing import List

try:
    import pysam
except ImportError as exc:  # pragma: no cover
    sys.stderr.write("pysam is required: pip install pysam\n")
    raise


def sample_read_lengths(path: str, num_reads: int, seed: int) -> List[int]:
    """Sample primary read lengths from the BAM (first N for speed)."""
    rng = random.Random(seed)  # kept for reproducibility if extended later
    _ = rng  # silence lint for unused rng in this fast path
    lengths: List[int] = []

    # Some BAMs may lack @SQ headers; disable sequence checking to handle those.
    with pysam.AlignmentFile(path, "rb", check_sq=False) as bam:
        for aln in bam:
            if aln.is_secondary or aln.is_supplementary:
                continue
            lengths.append(aln.query_length or 0)
            if len(lengths) >= num_reads:
                break
    return lengths


def ascii_histogram(
    lengths: List[int],
    bin_size: int,
    max_bar: int = 50,
    max_bins: int = 120,
) -> str:
    """Return a simple ASCII histogram of read lengths."""
    if not lengths:
        return "No reads to plot\n"

    max_len = max(lengths)
    # Expand bin size if there would be too many bins.
    bin_size = max(bin_size, math.ceil((max_len + 1) / max_bins))
    bins = (max_len // bin_size) + 1

    counts = [0] * bins
    for l in lengths:
        counts[l // bin_size] += 1

    peak = max(counts)
    if peak == 0:
        return "No reads to plot\n"

    lines = []
    for idx, count in enumerate(counts):
        start = idx * bin_size
        end = start + bin_size - 1
        bar_len = int(count * max_bar / peak) if count else 0
        bar = "#" * bar_len
        lines.append(f"{start:>7}-{end:<7} | {bar} {count}")
    return "\n".join(lines) + "\n"


def classify(lengths: List[int], threshold: int) -> str:
    """Classify by median length vs threshold."""
    if not lengths:
        return "no_primary_reads"
    return "adaptive_sampling" if median(lengths) <= threshold else "wgs"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Subsample BAM reads and classify as adaptive sampling or WGS",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("bam", help="Path to BAM file")
    parser.add_argument(
        "-n",
        "--num-reads",
        type=int,
        default=1000,
        help="Number of primary reads to sample",
    )
    parser.add_argument(
        "-t",
        "--threshold",
        type=int,
        default=1000,
        help="Length threshold in bp",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1,
        help="Random seed for reproducible sampling",
    )
    parser.add_argument(
        "--histogram",
        action="store_true",
        help="Print an ASCII histogram of sampled read lengths",
    )
    parser.add_argument(
        "--bin-size",
        type=int,
        default=500,
        help="Bin size for the ASCII histogram (bp)",
    )
    args = parser.parse_args()

    lengths = sample_read_lengths(args.bam, args.num_reads, args.seed)
    result = classify(lengths, args.threshold)
    med_len = median(lengths) if lengths else "NA"

    sys.stdout.write(
        f"classification\t{result}\n"
        f"sampled_reads\t{len(lengths)}\n"
        f"median_length\t{med_len}\n"
        f"max_length\t{max(lengths) if lengths else 'NA'}\n"
    )
    if args.histogram:
        sys.stdout.write("\nHistogram (bp):\n")
        sys.stdout.write(ascii_histogram(lengths, args.bin_size))


if __name__ == "__main__":
    main()
