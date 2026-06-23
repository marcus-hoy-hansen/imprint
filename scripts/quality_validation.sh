#!/bin/bash
#SBATCH --job-name=Qval
#SBATCH --account=nanopore_kga
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=5:00:00
#SBATCH --output=logs/Qval.out


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
    if [[ -f "${dir}/adaptive_panel_lib.sh" && -f "${dir}/target_region_mean_coverage.sh" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  return 1
}

maybe_activate_conda() {
  local env_name="${NP_CONDA_ENV:-bwa}"
  local conda_profile="${NP_CONDA_PROFILE:-/home/$USER/miniforge3/etc/profile.d/conda.sh}"

  if [[ -f "$conda_profile" ]]; then
    # shellcheck source=/dev/null
    source "$conda_profile"
    conda activate "$env_name" >/dev/null 2>&1 || true
  fi
}

SCRIPT_DIR="$(resolve_script_dir)" || {
  echo "ERROR: could not resolve scripts directory for quality validation" >&2
  exit 1
}
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/adaptive_panel_lib.sh"
TARGET_SCRIPT="${SCRIPT_DIR}/target_region_mean_coverage.sh"
NON_TARGET_SCRIPT="${SCRIPT_DIR}/test_non_target_mean_coverage.sh"
READ_LENGTH_SCRIPT="${SCRIPT_DIR}/read_length_summary.sh"

usage() {
  cat <<'EOF'
Usage: bash quality_validation.sh <input.bam>

Runs target-region mean coverage, non-target mean coverage, target/non-target read-length summaries, samtools flagstat, and samtools stats.
Outputs are written to QC/validation_metrics under the sample analysis directory.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

if ! command -v samtools >/dev/null 2>&1; then
  maybe_activate_conda
fi

if ! command -v samtools >/dev/null 2>&1; then
  echo "ERROR: samtools not found in PATH after attempting conda activation" >&2
  exit 1
fi

BAM_FILE="$1"

if [[ ! -f "$BAM_FILE" ]]; then
  echo "ERROR: BAM file not found: $BAM_FILE" >&2
  exit 1
fi

bam_dir="$(dirname "$BAM_FILE")"
sample_dir="$(cd "${bam_dir}/.." && pwd)"
sample_name="$(basename "$BAM_FILE" .bam)"
qc_dir="${sample_dir}/QC/validation_metrics"

mkdir -p "$qc_dir"

target_output="${qc_dir}/${sample_name}.target_region_mean_coverage.tsv"
non_target_output="${qc_dir}/${sample_name}.non_target_mean_coverage.txt"
flagstat_output="${qc_dir}/${sample_name}.flagstat.txt"
stats_output="${qc_dir}/${sample_name}.stats.txt"
target_read_length_output="${qc_dir}/${sample_name}.target_read_length_stats.txt"
non_target_read_length_output="${qc_dir}/${sample_name}.non_target_read_length_stats.txt"
selected_bed="$(select_best_adaptive_panel "$BAM_FILE")"

bash "$TARGET_SCRIPT" "$BAM_FILE" "$target_output"

{
  printf 'bed\t%s\n' "$selected_bed"
  printf 'mean_non_target_coverage\t'
  bash "$NON_TARGET_SCRIPT" "$selected_bed" "$BAM_FILE"
} > "$non_target_output"

bash "$READ_LENGTH_SCRIPT" "$selected_bed" "$BAM_FILE" target "$target_read_length_output"
bash "$READ_LENGTH_SCRIPT" "$selected_bed" "$BAM_FILE" non_target "$non_target_read_length_output"

samtools flagstat "$BAM_FILE" > "$flagstat_output"
samtools stats "$BAM_FILE" \
  | awk -F '\t' '$1 == "SN" { sub(/:$/, "", $2); print $2 "\t" $3 }' \
  > "$stats_output"

printf 'Wrote:\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$target_output" \
  "$non_target_output" \
  "$target_read_length_output" \
  "$non_target_read_length_output" \
  "$flagstat_output" \
  "$stats_output"
