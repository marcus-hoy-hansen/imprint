#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
CONF_FILE="${1:-${TEST_DIR}/fullpipe_test.conf}"
SAMTOOLS_CONTAINER="${TEST_DIR}/containers/samtools_1.20.sif"

# shellcheck source=/dev/null
source "${CONF_FILE}"

if [[ ! -f "${SAMTOOLS_CONTAINER}" ]]; then
  echo "ERROR: missing samtools container: ${SAMTOOLS_CONTAINER}" >&2
  echo "Build it first with: bash apptainer_test/build_samtools_container.sh" >&2
  exit 1
fi

if [[ ! -f "${INPUT_SUP_BAM}" ]]; then
  echo "ERROR: input SUP BAM not found: ${INPUT_SUP_BAM}" >&2
  exit 1
fi

RAW_DIR="${ANALYSIS_DIR}/${TEST_SAMPLE}/data/raw"
RAW_BAM="${RAW_DIR}/$(basename "${INPUT_SUP_BAM}" .bam).subset_${SUBSET_READS}.bam"
TMP_DIR="${ANALYSIS_DIR}/.tmp"
CACHE_DIR="${ANALYSIS_DIR}/.apptainer_cache"

mkdir -p "${RAW_DIR}" "${TMP_DIR}" "${CACHE_DIR}"

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-${TMP_DIR}}}"
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${SINGULARITY_CACHEDIR:-${CACHE_DIR}}}"
mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}"

echo "Preparing subset BAM:"
echo "  input:  ${INPUT_SUP_BAM}"
echo "  output: ${RAW_BAM}"
echo "  reads:  ${SUBSET_READS}"

apptainer exec "${SAMTOOLS_CONTAINER}" bash -lc \
  "set -euo pipefail; set +o pipefail; samtools view -h '${INPUT_SUP_BAM}' | awk 'BEGIN {n=0} /^@/ {print; next} n < ${SUBSET_READS} {print; n++} n == ${SUBSET_READS} {exit}' | samtools view -b -o '${RAW_BAM}'; set -o pipefail"

echo "Done:"
echo "  ${RAW_BAM}"
