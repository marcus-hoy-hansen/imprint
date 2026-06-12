#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash test_non_target_mean_coverage.sh <targets.bed> <input.bam>" >&2
  exit 1
fi

BED_FILE="$1"
BAM_FILE="$2"
HG38_GENOME_SIZE=3088269832

NON_TARGET_BASES="$(
  samtools view -b -L "$BED_FILE" -U /dev/stdout -o /dev/null "$BAM_FILE" \
    | samtools stats - \
    | awk -F '\t' '/^SN\tbases mapped \(cigar\):/ {print $3}'
)"

TARGET_SIZE="$(awk '{sum += $3 - $2} END {print sum}' "$BED_FILE")"

awk -v b="$NON_TARGET_BASES" -v g="$HG38_GENOME_SIZE" -v t="$TARGET_SIZE" 'BEGIN {printf "%.6f\n", b / (g - t)}'
