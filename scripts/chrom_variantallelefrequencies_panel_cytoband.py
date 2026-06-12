import argparse
import csv
import gzip
from bisect import bisect_right
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

import matplotlib.pyplot as plt
import numpy as np
from matplotlib import gridspec
from scipy.stats import gaussian_kde


@dataclass(frozen=True)
class BedInterval:
    chrom: str
    start: int
    end: int
    name: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chrom", default="chr12", help="Chromosome name, e.g. chr12")
    parser.add_argument("--all-chroms", action="store_true", help="Generate plots for chr1-chr22, chrX, and chrY")
    parser.add_argument("--vcf", required=True, help="Path to input .vcf.gz file")
    parser.add_argument("--bed", help="Optional BED file; only keep variants inside these intervals")
    parser.add_argument(
        "--bed-layout",
        choices=("full", "target"),
        default="full",
        help="With --bed, keep full chromosome coordinates or compress to concatenated target intervals",
    )
    parser.add_argument(
        "--x-axis-mode",
        choices=("position", "index"),
        default="position",
        help="Plot variants by genomic position or by variant index",
    )
    parser.add_argument(
        "--cytoband-mode",
        choices=("collapsed", "uncollapsed"),
        default="collapsed",
        help="Assign one cytoband per target interval or split targets at cytoband boundaries",
    )
    parser.add_argument("--cytoband", required=True, help="Path to UCSC-style cytoBand.txt file")
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


def merge_named_intervals(intervals: list[BedInterval]) -> list[BedInterval]:
    if not intervals:
        return []

    intervals = sorted(intervals, key=lambda item: (item.start, item.end, item.name))
    merged = [intervals[0]]
    for current in intervals[1:]:
        last = merged[-1]
        if current.start <= last.end:
            merged_name = last.name if last.name == current.name else f"{last.name},{current.name}"
            merged[-1] = BedInterval(last.chrom, last.start, max(last.end, current.end), merged_name)
        else:
            merged.append(current)
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
                start = int(fields[1]) + 1
                end = int(fields[2])
            except ValueError:
                continue
            if end < start:
                continue
            intervals_by_chrom.setdefault(chrom, []).append((start, end))

    return {chrom: merge_intervals(intervals) for chrom, intervals in intervals_by_chrom.items()}


def load_bed_records(path: Path | None) -> dict[str, list[BedInterval]]:
    if path is None:
        return {}

    intervals_by_chrom: dict[str, list[BedInterval]] = {}
    with open_text_maybe_gzip(path) as handle:
        for line in handle:
            if not line.strip() or line.startswith(("#", "track", "browser")):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 3:
                continue
            chrom = fields[0]
            try:
                start = int(fields[1]) + 1
                end = int(fields[2])
            except ValueError:
                continue
            if end < start:
                continue
            name = fields[3] if len(fields) > 3 and fields[3] else f"{chrom}:{start}-{end}"
            intervals_by_chrom.setdefault(chrom, []).append(BedInterval(chrom, start, end, name))

    return {chrom: merge_named_intervals(intervals) for chrom, intervals in intervals_by_chrom.items()}


def position_in_intervals(position: int, intervals: list[tuple[int, int]]) -> bool:
    if not intervals:
        return False

    starts = [start for start, _ in intervals]
    idx = bisect_right(starts, position) - 1
    if idx < 0:
        return False
    _, end = intervals[idx]
    return position <= end


def load_cytobands(path: Path) -> dict[str, list[tuple[int, int, str, str]]]:
    bands_by_chrom: dict[str, list[tuple[int, int, str, str]]] = {}
    with path.open("rt", encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            if len(row) < 5:
                continue
            chrom = row[0]
            try:
                start = int(row[1])
                end = int(row[2])
            except ValueError:
                continue
            bands_by_chrom.setdefault(chrom, []).append((start, end, row[3], row[4]))
    return bands_by_chrom


def extract_variants(
    path: Path,
    chrom: str,
    depth_threshold: int,
    bed_intervals: dict[str, list[tuple[int, int]]],
) -> list[tuple[int, float]]:
    variants: list[tuple[int, float]] = []
    chrom_intervals = bed_intervals.get(chrom, [])

    with open_text_maybe_gzip(path) as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            if len(row) <= 1 or row[0].startswith("#"):
                continue
            if row[0] != chrom or row[6] != "PASS":
                continue
            try:
                position = int(row[1])
            except ValueError:
                continue
            if bed_intervals and not position_in_intervals(position, chrom_intervals):
                continue
            if not is_snv(row[3], row[4]):
                continue

            sample_fields = row[-1].split(":")
            if len(sample_fields) < 5:
                continue

            try:
                if int(sample_fields[2]) < depth_threshold:
                    continue
                vaf = float(sample_fields[4])
            except ValueError:
                continue
            if 0.0 <= vaf <= 1.0:
                variants.append((position, vaf))

    return variants


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


def layout_suffix(layout: str, bed_path: Path | None) -> str:
    if bed_path is None or layout == "full":
        return ""
    return f" | layout: {layout}"


def cytoband_color(stain: str) -> tuple[str, str]:
    gpos_map = {
        "gneg": "#ffffff",
        "gpos25": "#d9d9d9",
        "gpos50": "#a6a6a6",
        "gpos75": "#737373",
        "gpos100": "#262626",
        "gvar": "#c9b08f",
        "stalk": "#9ecae1",
        "acen": "#c44e52",
    }
    face = gpos_map.get(stain, "#dddddd")
    edge = "#444444" if stain != "acen" else "#8b1e24"
    return face, edge


def plot_cytobands(ax: plt.Axes, bands: list[tuple[int, int, str, str]], chrom_end: int) -> None:
    label_min_width = max(chrom_end * 0.035, 4_000_000)
    for start, end, band_name, stain in bands:
        width = end - start
        face, edge = cytoband_color(stain)
        ax.bar(
            x=start + width / 2,
            height=1.0,
            width=width,
            bottom=0,
            color=face,
            edgecolor=edge,
            linewidth=0.6,
            align="center",
        )
        if width >= label_min_width:
            text_color = "white" if stain in {"gpos75", "gpos100"} else "black"
            ax.text(
                start + width / 2,
                0.5,
                band_name,
                ha="center",
                va="center",
                fontsize=7,
                color=text_color,
                rotation=90,
                clip_on=True,
            )

    ax.set_xlim(0, chrom_end)
    ax.set_ylim(0, 1)
    ax.set_yticks([])
    ax.set_xlabel("Genomic position (Mb)")
    ax.tick_params(axis="x", labelsize=9)
    ax.spines["left"].set_visible(False)
    ax.spines["right"].set_visible(False)


def band_for_position(position: int, cytobands: list[tuple[int, int, str, str]]) -> tuple[str, str]:
    for start, end, band_name, stain in cytobands:
        if start <= position <= end:
            return band_name, stain
    return "NA", "gneg"


def build_target_layout(
    intervals: list[BedInterval],
    cytobands: list[tuple[int, int, str, str]],
    gap_bp: int = 50_000,
) -> tuple[list[dict[str, object]], dict[int, float], float]:
    layout: list[dict[str, object]] = []
    position_map: dict[int, float] = {}
    offset = 0.0

    for idx, interval in enumerate(intervals):
        width = interval.end - interval.start + 1
        band_name, stain = band_for_position((interval.start + interval.end) // 2, cytobands)
        projected_start = offset
        projected_end = offset + width
        layout.append(
            {
                "interval": interval,
                "projected_start": projected_start,
                "projected_end": projected_end,
                "band_name": band_name,
                "stain": stain,
                "index": idx,
            }
        )
        for pos in range(interval.start, interval.end + 1):
            position_map[pos] = projected_start + (pos - interval.start)
        offset = projected_end + gap_bp

    total_width = offset - gap_bp if layout else 0.0
    return layout, position_map, total_width


def project_variants_to_targets(
    variants: list[tuple[int, float]],
    layout: list[dict[str, object]],
) -> tuple[np.ndarray, np.ndarray]:
    projected_positions: list[float] = []
    projected_vafs: list[float] = []

    for position, vaf in variants:
        for item in layout:
            interval = item["interval"]
            if interval.start <= position <= interval.end:
                projected_positions.append(item["projected_start"] + (position - interval.start))
                projected_vafs.append(vaf)
                break

    return np.array(projected_positions, dtype=float), np.array(projected_vafs, dtype=float)


def plot_target_intervals(ax: plt.Axes, layout: list[dict[str, object]], total_width: float) -> None:
    for item in layout:
        interval = item["interval"]
        start = item["projected_start"]
        end = item["projected_end"]
        width = end - start
        face, edge = cytoband_color(item["stain"])
        ax.bar(
            x=start + width / 2,
            height=1.0,
            width=width,
            bottom=0,
            color=face,
            edgecolor=edge,
            linewidth=0.6,
            align="center",
        )
        if item["index"] % 2 == 1:
            ax.axvspan(start, end, color="#000000", alpha=0.03, linewidth=0)
        if width >= max(total_width * 0.025, 90_000):
            text_color = "white" if item["stain"] in {"gpos75", "gpos100"} else "black"
            label = f"{item['band_name']}\n{interval.name.split(',')[0]}"
            ax.text(
                start + width / 2,
                0.5,
                label,
                ha="center",
                va="center",
                fontsize=6.5,
                color=text_color,
                rotation=90,
                clip_on=True,
            )

    ax.set_xlim(0, total_width)
    ax.set_ylim(0, 1)
    ax.set_yticks([])
    ax.set_xlabel("Concatenated target regions (Mb)")
    ax.tick_params(axis="x", labelsize=9)
    ax.spines["left"].set_visible(False)
    ax.spines["right"].set_visible(False)


def build_index_layout(
    variants: list[tuple[int, float]],
    bed_records: list[BedInterval],
    cytobands: list[tuple[int, int, str, str]],
    cytoband_mode: str,
) -> tuple[np.ndarray, np.ndarray, list[dict[str, object]]]:
    positions = np.array([position for position, _ in variants], dtype=float)
    vafs = np.array([vaf for _, vaf in variants], dtype=float)
    x_index = np.arange(1, len(variants) + 1, dtype=float)
    layout: list[dict[str, object]] = []

    if len(variants) == 0:
        return x_index, vafs, layout

    source_intervals: list[tuple[BedInterval, str, str, int]] = []
    for idx, interval in enumerate(bed_records):
        if cytoband_mode == "uncollapsed":
            for band_start, band_end, band_name, stain in cytobands:
                overlap_start = max(interval.start, band_start)
                overlap_end = min(interval.end, band_end)
                if overlap_end < overlap_start:
                    continue
                source_intervals.append(
                    (BedInterval(interval.chrom, overlap_start, overlap_end, interval.name), band_name, stain, idx)
                )
        else:
            band_name, stain = band_for_position((interval.start + interval.end) // 2, cytobands)
            source_intervals.append((interval, band_name, stain, idx))

    for interval, band_name, stain, idx in source_intervals:
        hits = np.where((positions >= interval.start) & (positions <= interval.end))[0]
        if len(hits) == 0:
            continue
        layout.append(
            {
                "interval": interval,
                "projected_start": float(hits[0] + 1),
                "projected_end": float(hits[-1] + 1),
                "band_name": band_name,
                "stain": stain,
                "index": idx,
            }
        )

    return x_index, vafs, layout


def build_index_cytoband_layout(
    variants: list[tuple[int, float]],
    cytobands: list[tuple[int, int, str, str]],
) -> tuple[np.ndarray, np.ndarray, list[dict[str, object]]]:
    positions = np.array([position for position, _ in variants], dtype=float)
    vafs = np.array([vaf for _, vaf in variants], dtype=float)
    x_index = np.arange(1, len(variants) + 1, dtype=float)
    layout: list[dict[str, object]] = []

    if len(variants) == 0:
        return x_index, vafs, layout

    for idx, (band_start, band_end, band_name, stain) in enumerate(cytobands):
        hits = np.where((positions >= band_start) & (positions <= band_end))[0]
        if len(hits) == 0:
            continue
        layout.append(
            {
                "interval": BedInterval("band", int(band_start), int(band_end), band_name),
                "projected_start": float(hits[0] + 1),
                "projected_end": float(hits[-1] + 1),
                "band_name": band_name,
                "stain": stain,
                "index": idx,
            }
        )

    return x_index, vafs, layout


def add_target_top_axis(ax: plt.Axes, layout: list[dict[str, object]], total_width: float, chrom: str) -> None:
    top_ax = ax.twiny()
    top_ax.set_xlim(0, total_width)
    top_ax.set_xticks([])
    top_ax.set_xlabel(f"{chrom} cytobands across target BED", labelpad=42)
    top_ax.xaxis.set_label_position("top")
    top_ax.xaxis.tick_top()

    band_items: list[tuple[float, str]] = []
    seen_bands = set()
    for item in layout:
        band_name = item["band_name"]
        if band_name in seen_bands:
            continue
        start = item["projected_start"]
        end = item["projected_end"]
        band_items.append(((start + end) / 2, band_name))
        seen_bands.add(band_name)

    min_spacing = max(total_width * 0.035, 250_000)
    row_last_x = [-float("inf")] * 5
    row_y = [1.04, 1.11, 1.18, 1.25, 1.32]

    for x_pos, label in band_items:
        row_idx = 0
        for idx, last_x in enumerate(row_last_x):
            if x_pos - last_x >= min_spacing:
                row_idx = idx
                break
        else:
            row_idx = int(np.argmin(row_last_x))

        row_last_x[row_idx] = x_pos
        y_text = row_y[row_idx]
        ax.plot(
            [x_pos, x_pos],
            [1.0, y_text - 0.016],
            transform=ax.get_xaxis_transform(),
            color="#666666",
            linewidth=0.6,
            clip_on=False,
        )
        ax.text(
            x_pos,
            y_text,
            label,
            transform=ax.get_xaxis_transform(),
            ha="center",
            va="bottom",
            fontsize=8,
            color="#222222",
            clip_on=False,
        )


def add_index_top_axis(ax: plt.Axes, layout: list[dict[str, object]], total_width: float, chrom: str) -> None:
    top_ax = ax.twiny()
    top_ax.set_xlim(1, total_width)
    top_ax.set_xticks([])
    top_ax.set_xlabel(f"{chrom} cytobands across target BED", labelpad=72)
    top_ax.xaxis.set_label_position("top")
    top_ax.xaxis.tick_top()

    min_spacing = max(total_width * 0.045, 120)
    row_last_x = [-float("inf")] * 4
    row_y = [1.03, 1.10, 1.17, 1.24]
    seen_bands = set()

    for item in layout:
        band_name = item["band_name"]
        if band_name in seen_bands:
            continue
        seen_bands.add(band_name)
        x_pos = (item["projected_start"] + item["projected_end"]) / 2
        row_idx = 0
        for idx, last_x in enumerate(row_last_x):
            if x_pos - last_x >= min_spacing:
                row_idx = idx
                break
        else:
            row_idx = int(np.argmin(row_last_x))

        row_last_x[row_idx] = x_pos
        y_text = row_y[row_idx]
        ax.plot(
            [x_pos, x_pos],
            [1.0, y_text - 0.016],
            transform=ax.get_xaxis_transform(),
            color="#666666",
            linewidth=0.6,
            clip_on=False,
        )
        ax.text(
            x_pos,
            y_text,
            band_name,
            transform=ax.get_xaxis_transform(),
            ha="center",
            va="bottom",
            fontsize=8,
            color="#222222",
            clip_on=False,
        )


def add_absolute_mb_axis(ax: plt.Axes, variants: list[tuple[int, float]]) -> None:
    if not variants:
        return
    positions = np.array([position for position, _ in variants], dtype=float)
    x_index = np.arange(1, len(variants) + 1, dtype=float)
    major_mb_ticks = np.arange(20_000_000, (positions.max() // 20_000_000 + 2) * 20_000_000, 20_000_000, dtype=float)
    minor_mb_ticks = np.arange(10_000_000, (positions.max() // 10_000_000 + 2) * 10_000_000, 10_000_000, dtype=float)
    major_tick_positions = np.interp(major_mb_ticks, positions, x_index, left=np.nan, right=np.nan)
    minor_tick_positions = np.interp(minor_mb_ticks, positions, x_index, left=np.nan, right=np.nan)

    major_valid = ~np.isnan(major_tick_positions)
    minor_valid = ~np.isnan(minor_tick_positions)
    major_tick_positions = major_tick_positions[major_valid]
    major_tick_labels = [f"{tick / 1_000_000:.0f}" for tick in major_mb_ticks[major_valid]]
    minor_tick_positions = minor_tick_positions[minor_valid]
    ax.set_xticks([])
    ax.set_xlabel("Approximate genomic position (Mb anchors)", labelpad=28)

    for x_pos in minor_tick_positions:
        ax.plot(
            [x_pos, x_pos],
            [0.0, -0.035],
            transform=ax.get_xaxis_transform(),
            color="#999999",
            linewidth=0.5,
            clip_on=False,
        )

    for x_pos, label in zip(major_tick_positions, major_tick_labels):
        ax.plot(
            [x_pos, x_pos],
            [0.0, -0.06],
            transform=ax.get_xaxis_transform(),
            color="#666666",
            linewidth=0.6,
            clip_on=False,
        )
        ax.text(
            x_pos,
            -0.11,
            label,
            transform=ax.get_xaxis_transform(),
            ha="center",
            va="top",
            fontsize=8,
            color="#222222",
            clip_on=False,
        )


def draw_bed_coverage_track(ax: plt.Axes, layout: list[dict[str, object]], y_axes: float = 0.985) -> None:
    for item in layout:
        ax.plot(
            [item["projected_start"], item["projected_end"]],
            [y_axes, y_axes],
            transform=ax.get_xaxis_transform(),
            color="#1f4f99",
            linewidth=1.0,
            solid_capstyle="butt",
            clip_on=False,
            zorder=4,
        )


def make_plot(
    variants: list[tuple[int, float]],
    chrom: str,
    filebase: str,
    bed_label: str,
    layout_label: str,
    depth_threshold: int,
    output_stem: Path,
    show_plot: bool,
    cytobands: list[tuple[int, int, str, str]],
    bed_records: list[BedInterval],
    bed_layout: str,
    x_axis_mode: str,
    cytoband_mode: str,
) -> None:
    if not variants:
        raise ValueError(f"No values found for {chrom}")
    if not cytobands:
        raise ValueError(f"No cytobands found for {chrom}")

    chrom_end = max(end for _, end, _, _ in cytobands)
    using_target_layout = bed_layout == "target" and bool(bed_records)
    using_index_mode = x_axis_mode == "index"

    if using_target_layout:
        target_layout, _, plot_end = build_target_layout(bed_records, cytobands)
        positions, vaf_values = project_variants_to_targets(variants, target_layout)
    elif using_index_mode:
        if bed_records:
            positions, vaf_values, target_layout = build_index_layout(variants, bed_records, cytobands, cytoband_mode)
        else:
            positions, vaf_values, target_layout = build_index_cytoband_layout(variants, cytobands)
        plot_end = float(len(variants))
    else:
        target_layout = []
        plot_end = float(chrom_end)
        positions = np.array([position for position, _ in variants], dtype=float)
        vaf_values = np.array([vaf for _, vaf in variants], dtype=float)

    fig = plt.figure(figsize=(20.8, 7.9))
    gs = gridspec.GridSpec(
        2,
        2,
        figure=fig,
        width_ratios=[18, 3],
        height_ratios=[12, 1.4],
        wspace=0.06,
        hspace=0.12,
    )

    ax = fig.add_subplot(gs[0, 0])
    density_ax = fig.add_subplot(gs[0, 1], sharey=ax)
    band_ax = fig.add_subplot(gs[1, 0], sharex=ax)

    ax.scatter(positions, vaf_values, color="red", alpha=0.22, s=16, edgecolors="none")
    ax.set_ylabel("VAF (Variant allele frequency)", color="red")
    ax.tick_params(axis="y", colors="red")
    ax.spines["left"].set_color("red")
    ax.set_ylim(0, 1)
    ax.set_xlim(0, plot_end)
    ax.grid(axis="y", color="#d9d9d9", linewidth=0.6, alpha=0.7)
    ax.tick_params(axis="x", labelbottom=False)

    if using_target_layout or (using_index_mode and bed_records):
        draw_bed_coverage_track(ax, target_layout)

    if using_target_layout:
        add_target_top_axis(ax, target_layout, plot_end, chrom)
    elif using_index_mode:
        add_index_top_axis(ax, target_layout, plot_end, chrom)
    else:
        top_ax = ax.twiny()
        top_ax.set_xlim(0, chrom_end)
        tick_positions = [(start + end) / 2 for start, end, band_name, _ in cytobands if (end - start) >= max(chrom_end * 0.06, 6_000_000)]
        tick_labels = [band_name for start, end, band_name, _ in cytobands if (end - start) >= max(chrom_end * 0.06, 6_000_000)]
        top_ax.set_xticks(tick_positions)
        top_ax.set_xticklabels(tick_labels, fontsize=8)
        top_ax.set_xlabel(f"{chrom} cytobands", labelpad=8)
        top_ax.xaxis.set_label_position("top")
        top_ax.xaxis.tick_top()

    density_data = np.array(vaf_values[799:] if len(vaf_values) > 800 else vaf_values, dtype=float)
    ys = np.linspace(0, 1, 500)
    if len(density_data) > 1 and density_data.min() != density_data.max():
        std = density_data.std(ddof=1)
        bw = 0.04 / std if std else None
        kde = gaussian_kde(density_data, bw_method=bw)
        xs = kde(ys)
    else:
        xs = np.zeros_like(ys)

    density_ax.plot(xs, ys, color="#222222", linewidth=2)
    density_ax.fill_betweenx(ys, 0, xs, color="#222222", alpha=0.15)
    density_ax.set_xlabel("Density")
    density_ax.tick_params(axis="y", left=False, labelleft=False)
    density_ax.spines["left"].set_visible(False)
    density_ax.set_ylim(0, 1)

    if using_target_layout:
        plot_target_intervals(band_ax, target_layout, plot_end)
    elif using_index_mode:
        plot_target_intervals(band_ax, target_layout, plot_end)
        add_absolute_mb_axis(band_ax, variants)
    else:
        plot_cytobands(band_ax, cytobands, chrom_end)
    if using_target_layout:
        band_ax.set_xticks(ax.get_xticks())
        band_ax.set_xticklabels([f"{tick / 1_000_000:.1f}" for tick in ax.get_xticks()])

    fig.suptitle(
        f"{filebase}: {chrom} PASS SNVs, depth >= {depth_threshold}{bed_label}{layout_label}",
        fontweight="bold",
        y=0.998,
        fontsize=17,
    )
    fig.subplots_adjust(top=0.73, bottom=0.25)
    fig.savefig(f"{output_stem}.png", dpi=300, bbox_inches="tight")
    fig.savefig(f"{output_stem}.pdf", bbox_inches="tight")

    if show_plot:
        plt.show()
    plt.close(fig)


def main() -> None:
    args = parse_args()
    vcf_path = Path(args.vcf)
    bed_path = Path(args.bed) if args.bed else None
    cytoband_path = Path(args.cytoband)
    filebase = get_filebase(vcf_path)
    bedbase = get_filebase(bed_path) if bed_path else None
    output_dir = Path(args.output_dir) if args.output_dir else vcf_path.parent / f"{filebase}_variant_panel_cytoband"
    output_dir.mkdir(parents=True, exist_ok=True)
    bed_intervals = load_bed_intervals(bed_path)
    bed_records_by_chrom = load_bed_records(bed_path)
    bed_label = label_suffix(bed_path)
    layout_label = layout_suffix(args.bed_layout, bed_path)
    cytobands_by_chrom = load_cytobands(cytoband_path)

    for chrom in chromosome_list(args.all_chroms, args.chrom):
        stem_name = f"{filebase}_{chrom}_variant_panel_cytoband"
        if bedbase:
            stem_name = f"{stem_name}_{bedbase}"
        if bedbase and args.bed_layout == "target":
            stem_name = f"{stem_name}_target"
        if args.x_axis_mode == "index":
            stem_name = f"{stem_name}_index"
        stem_name = f"{stem_name}_{args.cytoband_mode}"
        output_stem = output_dir / stem_name
        # In index mode, keep the original chr-wide variant density and use BED only as annotation/coverage context.
        active_bed_intervals = {} if args.x_axis_mode == "index" else bed_intervals
        variants = extract_variants(vcf_path, chrom, args.depth, active_bed_intervals)
        if not variants:
            continue
        make_plot(
            variants,
            chrom,
            filebase,
            bed_label,
            layout_label,
            args.depth,
            output_stem,
            show_plot=args.show,
            cytobands=cytobands_by_chrom.get(chrom, []),
            bed_records=bed_records_by_chrom.get(chrom, []),
            bed_layout=args.bed_layout,
            x_axis_mode=args.x_axis_mode,
            cytoband_mode=args.cytoband_mode,
        )


if __name__ == "__main__":
    main()
