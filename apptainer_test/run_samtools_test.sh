#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
SNAKEFILE="${TEST_DIR}/Snakefile"
CONFIG="${TEST_DIR}/config.yaml"
CONTAINER="${TEST_DIR}/containers/samtools_1.20.sif"

if [[ ! -f "${CONTAINER}" ]]; then
  echo "ERROR: missing container image: ${CONTAINER}" >&2
  echo "Build it first with: bash apptainer_test/build_samtools_container.sh" >&2
  exit 1
fi

cd "${ROOT}"

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-/tmp}}"
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}}"
mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}"

snakemake \
  -s "${SNAKEFILE}" \
  --configfile "${CONFIG}" \
  --use-singularity \
  --cores 1 \
  --rerun-incomplete
