#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
CONTAINER="${TEST_DIR}/containers/workflow_runtime.sif"
RUNTIME_ENVS="${TEST_DIR}/runtime_envs"
SAMPLE=""
INPUT_DIR=""
OUTPUT_DIR=""
SUBSET_READS=""
PASSTHROUGH_ARGS=()

while (( $# )); do
  case "$1" in
    --sample)
      PASSTHROUGH_ARGS+=("$1")
      shift
      SAMPLE="${1:-}"
      PASSTHROUGH_ARGS+=("${SAMPLE}")
      ;;
    --input-dir)
      shift
      INPUT_DIR="${1:-}"
      ;;
    --output-dir)
      PASSTHROUGH_ARGS+=("$1")
      shift
      OUTPUT_DIR="${1:-}"
      PASSTHROUGH_ARGS+=("${OUTPUT_DIR}")
      ;;
    --subset-reads)
      shift
      SUBSET_READS="${1:-}"
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      ;;
  esac
  shift || true
done

if [[ ! -f "${CONTAINER}" ]]; then
  echo "ERROR: missing runtime container: ${CONTAINER}" >&2
  echo "Build it first with: bash apptainer_test/build_workflow_runtime.sh" >&2
  exit 1
fi

if [[ ! -d "${RUNTIME_ENVS}/samtools" ]]; then
  echo "ERROR: missing runtime env folder: ${RUNTIME_ENVS}" >&2
  echo "Build it first with: bash apptainer_test/build_baked_runtime_envs.sh" >&2
  exit 1
fi

if [[ -z "${SAMPLE}" || -z "${INPUT_DIR}" || -z "${OUTPUT_DIR}" ]]; then
  echo "ERROR: run_baked_workflow.sh requires --sample, --input-dir and --output-dir" >&2
  exit 1
fi

STATE_DIR="${OUTPUT_DIR}/${SAMPLE}/.snakemake_container_state"
mkdir -p "${STATE_DIR}"

CONTAINER_INPUT_DIR="${INPUT_DIR}"
if [[ -n "${SUBSET_READS}" ]]; then
  SUBSET_DIR="${OUTPUT_DIR}/${SAMPLE}/.wrapper_subset_input"
  mkdir -p "${SUBSET_DIR}"

  mapfile -t SOURCE_BAMS < <(find "${INPUT_DIR}" -maxdepth 1 -type f -name '*.bam' ! -name '*.bai' | sort)
  if [[ "${#SOURCE_BAMS[@]}" -eq 0 ]]; then
    echo "ERROR: no BAM files found in ${INPUT_DIR}" >&2
    exit 1
  fi

  for bam in "${SOURCE_BAMS[@]}"; do
    subset_bam="${SUBSET_DIR}/$(basename "${bam}")"
    tmp_bam="${subset_bam}.tmp"
    rm -f "${tmp_bam}"
    set +o pipefail
    samtools view -h "${bam}" \
      | awk -v limit="${SUBSET_READS}" 'BEGIN {n=0} /^@/ {print; next} n < limit {print; n++} n == limit {exit}' \
      | samtools view -b -o "${tmp_bam}"
    set -o pipefail
    mv -f "${tmp_bam}" "${subset_bam}"
  done

  CONTAINER_INPUT_DIR="${SUBSET_DIR}"
fi

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-/tmp}}"
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}}"
mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}"

apptainer exec \
  --bind /faststorage \
  --bind /home \
  --bind "${RUNTIME_ENVS}:/opt/workflow/runtime_envs" \
  --bind "${STATE_DIR}:/opt/workflow/.snakemake" \
  "${CONTAINER}" \
  bash /opt/workflow/apptainer_test/container_entrypoint_baked.sh \
  --input-dir "${CONTAINER_INPUT_DIR}" \
  "${PASSTHROUGH_ARGS[@]}"
