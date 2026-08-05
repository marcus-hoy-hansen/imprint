#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
DEF_FILE="${TEST_DIR}/Apptainer.workflow_runtime.def"
CONTAINER_DIR="${TEST_DIR}/containers"
SIF_FILE="${CONTAINER_DIR}/workflow_runtime.sif"
MODE="${1:-external-envs}"
RUNTIME_ENVS_TAR="${TEST_DIR}/runtime_envs.tar"

mkdir -p "${CONTAINER_DIR}"

case "${MODE}" in
  external-envs)
    echo "Building lightweight runtime image with external runtime env bind mount"
    ;;
  baked-envs)
    if [[ ! -f "${RUNTIME_ENVS_TAR}" ]]; then
      echo "ERROR: missing runtime env tar: ${RUNTIME_ENVS_TAR}" >&2
      echo "Create it next to runtime_envs before baked build." >&2
      exit 1
    fi
    echo "Building baked-env runtime image using:"
    echo "  ${RUNTIME_ENVS_TAR}"
    ;;
  *)
    echo "ERROR: mode must be external-envs or baked-envs" >&2
    exit 1
    ;;
esac

if [[ "${MODE}" == "external-envs" ]]; then
  echo "Expected external env folder:"
  echo "  ${TEST_DIR}/runtime_envs"
fi

echo "Building Apptainer runtime image:"
echo "  def: ${DEF_FILE}"
echo "  out: ${SIF_FILE}"

cd "${ROOT}"
apptainer build "${SIF_FILE}" "${DEF_FILE}"

echo "Done:"
echo "  ${SIF_FILE}"
