#!/usr/bin/env bash

#SBATCH --job-name=t2t-qc-align
#SBATCH --account=nanopore_kga
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/t2t_qc_align_sort-%j.out
#SBATCH --error=logs/t2t_qc_align_sort-%j.out

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sbatch scripts/t2t_qc_align_sort.sh <sup_unmapped.bam> [output.sorted.bam] [sample_name] [reference.fasta]

Align an input Dorado SUP BAM to the T2T reference for QC-only use, then sort and index the result.

Arguments:
  <sup_unmapped.bam>   Input SUP BAM, typically an unmapped Dorado BAM.
  [output.sorted.bam]  Output sorted BAM path. Default: next to input with .t2t.sorted.bam suffix.
  [sample_name]        Optional sample name. Default: basename of output BAM without .bam.
  [reference.fasta]    Optional T2T reference FASTA.

Defaults:
  reference.fasta = /faststorage/project/nanopore_kga/STORAGE/resources/references/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna
EOF
}

if [[ $# -lt 1 || $# -gt 4 ]]; then
  usage >&2
  exit 1
fi

INPUT_BAM="$1"
OUTPUT_BAM="${2:-}"
SAMPLE_NAME="${3:-}"
REFERENCE_FASTA="${4:-/faststorage/project/nanopore_kga/STORAGE/resources/references/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna}"

if [[ ! -f "$INPUT_BAM" ]]; then
  echo "ERROR: input BAM not found: $INPUT_BAM" >&2
  exit 1
fi

if [[ ! -f "$REFERENCE_FASTA" ]]; then
  echo "ERROR: reference FASTA not found: $REFERENCE_FASTA" >&2
  exit 1
fi

if [[ -z "$OUTPUT_BAM" ]]; then
  input_dir="$(dirname "$INPUT_BAM")"
  input_base="$(basename "$INPUT_BAM" .bam)"
  input_base="${input_base/_hg38_/_}"
  OUTPUT_BAM="${input_dir}/${input_base}.t2t.sorted.bam"
fi

if [[ -z "$SAMPLE_NAME" ]]; then
  SAMPLE_NAME="$(basename "$OUTPUT_BAM" .bam)"
fi

OUTPUT_DIR="$(dirname "$OUTPUT_BAM")"
mkdir -p "$OUTPUT_DIR"

DORADO="${NP_DORADO_ALIGNER:-/home/$USER/dorado-1.2.0-linux-x64/bin/dorado}"
if ! command -v "$DORADO" >/dev/null 2>&1; then
  echo "ERROR: dorado aligner not found at $DORADO" >&2
  exit 127
fi

export PATH="/home/$USER/miniforge3/condabin:/home/$USER/miniforge3/bin:$PATH"
source "/home/$USER/miniforge3/etc/profile.d/conda.sh"
conda activate bwa >/dev/null 2>&1 || true

if ! command -v samtools >/dev/null 2>&1; then
  echo "ERROR: samtools not found in PATH" >&2
  exit 127
fi

TMP_PREFIX="${OUTPUT_BAM%.bam}.tmp"
trap 'rm -f "${TMP_PREFIX}.bam"' EXIT

echo "=== T2T QC Align + Sort ==="
echo "Input BAM:      $INPUT_BAM"
echo "Output BAM:     $OUTPUT_BAM"
echo "Sample name:    $SAMPLE_NAME"
echo "Reference:      $REFERENCE_FASTA"
echo "Dorado:         $DORADO"
echo "Threads:        ${SLURM_CPUS_PER_TASK:-32}"

"$DORADO" aligner \
  "$REFERENCE_FASTA" \
  "$INPUT_BAM" \
  --mm2-opts "-Y" \
  --threads "${SLURM_CPUS_PER_TASK:-32}" \
  > "${TMP_PREFIX}.bam"

samtools sort \
  -@ "${SLURM_CPUS_PER_TASK:-32}" \
  -o "$OUTPUT_BAM" \
  "${TMP_PREFIX}.bam"

samtools index \
  -@ "${SLURM_CPUS_PER_TASK:-32}" \
  "$OUTPUT_BAM"

rm -f "${TMP_PREFIX}.bam"
trap - EXIT

echo "Wrote:"
echo "  $OUTPUT_BAM"
echo "  ${OUTPUT_BAM}.bai"
