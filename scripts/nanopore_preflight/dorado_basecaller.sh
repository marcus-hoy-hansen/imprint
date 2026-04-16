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
#   sbatch dorado_basecaller.sh <RUN_SAMPLE_ROOT> [OUT_BAM] [ALIGNED_BAM]
# Example:
#   sbatch dorado_basecaller.sh 251006_Nanopore_Adaptive/04203-21
#   -> outputs 251006_Nanopore_Adaptive/04203-21/04203-21_sup.bam

set -euo pipefail
umask 002

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"
# shellcheck source=/dev/null
source "${CONFIG_FILE}"
# shellcheck source=lib.sh
source "${NP_SCRIPT_ROOT}/lib.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <RUN_SAMPLE_ROOT> [OUT_BAM] [ALIGNED_BAM]" >&2
  exit 1
fi

ROOT="$1"                            # e.g. 251006_Nanopore_Adaptive/04203-21
ROOT_BASENAME="$(basename "$ROOT")"  # e.g. 04203-21
DEFAULT_OUT="${ROOT_BASENAME}_sup.bam"
OUT_BAM="${2:-$DEFAULT_OUT}"         # name only
ALIGNED_BAM="${3:-}"
ENTRY_STAGE="${NP_ENTRY_STAGE:-snakemake}"

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

if [[ -n "$ALIGNED_BAM" ]]; then
  if [[ "$ENTRY_STAGE" == "basecall" ]]; then
    echo "Basecall-only mode; alignment and downstream submission skipped"
    exit 0
  fi

  echo "Submitting for alignment and nanoimprint"
  clean_sbatch --export=ALL,NP_ENTRY_STAGE="$ENTRY_STAGE" "${NP_SCRIPT_ROOT}/dorado_align_and_submit.sh" "$OUT_PATH" "$ALIGNED_BAM"
fi
