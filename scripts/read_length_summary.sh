#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash read_length_summary.sh <targets.bed> <input.bam> <target|non_target> [output.txt]

Computes Q1, Median, Q3, and N50 for read lengths in the selected subset.
"target" uses reads overlapping the BED; "non_target" uses reads outside the BED.
If output.txt is omitted, a file is written next to the BAM.
EOF
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
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

BED_FILE="$1"
BAM_FILE="$2"
MODE="$3"
OUTPUT_FILE="${4:-}"

if [[ ! -f "$BED_FILE" ]]; then
  echo "ERROR: BED file not found: $BED_FILE" >&2
  exit 1
fi

if [[ ! -f "$BAM_FILE" ]]; then
  echo "ERROR: BAM file not found: $BAM_FILE" >&2
  exit 1
fi

if [[ "$MODE" != "target" && "$MODE" != "non_target" ]]; then
  echo "ERROR: mode must be target or non_target" >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  bam_dir="$(dirname "$BAM_FILE")"
  bam_base="$(basename "$BAM_FILE" .bam)"
  OUTPUT_FILE="${bam_dir}/${bam_base}.${MODE}_read_length_stats.txt"
fi

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

lengths_tmp="${tmp_dir}/lengths.tsv"
lengths_sorted="${tmp_dir}/lengths.sorted.tsv"
lengths_desc="${tmp_dir}/lengths.desc.tsv"

case "$MODE" in
  target)
    samtools view -F 0x904 -L "$BED_FILE" "$BAM_FILE" \
      | awk 'length($10) > 0 { print length($10) }' > "$lengths_tmp"
    ;;
  non_target)
    samtools view -b -F 0x904 -L "$BED_FILE" -U /dev/stdout -o /dev/null "$BAM_FILE" \
      | samtools view - \
      | awk 'length($10) > 0 { print length($10) }' > "$lengths_tmp"
    ;;
esac

sort -n "$lengths_tmp" > "$lengths_sorted"
sort -nr "$lengths_tmp" > "$lengths_desc"

read_count="$(wc -l < "$lengths_sorted")"

if [[ "$read_count" -eq 0 ]]; then
  {
    printf 'Q1\tNA\n'
    printf 'Median\tNA\n'
    printf 'Q3\tNA\n'
    printf 'N50\tNA\n'
  } > "$OUTPUT_FILE"
  printf 'Wrote %s\n' "$OUTPUT_FILE"
  exit 0
fi

q1_idx="$(awk -v n="$read_count" 'BEGIN { print int((n - 1) * 0.25 + 1.5) }')"
median_idx="$(awk -v n="$read_count" 'BEGIN { print int((n - 1) * 0.50 + 1.5) }')"
q3_idx="$(awk -v n="$read_count" 'BEGIN { print int((n - 1) * 0.75 + 1.5) }')"

read_stats="$(awk -v q1="$q1_idx" -v median="$median_idx" -v q3="$q3_idx" '
  NR == q1 { q1_val = $1 }
  NR == median { median_val = $1 }
  NR == q3 { q3_val = $1 }
  { total += $1 }
  END { printf "%s\t%s\t%s\t%.0f\n", q1_val, median_val, q3_val, total }
' "$lengths_sorted")"

IFS=$'\t' read -r q1_value median_value q3_value total_bases <<< "$read_stats"

n50_value="$(awk -v total="$total_bases" '
  {
    running += $1
    if ((running * 2) >= total) {
      print $1
      exit
    }
  }
' "$lengths_desc")"

{
  printf 'Q1\t%s\n' "$q1_value"
  printf 'Median\t%s\n' "$median_value"
  printf 'Q3\t%s\n' "$q3_value"
  printf 'N50\t%s\n' "$n50_value"
} > "$OUTPUT_FILE"

printf 'Wrote %s\n' "$OUTPUT_FILE"
