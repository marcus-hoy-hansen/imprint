#!/usr/bin/env bash
set -euo pipefail

ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"
ROOT="$(cd "${ROOT}" && pwd)"
CONFIG_FILE="${ROOT}/scripts/nanopore_preflight/config.sh"
PREFLIGHT="${ROOT}/scripts/nanopore_preflight/preflight.sh"
SCHEDULER="${ROOT}/scripts/nanopore_preflight/nanopore_imprint_scheduler.sh"
LOG_DIR="${ROOT}/logs"

usage() {
  cat <<EOF
Usage: bash RUN.sh [BASE] [--entry preflight|basecall|align|snakemake] [--analysis-dir /path] [--continue]
       bash RUN.sh --watch [BASE] [--entry preflight|basecall|align|snakemake] [--analysis-dir /path] [--continue]

Default:
  bash RUN.sh
  Equivalent to: bash RUN.sh --entry preflight --continue

Stages:
  preflight  Run upload checks only. Add --continue to run the full workflow.
  basecall   Start at Dorado basecalling. Add --continue to stage SUP BAM and run Snakemake.
  align      Legacy alias that stages an existing SUP BAM and optionally runs Snakemake.
  snakemake  Submit runSnakemake.sh directly from preflight-discovered samples.

Watcher:
  bash RUN.sh --watch
  Equivalent to scheduling repeated: bash RUN.sh --entry preflight --continue

Examples:
  bash RUN.sh
  bash RUN.sh --watch
  bash RUN.sh --entry preflight --continue
  bash RUN.sh --entry snakemake
  bash RUN.sh --entry align --continue
  bash RUN.sh --analysis-dir /faststorage/project/nanopore_kga/analysis_test --continue
  bash RUN.sh /faststorage/project/nanopore_kga/uploaded --entry snakemake
EOF
}

mkdir -p "${LOG_DIR}"

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --watch)
    shift
    env \
      -u SLURM_MEM_PER_CPU \
      -u SLURM_MEM_PER_GPU \
      -u SLURM_MEM_PER_NODE \
      sbatch --output="${LOG_DIR}/imprint-watch-%j.out" --error="${LOG_DIR}/imprint-watch-%j.out" --export=ALL,CONFIG_FILE="${CONFIG_FILE}" "${SCHEDULER}" --watch "$@"
    exit 0
    ;;
esac

has_explicit_mode=0
for arg in "$@"; do
  case "$arg" in
    --entry|--continue)
      has_explicit_mode=1
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  set -- --entry preflight --continue
elif [[ $has_explicit_mode -eq 0 ]]; then
  set -- --entry preflight --continue "$@"
fi

env \
  -u SLURM_MEM_PER_CPU \
  -u SLURM_MEM_PER_GPU \
  -u SLURM_MEM_PER_NODE \
  sbatch --output="${LOG_DIR}/preflight-%j.out" --error="${LOG_DIR}/preflight-%j.out" --export=ALL,CONFIG_FILE="${CONFIG_FILE}" "${PREFLIGHT}" "$@"
