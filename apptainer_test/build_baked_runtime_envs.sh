#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT}/apptainer_test"
ENV_DIR="${TEST_DIR}/runtime_envs"

mkdir -p "${ENV_DIR}"

if ! command -v mamba >/dev/null 2>&1 && ! command -v conda >/dev/null 2>&1; then
  echo "ERROR: neither mamba nor conda found on PATH" >&2
  exit 1
fi

SOLVER="conda"
if command -v mamba >/dev/null 2>&1; then
  SOLVER="mamba"
fi

build_env() {
  local name="$1"
  local spec="$2"
  local prefix="${ENV_DIR}/${name}"

  echo
  echo "Building env: ${name}"
  echo "  spec:   ${spec}"
  echo "  prefix: ${prefix}"

  rm -rf "${prefix}"
  "${SOLVER}" env create -p "${prefix}" -f "${spec}"
}

build_env samtools envs/samtools.yaml
build_env bedtools envs/bedtools.yaml
build_env nanoplot envs/nanoPlot.yaml
build_env clair3 envs/clair3.yaml
build_env cuteSV envs/cuteSV.yaml
build_env sniffles2 envs/sniffles2.yaml
build_env hifiCNV envs/hifiCNV.yaml
build_env qdna envs/qdna.yaml
build_env straglr envs/straglr.yaml
build_env variant_panel envs/variant_panel.yaml
build_env nanoimprint envs/nanoImprint.yaml
build_env bcftools envs/bcftools.yaml
build_env workflow_py apptainer_test/workflow_python.yaml

echo
echo "Built runtime env prefixes under:"
echo "  ${ENV_DIR}"

