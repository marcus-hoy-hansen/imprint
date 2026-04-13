#!/bin/bash
#SBATCH --job-name=dorado-sup
#SBATCH --account=nanopore_kga
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# Usage:
#   sbatch dorado_basecaller.sh <RUN_SAMPLE_ROOT> [OUT_BAM] [ALIGNED_BAM]
# Example:
#   sbatch dorado_basecaller.sh 251006_Nanopore_Adaptive/04203-21
#   -> outputs 251006_Nanopore_Adaptive/04203-21/04203-21_sup.bam

set -euo pipefail
umask 002

# shellcheck source=lib.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NP_SCRIPT_ROOT:=${SCRIPT_DIR}}"
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
"$DORADO" --version || true

# ensure ROOT exists
mkdir -p "$ROOT"

OUT_PATH="$ROOT/$OUT_BAM"

if [[ -s "$OUT_PATH" ]]; then
  echo "Basecalled BAM already present; skipping basecalling: $OUT_PATH"
else
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
fi

echo "Done: $OUT_PATH"

if [[ -n "$ALIGNED_BAM" ]]; then
  echo "Submitting for alignment and nanoimprint"
  sbatch "${NP_SCRIPT_ROOT}/dorado_align_and_nanoimprint.sh" "$OUT_PATH" "$ALIGNED_BAM"
fi
