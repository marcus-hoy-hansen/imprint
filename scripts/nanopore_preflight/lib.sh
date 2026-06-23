#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"

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

clean_sbatch() {
  env \
    -u SLURM_MEM_PER_CPU \
    -u SLURM_MEM_PER_GPU \
    -u SLURM_MEM_PER_NODE \
    sbatch "$@"
}

sample_lock_write() {
  local lock_file="$1"
  local stage="$2"
  local jobid="$3"
  local sample_token="${4:-}"
  local tmp_file

  mkdir -p "$(dirname "$lock_file")"
  tmp_file="${lock_file}.tmp.$$"

  {
    printf 'stage=%s\n' "$stage"
    printf 'jobid=%s\n' "$jobid"
    printf 'sample=%s\n' "$sample_token"
    printf 'time=%s\n' "$(date -Is)"
    printf 'host=%s\n' "$(hostname)"
  } > "$tmp_file"

  mv "$tmp_file" "$lock_file"
}

sample_lock_clear() {
  local lock_file="${1:-}"
  [[ -n "$lock_file" ]] || return 0
  rm -f "$lock_file"
}
