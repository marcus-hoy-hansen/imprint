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
  echo "ERROR: could not resolve scripts directory for test_non_target_mean_coverage.sh" >&2
  exit 1
}
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/adaptive_panel_lib.sh"

if [[ $# -ne 1 && $# -ne 2 ]]; then
  echo "Usage: bash test_non_target_mean_coverage.sh [targets.bed] <input.bam>" >&2
  exit 1
fi

if [[ $# -eq 2 ]]; then
  BED_FILE="$1"
  BAM_FILE="$2"
else
  BAM_FILE="$1"
  BED_FILE="$(select_best_adaptive_panel "$BAM_FILE")"
fi

HG38_GENOME_SIZE=3088269832

NON_TARGET_BASES="$(
  samtools view -b -L "$BED_FILE" -U /dev/stdout -o /dev/null "$BAM_FILE" \
    | samtools stats - \
    | awk -F '\t' '/^SN\tbases mapped \(cigar\):/ {print $3}'
)"

TARGET_SIZE="$(awk '{sum += $3 - $2} END {print sum}' "$BED_FILE")"

awk -v b="$NON_TARGET_BASES" -v g="$HG38_GENOME_SIZE" -v t="$TARGET_SIZE" 'BEGIN {printf "%.6f\n", b / (g - t)}'
