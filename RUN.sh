#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ROOT}/scripts/nanopore_preflight/config.sh"
PREFLIGHT="${ROOT}/scripts/nanopore_preflight/preflight.sh"
SCHEDULER="${ROOT}/scripts/nanopore_preflight/nanopore_imprint_scheduler.sh"

usage() {
  cat <<EOF
Usage: bash RUN.sh [BASE] [--entry preflight|basecall|align|snakemake] [--continue]
       bash RUN.sh --watch [BASE] [--entry preflight|basecall|align|snakemake] [--continue]

Default:
  bash RUN.sh
  Equivalent to: bash RUN.sh --entry preflight --continue

Stages:
  preflight  Run upload checks only. Add --continue to run the full workflow.
  basecall   Start at Dorado basecalling. Add --continue to align and run Snakemake.
  align      Submit alignment directly. Add --continue to run Snakemake after alignment.
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
  bash RUN.sh /faststorage/project/nanopore_kga/uploaded --entry snakemake
EOF
}

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
      sbatch --export=ALL,CONFIG_FILE="${CONFIG_FILE}" "${SCHEDULER}" --watch "$@"
    exit 0
    ;;
esac

if [[ $# -eq 0 ]]; then
  set -- --entry preflight --continue
fi

env \
  -u SLURM_MEM_PER_CPU \
  -u SLURM_MEM_PER_GPU \
  -u SLURM_MEM_PER_NODE \
  sbatch --export=ALL,CONFIG_FILE="${CONFIG_FILE}" "${PREFLIGHT}" "$@"
