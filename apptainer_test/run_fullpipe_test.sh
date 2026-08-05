#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
CONF_FILE="${1:-${TEST_DIR}/fullpipe_test.conf}"
RUNNER_CONTAINER="${TEST_DIR}/containers/snakemake_runner.sif"

# shellcheck source=/dev/null
source "${CONF_FILE}"

if [[ ! -f "${RUNNER_CONTAINER}" ]]; then
  echo "ERROR: missing Snakemake runner container: ${RUNNER_CONTAINER}" >&2
  echo "Build it first with: bash apptainer_test/build_snakemake_runner.sh" >&2
  exit 1
fi

bash "${TEST_DIR}/prepare_fullpipe_subset.sh" "${CONF_FILE}"

TMP_DIR="${ANALYSIS_DIR}/.tmp"
CACHE_DIR="${ANALYSIS_DIR}/.apptainer_cache"
XDG_CACHE_DIR="${ANALYSIS_DIR}/.xdg_cache"

mkdir -p "${TMP_DIR}" "${CACHE_DIR}" "${XDG_CACHE_DIR}"

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-${TMP_DIR}}}"
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${SINGULARITY_CACHEDIR:-${CACHE_DIR}}}"
mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}"

cd "${ROOT}"

apptainer exec \
  --bind /faststorage \
  --bind /home \
  "${RUNNER_CONTAINER}" \
  bash -lc "
    set -euo pipefail
    export XDG_CACHE_HOME='${XDG_CACHE_DIR}'
    export TMPDIR='${TMP_DIR}'
    cd '${ROOT}'
    snakemake \
      -s workflows/workflow_AS/Snakefile_AS \
      --configfile config/config.yaml \
      --config \
      sample='${TEST_SAMPLE}' \
      refGenome='${REF_GENOME}' \
      refFile='${REF_FILE}' \
      ASversion='${AS_VERSION}' \
      analysisDir='${ANALYSIS_DIR}' \
      --use-conda \
      --conda-frontend conda \
      --rerun-incomplete \
      --profile profiles/AS/
  "
