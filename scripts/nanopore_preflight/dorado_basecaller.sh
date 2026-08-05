#!/bin/bash
#SBATCH --job-name=dorado-sup
#SBATCH --account=nanopore_kga
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=24:00:00
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

# Usage:
#   sbatch dorado_basecaller.sh <RUN_SAMPLE_ROOT> [OUT_BAM] [ANALYSIS_RAW_BAM]
# Example:
#   sbatch dorado_basecaller.sh upload_batch_adaptive/sample
#   -> outputs upload_batch_adaptive/sample/sample_sup.bam

set -euo pipefail
umask 002

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"
# shellcheck source=/dev/null
source "${CONFIG_FILE}"
# shellcheck source=lib.sh
source "${NP_SCRIPT_ROOT}/lib.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <RUN_SAMPLE_ROOT> [OUT_BAM] [ANALYSIS_RAW_BAM]" >&2
  exit 1
fi

ROOT="$1"                            # e.g. upload_batch_adaptive/sample
ROOT_BASENAME="$(basename "$ROOT")"  # e.g. sample
DEFAULT_OUT="${ROOT_BASENAME}_sup.bam"
OUT_BAM="${2:-$DEFAULT_OUT}"         # name only
ANALYSIS_RAW_BAM="${3:-}"
ENTRY_STAGE="${NP_ENTRY_STAGE:-snakemake}"
SAMPLE_LOCK_FILE="${NP_SAMPLE_LOCK_FILE:-}"
SAMPLE_TOKEN="${NP_SAMPLE_TOKEN:-$ROOT_BASENAME}"

DORADO="$NP_DORADO_BASECALLER"
command -v "$DORADO" >/dev/null || { echo "ERROR: dorado not found at $DORADO"; exit 127; }

DEVICE="${NP_DORADO_DEVICE:-cuda:all}"
LIMIT_ARGS=()
MODEL="${NP_DORADO_MODEL:-sup,5mCG_5hmCG,6mA}"
if [[ "${NP_DORADO_TEST_MODE:-0}" == "1" || "$DEVICE" == "cpu" ]]; then
  DEVICE="cpu"
  LIMIT_ARGS=(--max-reads "${NP_DORADO_TEST_LIMIT:-1000}")
  MODEL="${NP_DORADO_TEST_MODEL:-hac}"
  echo "TEST MODE: limiting to ${LIMIT_ARGS[*]}"
fi

echo "=== Dorado Basecalling ==="
echo "ROOT        : $ROOT"
echo "Output BAM  : $ROOT/$OUT_BAM"
echo "Model       : $MODEL"
echo "Min QScore  : 10"
echo "Device      : $DEVICE"
echo "Entry Stage : $ENTRY_STAGE"
"$DORADO" --version || true

# ensure ROOT exists
mkdir -p "$ROOT"

OUT_PATH="$ROOT/$OUT_BAM"

sleep 10

# If OUT_BAM exists and is non-empty, resume; else start fresh
if [[ -s "$OUT_PATH" ]]; then
  echo "Resuming into existing BAM..."
  "$DORADO" basecaller \
    -x "$DEVICE" \
    --min-qscore 10 \
    --resume-from "$OUT_PATH" \
    "${LIMIT_ARGS[@]}" \
    "$MODEL" \
    "$ROOT"/*/pod5/ \
    >> "$OUT_PATH"
else
  echo "Starting fresh..."
  "$DORADO" basecaller \
    -x "$DEVICE" \
    --min-qscore 10 \
    "${LIMIT_ARGS[@]}" \
    "$MODEL" \
    "$ROOT"/*/pod5/ \
    > "$OUT_PATH"
fi

echo "Done: $OUT_PATH"

if [[ -n "$ANALYSIS_RAW_BAM" ]]; then
  mkdir -p "$(dirname "$ANALYSIS_RAW_BAM")"
  cp -u "$OUT_PATH" "$ANALYSIS_RAW_BAM"
fi

sample_lock_clear "$SAMPLE_LOCK_FILE"

if [[ "$ENTRY_STAGE" == "basecall" ]]; then
  echo "Basecall-only mode; Snakemake submission skipped"
  exit 0
fi

if [[ "$ENTRY_STAGE" == "snakemake" ]]; then
  clean_sbatch --export=ALL,CONFIG_FILE="${CONFIG_FILE:-}",NP_CONFIG_FILE="${NP_CONFIG_FILE:-}",NP_ANALYSIS_DIR="${NP_OUT}" "${NP_SNAKEMAKE_SCRIPT}" "${SAMPLE_TOKEN}"
fi
