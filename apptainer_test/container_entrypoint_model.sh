#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  bash container_entrypoint_model.sh \
    --sample SAMPLE \
    --input-dir /path/to/sup_bams \
    --output-dir /path/to/analysis_root \
    --site-config /path/to/site_config.conf \
    [--mode copy|link] \
    [--dry-run]

This is a complete workflow model wrapper.
It stages SUP BAMs into the output analysis tree and constructs the real Snakemake call.
EOF
}

SAMPLE=""
INPUT_DIR=""
OUTPUT_DIR=""
SITE_CONFIG=""
STAGE_MODE="link"
DRY_RUN=0

while (( $# )); do
  case "$1" in
    --sample)
      shift
      SAMPLE="${1:-}"
      ;;
    --input-dir)
      shift
      INPUT_DIR="${1:-}"
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="${1:-}"
      ;;
    --site-config)
      shift
      SITE_CONFIG="${1:-}"
      ;;
    --mode)
      shift
      STAGE_MODE="${1:-}"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$SAMPLE" || -z "$INPUT_DIR" || -z "$OUTPUT_DIR" || -z "$SITE_CONFIG" ]]; then
  usage
  exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "ERROR: input directory not found: $INPUT_DIR" >&2
  exit 1
fi

if [[ ! -f "$SITE_CONFIG" ]]; then
  echo "ERROR: site config not found: $SITE_CONFIG" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$SITE_CONFIG"

IFS="_" read -r SAMPLE_ID REF TYPE <<< "$SAMPLE"

if [[ -z "${SAMPLE_ID:-}" || -z "${REF:-}" || -z "${TYPE:-}" ]]; then
  echo "ERROR: sample token must look like <sample>_<reference>_<type>" >&2
  exit 1
fi

case "$REF" in
  hg38)
    REFFILE="${HG38_REF:-hg38_noAlt.fasta}"
    ;;
  T2T)
    REFFILE="${T2T_REF:-GCF_009914755.1_T2T-CHM13v2.0_genomic.fna}"
    ;;
  *)
    echo "ERROR: unsupported reference token in sample: $REF" >&2
    exit 1
    ;;
esac

if [[ "$TYPE" =~ ^AS ]]; then
  WORKFLOW="workflows/workflow_AS/Snakefile_AS"
  AS_VERSION="${TYPE#AS}"
elif [[ "$TYPE" == "WGS" ]]; then
  WORKFLOW="workflows/workflow_WGS/Snakefile_WGS"
  AS_VERSION=""
else
  echo "ERROR: unsupported sample type token in sample: $TYPE" >&2
  exit 1
fi

RAW_DIR="${OUTPUT_DIR}/${SAMPLE}/data/raw"
mkdir -p "$RAW_DIR"

mapfile -t INPUT_BAMS < <(find "$INPUT_DIR" -maxdepth 1 -type f -name '*.bam' ! -name '*.bai' | sort)

if [[ "${#INPUT_BAMS[@]}" -eq 0 ]]; then
  echo "ERROR: no BAM files found in input directory: $INPUT_DIR" >&2
  exit 1
fi

for bam in "${INPUT_BAMS[@]}"; do
  target="${RAW_DIR}/$(basename "$bam")"
  case "$STAGE_MODE" in
    copy)
      cp -u "$bam" "$target"
      ;;
    link)
      ln -sfn "$bam" "$target"
      ;;
    *)
      echo "ERROR: --mode must be copy or link" >&2
      exit 1
      ;;
  esac
done

CMD=(
  snakemake
  -s "$WORKFLOW"
  --configfile "config/config.yaml"
  --config
  "sample=${SAMPLE}"
  "refGenome=${REF}"
  "refFile=${REFFILE}"
  "analysisDir=${OUTPUT_DIR}"
  "referenceDir=${REFERENCE_DIR}"
  "dataDir=${DATA_DIR}"
  "softwareDir=${SOFTWARE_DIR}"
  "clair3Model=${CLAIR3_MODEL}"
)

if [[ -n "$AS_VERSION" ]]; then
  CMD+=("ASversion=${AS_VERSION}")
fi

CMD+=(
  --rerun-incomplete
)

echo "Workflow model"
echo "  sample:      $SAMPLE"
echo "  input-dir:   $INPUT_DIR"
echo "  output-dir:  $OUTPUT_DIR"
echo "  workflow:    $WORKFLOW"
echo "  ref file:    $REFFILE"
echo "  stage mode:  $STAGE_MODE"
echo "  BAM count:   ${#INPUT_BAMS[@]}"
echo
printf 'Command:\n'
printf '  %q' "${CMD[@]}"
printf '\n'

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

"${CMD[@]}"
