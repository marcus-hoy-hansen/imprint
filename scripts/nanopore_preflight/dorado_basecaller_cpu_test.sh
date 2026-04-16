#!/bin/bash
#SBATCH --job-name=dorado-test-cpu
#SBATCH --account=nanopore_kga
#SBATCH --partition=normal
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

# CPU-only, limited-read test wrapper that reuses the main basecaller logic.
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

export NP_DORADO_DEVICE="cpu"
export NP_DORADO_TEST_MODE="1"

exec "${NP_SCRIPT_ROOT}/dorado_basecaller.sh" "$@"
