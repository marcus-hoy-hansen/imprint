#!/usr/bin/env bash
set -euo pipefail

resolve_script_dir() {
  local candidate_dirs=()

  candidate_dirs+=("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")

  if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    candidate_dirs+=("${SLURM_SUBMIT_DIR}/scripts")
  fi

  candidate_dirs+=("$(pwd)/scripts")

  local dir
  for dir in "${candidate_dirs[@]}"; do
    if [[ -f "${dir}/adaptive_panel_lib.sh" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  return 1
}

SCRIPT_DIR="$(resolve_script_dir)" || {
  echo "ERROR: could not resolve scripts directory for target_region_mean_coverage.sh" >&2
  exit 1
}
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/adaptive_panel_lib.sh"

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

best_bed="$(select_best_adaptive_panel "$BAM_FILE")"
bed_name="$(basename "$best_bed")"
bed_slug="${bed_name//[^[:alnum:]._-]/_}"
best_regions="${tmp_dir}/${bed_slug}.regions.tsv"
means_tmp="${tmp_dir}/${bed_slug}.means.tsv"
sorted_tmp="${tmp_dir}/${bed_slug}.means.sorted.tsv"
best_summary="${tmp_dir}/${bed_slug}.summary.tsv"

samtools bedcov "$best_bed" "$BAM_FILE" | awk '
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
' means_file="$means_tmp" > "$best_regions"

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
' "$sorted_tmp" > "$best_summary"

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  printf 'Panel\t%s\n' "$(basename "$best_bed")"
  cat "$best_summary"
  printf '%s\n' '--------------'
  printf 'chrom\tstart\tend\tregion\tmean_coverage\n'
  cat "$best_regions"
} > "$OUTPUT_FILE"

printf 'Wrote %s using panel %s\n' "$OUTPUT_FILE" "$(basename "$best_bed")"
