import argparse
import csv
import gzip
from bisect import bisect_right
from pathlib import Path
from typing import TextIO

import matplotlib.pyplot as plt
import numpy as np
from scipy.stats import gaussian_kde


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chrom", default="chr12", help="Chromosome name, e.g. chr12")
    parser.add_argument("--all-chroms", action="store_true", help="Generate plots for chr1-chr22, chrX, and chrY")
    parser.add_argument("--vcf", required=True, help="Path to input .vcf.gz file")
    parser.add_argument("--bed", help="Optional BED file; only keep variants inside these intervals")
    parser.add_argument("--depth", type=int, default=10, help="Minimum depth threshold for the 3rd sample field")
    parser.add_argument("--output-dir", help="Directory for output plots; defaults to a folder next to the VCF")
    parser.add_argument("--show", action="store_true", help="Open a plot window after saving outputs")
    return parser.parse_args()


def is_snv(ref: str, alt: str) -> bool:
    return len(ref) == 1 and len(alt) == 1


def open_text_maybe_gzip(path: Path) -> TextIO:
    if path.suffix == ".gz":
        return gzip.open(path, "rt")

    with path.open("rb") as probe:
        magic = probe.read(2)

    if magic == b"\x1f\x8b":
        return gzip.open(path, "rt")

    return path.open("rt")


def merge_intervals(intervals: list[tuple[int, int]]) -> list[tuple[int, int]]:
    if not intervals:
        return []

    intervals.sort()
    merged = [intervals[0]]
    for start, end in intervals[1:]:
        last_start, last_end = merged[-1]
        if start <= last_end:
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))
    return merged


def load_bed_intervals(path: Path | None) -> dict[str, list[tuple[int, int]]]:
    if path is None:
        return {}

    intervals_by_chrom: dict[str, list[tuple[int, int]]] = {}
    with open_text_maybe_gzip(path) as handle:
        for line in handle:
            if not line.strip() or line.startswith(("#", "track", "browser")):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 3:
                continue
            chrom = fields[0]
            try:
                # BED is 0-based half-open; VCF POS is 1-based inclusive.
                start = int(fields[1]) + 1
                end = int(fields[2])
            except ValueError:
                continue
            if end < start:
                continue
            intervals_by_chrom.setdefault(chrom, []).append((start, end))

    return {chrom: merge_intervals(intervals) for chrom, intervals in intervals_by_chrom.items()}


def position_in_intervals(position: int, intervals: list[tuple[int, int]]) -> bool:
    if not intervals:
        return False

    starts = [start for start, _ in intervals]
    idx = bisect_right(starts, position) - 1
    if idx < 0:
        return False
    _, end = intervals[idx]
    return position <= end


def extract_values(
    path: Path,
    chrom: str,
    depth_threshold: int,
    bed_intervals: dict[str, list[tuple[int, int]]],
) -> list[str]:
    values: list[str] = []
    chrom_intervals = bed_intervals.get(chrom, [])

    with open_text_maybe_gzip(path) as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            if len(row) <= 1 or row[0].startswith("#"):
                continue
            if row[0] != chrom or row[6] != "PASS":
                continue
            if bed_intervals:
                try:
                    position = int(row[1])
                except ValueError:
                    continue
                if not position_in_intervals(position, chrom_intervals):
                    continue
            if not is_snv(row[3], row[4]):
                continue

            sample_fields = row[-1].split(":")
            if len(sample_fields) < 5:
                continue

            # Keep rows where the 3rd sample-field entry is >= the requested depth threshold.
            try:
                if int(sample_fields[2]) < depth_threshold:
                    continue
            except ValueError:
                continue

            values.append(sample_fields[4])

    return values


def get_filebase(path: Path) -> str:
    name = path.name
    if name.endswith(".vcf.gz"):
        return name[:-7]
    return path.stem


def chromosome_list(all_chroms: bool, chrom: str) -> list[str]:
    if all_chroms:
        return [f"chr{i}" for i in range(1, 23)] + ["chrX", "chrY"]
    return [chrom]


def label_suffix(path: Path | None) -> str:
    if path is None:
        return ""
    return f" | BED: {get_filebase(path)}"


def make_plot(
    values: list[str],
    chrom: str,
    filebase: str,
    bed_label: str,
    depth_threshold: int,
    output_stem: Path,
    show_plot: bool,
) -> None:
    if not values:
        raise ValueError(f"No values found for {chrom}")

    numeric_values: list[float] = []
    for value in values:
        try:
            numeric_values.append(float(value))
        except ValueError:
            continue

    if not numeric_values:
        raise ValueError(f"No numeric 5th sample-field values found for {chrom}")

    vaf_values = [value for value in numeric_values if 0.0 <= value <= 1.0]
    if not vaf_values:
        raise ValueError(f"No numeric 0-1 VAF values found for {chrom}")

    fig, ax = plt.subplots(figsize=(14, 4))
    x_positions = np.arange(1, len(vaf_values) + 1)
    ax.scatter(x_positions, vaf_values, color="red", alpha=0.2, s=10, edgecolors="none")
    ax.set_xlabel("Variant index", color="red")
    ax.tick_params(axis="x", colors="red")
    ax.spines["bottom"].set_color("red")
    ax.set_ylabel("VAF (Variant allele frequency)", color="red")
    ax.tick_params(axis="y", colors="red")
    ax.spines["left"].set_color("red")
    ax.set_ylim(0, 1)

    density_data = np.array(vaf_values[799:] if len(vaf_values) > 800 else vaf_values, dtype=float)
    ax2 = ax.twinx()
    xs = np.linspace(0, 1, 500)

    if len(density_data) > 1 and density_data.min() != density_data.max():
        std = density_data.std(ddof=1)
        bw = 0.04 / std if std else None
        kde = gaussian_kde(density_data, bw_method=bw)
        ys = kde(xs)
    else:
        ys = np.zeros_like(xs)

    density_x = np.interp(xs, [0, 1], [1, max(len(vaf_values), 1)])
    ax2.plot(density_x, ys, color="black", alpha=0.8, linewidth=2)
    ax2.fill_between(density_x, ys, color="black", alpha=0.15)
    ax2.set_ylabel("VAF density distribution", color="black")
    ax2.tick_params(axis="y", colors="black")
    ax2.spines["right"].set_color("black")

    top_ax = ax.twiny()
    top_ax.set_xlim(0, 1)
    top_ax.set_xlabel("Variant allele frequency", labelpad=8)
    top_ax.xaxis.set_label_position("top")
    top_ax.xaxis.tick_top()

    ax.set_title(
        f"{filebase}: {chrom} PASS SNVs, depth >= {depth_threshold}{bed_label}",
        fontweight="bold",
        pad=28,
    )
    plt.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(f"{output_stem}.png", dpi=300, bbox_inches="tight")
    fig.savefig(f"{output_stem}.pdf", bbox_inches="tight")

    if show_plot:
        plt.show()
    plt.close(fig)


def main() -> None:
    args = parse_args()
    vcf_path = Path(args.vcf)
    bed_path = Path(args.bed) if args.bed else None
    filebase = get_filebase(vcf_path)
    bedbase = get_filebase(bed_path) if bed_path else None
    output_dir = Path(args.output_dir) if args.output_dir else vcf_path.parent / f"{filebase}_variant_panel"
    output_dir.mkdir(parents=True, exist_ok=True)
    bed_intervals = load_bed_intervals(bed_path)
    bed_label = label_suffix(bed_path)

    for chrom in chromosome_list(args.all_chroms, args.chrom):
        stem_name = f"{filebase}_{chrom}_variant_panel"
        if bedbase:
            stem_name = f"{stem_name}_{bedbase}"
        output_stem = output_dir / stem_name
        values = extract_values(vcf_path, chrom, args.depth, bed_intervals)
        if not values:
            continue
        make_plot(values, chrom, filebase, bed_label, args.depth, output_stem, show_plot=args.show)


if __name__ == "__main__":
    main()
