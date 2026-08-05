#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  bash run_containerized_workflow.sh \
    --sample SAMPLE \
    --input-dir /path/to/sup_bams \
    --output-dir /path/to/analysis_root \
    --site-config /path/to/site_config.yaml

This is a blueprint wrapper for a future production container image.
It is not wired into the current workflow automatically.
EOF
}

SAMPLE=""
INPUT_DIR=""
OUTPUT_DIR=""
SITE_CONFIG=""

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

echo "Containerized workflow blueprint"
echo "  sample:      $SAMPLE"
echo "  input-dir:   $INPUT_DIR"
echo "  output-dir:  $OUTPUT_DIR"
echo "  site-config: $SITE_CONFIG"

sample_root="${OUTPUT_DIR}/${SAMPLE}/data/raw"
mkdir -p "${sample_root}"

echo
echo "Expected staging step:"
echo "  stage SUP BAMs from ${INPUT_DIR} into ${sample_root}"
echo
echo "Expected workflow step:"
cat <<EOF
snakemake \\
  -s /opt/workflow/workflows/workflow_AS/Snakefile_AS \\
  --configfile ${SITE_CONFIG} \\
  --config sample=${SAMPLE} analysisDir=${OUTPUT_DIR} \\
  --cores 1
EOF
echo
echo "This wrapper is a blueprint only. The final production image should replace this echo block with the real Snakemake invocation."
