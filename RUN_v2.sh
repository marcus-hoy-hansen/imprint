#!/usr/bin/env bash
#SBATCH --output=/faststorage/project/nanopore_kga/workflow_dev/logs/RUN_v2-%j.out
#SBATCH --error=/faststorage/project/nanopore_kga/workflow_dev/logs/RUN_v2-%j.out
set -euo pipefail

ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"
ROOT="$(cd "${ROOT}" && pwd)"
SNAKEFILE="${ROOT}/workflows/preflight/Snakefile_preflight"
CONFIG_FILE="${ROOT}/config/preflight_v2.yaml"
PROFILE_DIR="${ROOT}/profiles/preflight"

UPLOAD_DIR=""
STORAGE_DIR=""
ANALYSIS_DIR=""
ENTRY_STAGE="preflight"
CONTINUE_AFTER_ENTRY=0
WATCH=0
UNLOCK=0
EXTRA_SNAKEMAKE_ARGS=()
HAS_EXPLICIT_MODE=0

usage() {
  cat <<EOF
Usage: bash RUN_v2.sh [BASE] [--config /path/to/preflight_v2.yaml] [--profile /path/to/profile] [--upload-dir /path] [--storage-dir /path] [--analysis-dir /path] [--entry preflight|basecall|align|snakemake] [--continue] [--unlock] [-- <extra snakemake args>]

Snakemake-native preflight wrapper.
Default:
  bash RUN_v2.sh
  Equivalent to: bash RUN_v2.sh --entry preflight --continue

Stage mapping:
  preflight            -> validate_all
  basecall             -> basecall_all
  align                -> basecall_all
  snakemake            -> submit_all
  any stage + --continue -> submit_all

Examples:
  bash RUN_v2.sh
  bash RUN_v2.sh --unlock
  bash RUN_v2.sh --analysis-dir /faststorage/project/nanopore_kga/analysis_test --continue
  bash RUN_v2.sh --upload-dir /faststorage/project/nanopore_kga/uploaded --storage-dir /faststorage/project/nanopore_kga/STORAGE --analysis-dir /faststorage/project/nanopore_kga/analysis_v2
  bash RUN_v2.sh --entry basecall
  
Limitations:
  --watch is not implemented yet for RUN_v2.sh
EOF
}

target_for_stage() {
  local stage="$1"
  local do_continue="$2"

  if [[ "$do_continue" -eq 1 ]]; then
    printf '%s\n' "submit_all"
    return 0
  fi

  case "$stage" in
    preflight) printf '%s\n' "validate_all" ;;
    basecall) printf '%s\n' "basecall_all" ;;
    align) printf '%s\n' "basecall_all" ;;
    snakemake) printf '%s\n' "submit_all" ;;
    *)
      echo "ERROR: invalid --entry '$stage'" >&2
      exit 1
      ;;
  esac
}

while (( $# )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --config)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --config requires a value" >&2; exit 1; }
      CONFIG_FILE="$1"
      ;;
    --profile)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --profile requires a value" >&2; exit 1; }
      PROFILE_DIR="$1"
      ;;
    --upload-dir)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --upload-dir requires a value" >&2; exit 1; }
      UPLOAD_DIR="$1"
      ;;
    --storage-dir)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --storage-dir requires a value" >&2; exit 1; }
      STORAGE_DIR="$1"
      ;;
    --analysis-dir)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --analysis-dir requires a value" >&2; exit 1; }
      ANALYSIS_DIR="$1"
      ;;
    --entry)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --entry requires a value" >&2; exit 1; }
      ENTRY_STAGE="$1"
      HAS_EXPLICIT_MODE=1
      ;;
    --continue)
      CONTINUE_AFTER_ENTRY=1
      HAS_EXPLICIT_MODE=1
      ;;
    --watch)
      WATCH=1
      ;;
    --unlock)
      UNLOCK=1
      ;;
    --)
      shift
      EXTRA_SNAKEMAKE_ARGS+=("$@")
      break
      ;;
    *)
      if [[ -z "$UPLOAD_DIR" && "$1" != --* ]]; then
        UPLOAD_DIR="$1"
      else
        EXTRA_SNAKEMAKE_ARGS+=("$1")
      fi
      ;;
  esac
  shift
done

if [[ $HAS_EXPLICIT_MODE -eq 0 ]]; then
  CONTINUE_AFTER_ENTRY=1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if [[ ! -f "$SNAKEFILE" ]]; then
  echo "ERROR: snakefile not found: $SNAKEFILE" >&2
  exit 1
fi

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "ERROR: profile dir not found: $PROFILE_DIR" >&2
  exit 1
fi

export PATH="/home/$USER/miniforge3/condabin:/home/$USER/miniforge3/bin:$PATH"
source /home/$USER/miniforge3/etc/profile.d/conda.sh
conda activate snakemake_env

TARGET="$(target_for_stage "$ENTRY_STAGE" "$CONTINUE_AFTER_ENTRY")"

SNAKEMAKE_CMD=(
  snakemake
  -s "$SNAKEFILE"
  --configfile "$CONFIG_FILE"
  --profile "$PROFILE_DIR"
)

CONFIG_OVERRIDES=()
if [[ -n "$UPLOAD_DIR" ]]; then
  CONFIG_OVERRIDES+=("uploadDir=$UPLOAD_DIR")
fi
if [[ -n "$STORAGE_DIR" ]]; then
  CONFIG_OVERRIDES+=("storageDir=$STORAGE_DIR")
fi
if [[ -n "$ANALYSIS_DIR" ]]; then
  CONFIG_OVERRIDES+=("analysisDir=$ANALYSIS_DIR")
fi

SNAKEMAKE_CMD+=("$TARGET")
if (( ${#CONFIG_OVERRIDES[@]} > 0 )); then
  SNAKEMAKE_CMD+=(--config "${CONFIG_OVERRIDES[@]}")
fi
if (( ${#EXTRA_SNAKEMAKE_ARGS[@]} > 0 )); then
  SNAKEMAKE_CMD+=("${EXTRA_SNAKEMAKE_ARGS[@]}")
fi

if (( WATCH )); then
  echo "ERROR: --watch is not implemented yet for the Snakemake-native preflight path" >&2
  exit 1
fi

if (( UNLOCK )); then
  SNAKEMAKE_CMD+=(--unlock)
fi

env \
  -u SLURM_MEM_PER_CPU \
  -u SLURM_MEM_PER_GPU \
  -u SLURM_MEM_PER_NODE \
  "${SNAKEMAKE_CMD[@]}"
