#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
DEF_FILE="${TEST_DIR}/Apptainer.snakemake_runner.def"
CONTAINER_DIR="${TEST_DIR}/containers"
SIF_FILE="${CONTAINER_DIR}/snakemake_runner.sif"

mkdir -p "${CONTAINER_DIR}"

echo "Building Apptainer image:"
echo "  def: ${DEF_FILE}"
echo "  out: ${SIF_FILE}"

apptainer build "${SIF_FILE}" "${DEF_FILE}"

echo "Done:"
echo "  ${SIF_FILE}"
