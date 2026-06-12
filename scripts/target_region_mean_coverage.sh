#!/usr/bin/env bash
set -euo pipefail

BED_FILES=(
  "/faststorage/project/nanopore_kga/uploaded/adaptiveSampling_hg38_v2.bed"
  "/faststorage/project/nanopore_kga/uploaded/RB_adaptiveSampling_GRCh38_v3.bed"
)

usage() {
  cat <<'EOF'
Usage: bash target_region_mean_coverage.sh <input.bam> [output.tsv]

Computes mean coverage for each BED target region from a BAM using samtools bedcov.
Runs all hardcoded panels, selects the panel with the highest mean region coverage,
and writes a summary header, separator, and per-region mean coverage table.
If output.tsv is omitted, a file is written next to the BAM.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

if ! command -v samtools >/dev/null 2>&1; then
  echo "ERROR: samtools not found in PATH" >&2
  exit 1
fi

if ! command -v awk >/dev/null 2>&1; then
  echo "ERROR: awk not found in PATH" >&2
  exit 1
fi

if ! command -v sort >/dev/null 2>&1; then
  echo "ERROR: sort not found in PATH" >&2
  exit 1
fi

BAM_FILE="$1"
OUTPUT_FILE="${2:-}"

if [[ ! -f "$BAM_FILE" ]]; then
  echo "ERROR: BAM file not found: $BAM_FILE" >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  bam_dir="$(dirname "$BAM_FILE")"
  bam_base="$(basename "$BAM_FILE")"
  bam_stem="${bam_base%.bam}"
  OUTPUT_FILE="${bam_dir}/${bam_stem}.target_region_mean_coverage.tsv"
fi

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

best_mean=""
best_bed=""
best_summary=""
best_regions=""

for bed_file in "${BED_FILES[@]}"; do
  if [[ ! -f "$bed_file" ]]; then
    echo "ERROR: BED file not found: $bed_file" >&2
    exit 1
  fi

  bed_name="$(basename "$bed_file")"
  bed_slug="${bed_name//[^[:alnum:]._-]/_}"
  regions_tmp="${tmp_dir}/${bed_slug}.regions.tsv"
  means_tmp="${tmp_dir}/${bed_slug}.means.tsv"
  sorted_tmp="${tmp_dir}/${bed_slug}.means.sorted.tsv"
  summary_tmp="${tmp_dir}/${bed_slug}.summary.tsv"

  samtools bedcov "$bed_file" "$BAM_FILE" | awk '
    BEGIN { OFS="\t" }
    {
      len = $3 - $2
      if (len <= 0) {
        next
      }

      name = ($4 == "" ? "." : $4)
      mean_cov = $NF / len

      print $1, $2, $3, name, sprintf("%.0f", mean_cov)
      print mean_cov > means_file
    }
  ' means_file="$means_tmp" > "$regions_tmp"

  sort -g "$means_tmp" > "$sorted_tmp"

  awk '
    function percentile(p,    idx) {
      if (n == 0) {
        return "NA"
      }
      idx = int((n - 1) * p + 1.5)
      if (idx < 1) {
        idx = 1
      }
      if (idx > n) {
        idx = n
      }
      return vals[idx]
    }

    {
      vals[++n] = $1
      sum += $1
    }

    END {
      if (n == 0) {
        print "Q1\tNA"
        print "Median\tNA"
        print "Q3\tNA"
        print "Mean\tNA"
        exit
      }

      printf "Q1\t%.2f\n", percentile(0.25)
      printf "Median\t%.2f\n", percentile(0.50)
      printf "Q3\t%.2f\n", percentile(0.75)
      printf "Mean\t%.2f\n", sum / n
    }
  ' "$sorted_tmp" > "$summary_tmp"

  panel_mean="$(awk -F '\t' '$1 == "Mean" { print $2 }' "$summary_tmp")"

  if [[ -z "$best_mean" ]] || awk -v current="$panel_mean" -v best="$best_mean" 'BEGIN { exit !(current > best) }'; then
    best_mean="$panel_mean"
    best_bed="$bed_file"
    best_summary="$summary_tmp"
    best_regions="$regions_tmp"
  fi
done

{
  printf 'Panel\t%s\n' "$(basename "$best_bed")"
  cat "$best_summary"
  printf '%s\n' '--------------'
  printf 'chrom\tstart\tend\tregion\tmean_coverage\n'
  cat "$best_regions"
} > "$OUTPUT_FILE"

printf 'Wrote %s using panel %s\n' "$OUTPUT_FILE" "$(basename "$best_bed")"
