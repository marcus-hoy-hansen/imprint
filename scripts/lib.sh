#!/usr/bin/env bash
set -euo pipefail

# Absolute root so sbatch copies can still find configs/libs after staging.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NP_SCRIPT_ROOT:=${SCRIPT_DIR}}"
CONFIG_FILE="${CONFIG_FILE:-${NP_SCRIPT_ROOT}/config.sh}"

# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    return 1
  fi
}

maybe_activate_conda() {
  local env_name="$1"
  if [[ -f "$NP_CONDA_PROFILE" ]]; then
    # shellcheck source=/dev/null
    source "$NP_CONDA_PROFILE"
    conda activate "$env_name" >/dev/null 2>&1 || true
  fi
}

ensure_samtools() {
  if ! command -v samtools >/dev/null 2>&1; then
    maybe_activate_conda "$NP_CONDA_ENV"
  fi

  require_cmd samtools
}
