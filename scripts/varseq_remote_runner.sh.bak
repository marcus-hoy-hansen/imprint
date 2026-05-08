#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <sample> <vcf> <template> <project_dir>" >&2
  exit 1
fi

SAMPLE="$1"
VCF="$2"
TEMPLATE="$3"
PROJECT_DIR="$4"

VERSION=$(tr -d '\n' < /scratch/share/varseq/default_version.txt)
VSPIPELINE="/scratch/share/varseq/VarSeq-${VERSION}/vspipeline"
PROJECT="${PROJECT_DIR}/project"
DONE_MARKER="${PROJECT_DIR}/varseq_done.txt"

mkdir -p "$PROJECT_DIR"

if [[ -e "$DONE_MARKER" ]]; then
  echo "VarSeq project already completed: $PROJECT"
  exit 0
fi

if [[ -e "$PROJECT" ]]; then
  echo "VarSeq project exists without completion marker, removing stale project: $PROJECT" >&2
  sleep 30
  rm -rf "$PROJECT"
fi

"$VSPIPELINE" \
  -c project_create path="$PROJECT" template="$TEMPLATE" \
  -c import files="$VCF" \
  -c download_required_sources \
  -c task_wait \
  -c workflow_run \
  -c task_wait

date --iso-8601=seconds > "$DONE_MARKER"
