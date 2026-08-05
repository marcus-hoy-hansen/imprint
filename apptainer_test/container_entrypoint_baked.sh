#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  bash /opt/workflow/apptainer_test/container_entrypoint_baked.sh \
    --sample SAMPLE \
    --input-dir /path/to/sup_bams \
    --output-dir /path/to/analysis_root \
    --site-config /path/to/runtime_site.conf \
    [--mode copy|link] \
    [--cores N] \
    [--dry-run]
EOF
}

SAMPLE=""
INPUT_DIR=""
OUTPUT_DIR=""
SITE_CONFIG=""
STAGE_MODE="link"
CORES="1"
DRY_RUN=0

while (( $# )); do
  case "$1" in
    --sample) shift; SAMPLE="${1:-}" ;;
    --input-dir) shift; INPUT_DIR="${1:-}" ;;
    --output-dir) shift; OUTPUT_DIR="${1:-}" ;;
    --site-config) shift; SITE_CONFIG="${1:-}" ;;
    --mode) shift; STAGE_MODE="${1:-}" ;;
    --cores) shift; CORES="${1:-}" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ -z "$SAMPLE" || -z "$INPUT_DIR" || -z "$OUTPUT_DIR" || -z "$SITE_CONFIG" ]]; then
  usage
  exit 1
fi

# shellcheck source=/dev/null
source "$SITE_CONFIG"

export PATH="/opt/workflow/runtime_bin:$PATH"
export NP_CONDA_ENV=""
export NP_CONDA_PROFILE=""

if [[ ! -x /opt/workflow/runtime_envs/samtools/bin/samtools ]]; then
  echo "ERROR: runtime envs not available at /opt/workflow/runtime_envs" >&2
  echo "Mount them with:" >&2
  echo "  --bind /path/to/runtime_envs:/opt/workflow/runtime_envs" >&2
  exit 1
fi

IFS="_" read -r SAMPLE_ID REF TYPE <<< "$SAMPLE"

case "$REF" in
  hg38) REFFILE="${HG38_REF:-hg38_noAlt.fasta}" ;;
  T2T) REFFILE="${T2T_REF:-GCF_009914755.1_T2T-CHM13v2.0_genomic.fna}" ;;
  *) echo "ERROR: unsupported reference token: $REF" >&2; exit 1 ;;
esac

if [[ "$TYPE" =~ ^AS ]]; then
  WORKFLOW="/opt/workflow/workflows/workflow_AS/Snakefile_AS"
  AS_VERSION="${TYPE#AS}"
elif [[ "$TYPE" == "WGS" ]]; then
  WORKFLOW="/opt/workflow/workflows/workflow_WGS/Snakefile_WGS"
  AS_VERSION=""
else
  echo "ERROR: unsupported sample type token: $TYPE" >&2
  exit 1
fi

RAW_DIR="${OUTPUT_DIR}/${SAMPLE}/data/raw"
mkdir -p "$RAW_DIR"

mapfile -t INPUT_BAMS < <(find "$INPUT_DIR" -maxdepth 1 -type f -name '*.bam' ! -name '*.bai' | sort)
if [[ "${#INPUT_BAMS[@]}" -eq 0 ]]; then
  echo "ERROR: no BAM files found in $INPUT_DIR" >&2
  exit 1
fi

for bam in "${INPUT_BAMS[@]}"; do
  target="${RAW_DIR}/$(basename "$bam")"
  case "$STAGE_MODE" in
    copy) cp -u "$bam" "$target" ;;
    link) ln -sfn "$bam" "$target" ;;
    *) echo "ERROR: --mode must be copy or link" >&2; exit 1 ;;
  esac
done

cd /opt/workflow

CMD=(
  snakemake
  -s "$WORKFLOW"
  --configfile /opt/workflow/config/config.yaml
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
  --cores "${CORES}"
  --jobs 1
  --executor local
  --keep-going
  --latency-wait 120
  --keep-incomplete
  --rerun-incomplete
)

echo "Baked workflow runtime"
echo "  sample:      $SAMPLE"
echo "  input-dir:   $INPUT_DIR"
echo "  output-dir:  $OUTPUT_DIR"
echo "  site-config: $SITE_CONFIG"
echo "  workflow:    $WORKFLOW"
echo "  BAM count:   ${#INPUT_BAMS[@]}"
echo "  cores:       $CORES"
echo
printf 'Command:\n'
printf '  %q' "${CMD[@]}"
printf '\n'

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

"${CMD[@]}"
