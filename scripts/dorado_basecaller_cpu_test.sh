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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NP_SCRIPT_ROOT:=${SCRIPT_DIR}}"

export NP_DORADO_DEVICE="cpu"
export NP_DORADO_TEST_MODE="1"

exec "${NP_SCRIPT_ROOT}/dorado_basecaller2_20260121.sh" "$@"
