#!/usr/bin/env bash
#
# Recursive batch rename of the single-sample VCF sample column.
# Outputs are placed directly in ./renamed_vcfs/ unless --inplace is used.
#
# Usage:
#   sbatch rename_sample_name_VCF_recursive.sh </path/to/vcfs/dir/> [NEWNAME] [--inplace]

#SBATCH --account=nanopore_kga
#SBATCH -J vcf_rename_flat
#SBATCH -c 1
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH -o vcf_rename_flat.%j.out
#SBATCH -e vcf_rename_flat.%j.err

set -euo pipefail

if [[ $# -lt 1 ]]; then
  >&2 echo "Usage: sbatch $0 </path/to/vcfs/dir/> [NEWNAME] [--inplace]"
  exit 1
fi

VCF_DIR="$1"
NEWNAME="${2:-SAMPLE}"
INPLACE="${3:-}"

if [[ ! -d "$VCF_DIR" ]]; then
  >&2 echo "ERROR: Not a directory: $VCF_DIR"
  exit 1
fi
[[ "${VCF_DIR}" != */ ]] && VCF_DIR="${VCF_DIR}/"

OUT_DIR="${VCF_DIR%/}/renamed_vcfs"
if [[ "$INPLACE" != "--inplace" ]]; then
  mkdir -p "$OUT_DIR"
fi

if [[ -f "/home/$USER/miniforge3/etc/profile.d/conda.sh" ]]; then
  source "/home/$USER/miniforge3/etc/profile.d/conda.sh"
else
  if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
  fi
fi
conda activate samtools_env

command -v bcftools >/dev/null 2>&1 || { echo "ERROR: bcftools not found in environment"; exit 1; }
command -v tabix >/dev/null 2>&1 || { echo "ERROR: tabix not found in environment"; exit 1; }

if [[ "$INPLACE" == "--inplace" ]]; then
  mapfile -d '' VFILES < <(find "$VCF_DIR" \( -type f -o -type l \) \( -name "*.vcf" -o -name "*.vcf.gz" \) -print0)
else
  mapfile -d '' VFILES < <(find "$VCF_DIR" \
    -path "$OUT_DIR" -prune -o \
    \( -type f -o -type l \) \( -name "*.vcf" -o -name "*.vcf.gz" \) -print0)
fi

if [[ ${#VFILES[@]} -eq 0 ]]; then
  echo "No .vcf or .vcf.gz files found under: ${VCF_DIR}"
  exit 0
fi

echo "Found ${#VFILES[@]} VCF files under ${VCF_DIR}"
echo "Target sample name: ${NEWNAME}"
[[ "$INPLACE" == "--inplace" ]] && echo "Mode: IN-PLACE (files will be overwritten)" || echo "Mode: COPY (outputs in $OUT_DIR/)"

for VCF in "${VFILES[@]}"; do
  echo "----"
  echo "Processing: $VCF"

  NS=$(bcftools query -l "$VCF" | wc -l | tr -d ' ')
  if [[ "$NS" != "1" ]]; then
    echo "SKIP: $VCF has $NS samples (script expects single-sample)."
    continue
  fi

  if [[ "$INPLACE" == "--inplace" ]]; then
    OUT="$VCF"
  else
    base=$(basename -- "$VCF")
    rel_path="${VCF#$VCF_DIR}"
    prefix=$(dirname "$rel_path" | tr '/' '_')
    [[ "$prefix" == "." ]] && prefix=""
    OUT="${OUT_DIR}/${prefix:+${prefix}_}${base}"
  fi

  if [[ "$VCF" =~ \.vcf\.gz$ ]]; then
    TMP="${OUT}.tmp.gz"
    bcftools reheader -s <(printf "%s\n" "$NEWNAME") -o "$TMP" "$VCF"
    tabix -f -p vcf "$TMP"
    mv -f "$TMP" "$OUT"
    mv -f "${TMP}.tbi" "${OUT}.tbi"
  else
    TMP="${OUT}.tmp"
    bcftools reheader -s <(printf "%s\n" "$NEWNAME") -o "$TMP" "$VCF"
    mv -f "$TMP" "$OUT"
  fi

  NAME=$(bcftools query -l "$OUT")
  echo "Renamed sample: $NAME"
done

conda deactivate || true
echo "All done."
