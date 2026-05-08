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
PROJECT="${PROJECT_DIR}/${SAMPLE}"
DONE_MARKER="${PROJECT_DIR}/varseq_done.txt"
ANALYSIS_SAMPLE_DIR="$(dirname "$(dirname "$VCF")")"
RENAMED_VCF_DIR="${ANALYSIS_SAMPLE_DIR}/renamed_vcfs"
VARIANTS_DIR="${ANALYSIS_SAMPLE_DIR}/variants"

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

declare -a IMPORT_FILES=()
declare -A SEEN_IMPORTS=()

add_import_file() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  case "$file" in
    *.tbi|*.csi)
      return 0
      ;;
    *.vcf|*.vcf.gz|*.txt|*.tsv|*.bed)
      ;;
    *)
      return 0
      ;;
  esac

  if [[ -z "${SEEN_IMPORTS[$file]+x}" ]]; then
    IMPORT_FILES+=("$file")
    SEEN_IMPORTS["$file"]=1
  fi
}

add_import_file "$VCF"

for dir in "$RENAMED_VCF_DIR" "$VARIANTS_DIR"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' file; do
      add_import_file "$file"
    done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)
  fi
done

if [[ ${#IMPORT_FILES[@]} -eq 0 ]]; then
  echo "No importable variant files found for sample: $SAMPLE" >&2
  exit 1
fi

echo "Creating VarSeq project: $PROJECT"
printf 'Importing files (%d):\n' "${#IMPORT_FILES[@]}"
printf '  %s\n' "${IMPORT_FILES[@]}"

declare -a VSPIPELINE_CMD=(
  "$VSPIPELINE"
  -c "project_create path=$PROJECT template=$TEMPLATE"
)

for import_file in "${IMPORT_FILES[@]}"; do
  VSPIPELINE_CMD+=(-c "import files=$import_file")
done

VSPIPELINE_CMD+=(
  -c download_required_sources
  -c task_wait
  -c workflow_run
  -c task_wait
)

"${VSPIPELINE_CMD[@]}"

date --iso-8601=seconds > "$DONE_MARKER"
