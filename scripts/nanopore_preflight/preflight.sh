#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"
# shellcheck source=/dev/null
source "${CONFIG_FILE}"
# shellcheck source=lib.sh
source "${NP_SCRIPT_ROOT}/lib.sh"

ENTRY_STAGE="preflight"
CONTINUE_AFTER_ENTRY=0

usage() {
  cat >&2 <<'EOF'
Usage: preflight.sh [BASE] [--entry preflight|basecall|align|snakemake] [--continue]

Stages:
  preflight  Run upload checks only. Add --continue to run the full workflow.
  basecall   Start at Dorado basecalling. Add --continue to align and run Snakemake.
  align      Submit alignment directly. Add --continue to run Snakemake after alignment.
  snakemake  Submit runSnakemake.sh directly from preflight-discovered samples.
EOF
}

ARGS=()
while (( $# )); do
  case "$1" in
    --entry)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --entry requires a value" >&2; usage; exit 1; }
      ENTRY_STAGE="$1"
      ;;
    --continue)
      CONTINUE_AFTER_ENTRY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      ARGS+=("$1")
      ;;
  esac
  shift
done

case "$ENTRY_STAGE" in
  preflight|basecall|align|snakemake) ;;
  *)
    echo "ERROR: invalid --entry '$ENTRY_STAGE'" >&2
    usage
    exit 1
    ;;
esac

if (( ${#ARGS[@]} > 1 )); then
  usage
  exit 1
fi

BASE=${ARGS[0]:-$NP_BASE}
STORAGE_BASE="$NP_STORAGE_BASE"
BASECALLER_SBATCH="${NP_BASECALLER_SBATCH:-${NP_SCRIPT_ROOT}/dorado_basecaller.sh}"

# If user requests CPU/test mode but left default GPU sbatch, switch to CPU header.
if [[ "${NP_DORADO_DEVICE:-}" == "cpu" || "${NP_DORADO_TEST_MODE:-0}" == "1" ]]; then
  if [[ "$BASECALLER_SBATCH" == "${NP_SCRIPT_ROOT}/dorado_basecaller.sh" ]]; then
    BASECALLER_SBATCH="${NP_SCRIPT_ROOT}/dorado_basecaller_cpu_test.sh"
  fi
fi

status=0

declare -a exp_dirs=()
while IFS= read -r -d '' dir; do
  exp_dirs+=("$dir")
done < <(find "$BASE" -maxdepth 1 -mindepth 1 -type d -iregex '.*/[^/]*\(adaptive\|adaptiv\|wgs\)$' -print0 | sort -z)

if (( ${#exp_dirs[@]} == 0 )); then
  echo "No experiment folders ending with *daptive or *WGS found under $BASE" >&2
  exit 1
fi

for exp_dir in "${exp_dirs[@]}"; do
  exp_name=$(basename "$exp_dir")
  echo "Experiment: $exp_name"

  declare -a samples=()
  while IFS= read -r -d '' sample; do
    samples+=("$sample")
  done < <(find "$exp_dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

  if (( ${#samples[@]} == 0 )); then
    echo "  No sample folders found"
    status=1
    continue
  fi

  for sample_dir in "${samples[@]}"; do
    sample_name=$(basename "$sample_dir")
    sample_error=0

    declare -a run_dirs=()
    while IFS= read -r -d '' run_dir; do
      run_dirs+=("$run_dir")
    done < <(find "$sample_dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

    if (( ${#run_dirs[@]} == 0 )); then
      echo "  [$sample_name] ERROR: no run folders found"
      status=1
      continue
    fi

    for run_dir in "${run_dirs[@]}"; do
      run_name=$(basename "$run_dir")
      csv_file=$(find "$run_dir" -maxdepth 1 -type f -name 'output_hash_*.csv' | head -n 1)

      if [[ -z "$csv_file" ]]; then
        echo "  [$sample_name/$run_name] ERROR: output_hash_*.csv missing"
        sample_error=1
        continue
      fi
    done

    if (( sample_error == 0 )); then
      dest="$STORAGE_BASE/$exp_name"
      echo "  [$sample_name] Preflight OK"

      if [[ "$ENTRY_STAGE" == "preflight" && "$CONTINUE_AFTER_ENTRY" -eq 0 ]]; then
        echo "  [$sample_name] Preflight-only mode; copy and downstream submission skipped"
        continue
      fi

      suffix=$([[ "$exp_name" =~ [Ww][Gg][Ss] ]] && echo "hg38_WGS" || echo "hg38_ASv2")
      supsuffix=$([[ "$exp_name" =~ [Ww][Gg][Ss] ]] && echo "sup_WGS" || echo "sup_AS")
      sample_token="${sample_name}_${suffix}"
      basecalled_bam="${dest}/${sample_name}/${sample_name}${supsuffix}.bam"
      aligned_bam="${dest}/${sample_name}/${sample_name}_${suffix}.bam"
      downstream_stage="$ENTRY_STAGE"
      if [[ "$CONTINUE_AFTER_ENTRY" -eq 1 ]]; then
        downstream_stage="snakemake"
      fi

      if [[ "$ENTRY_STAGE" == "align" ]]; then
        echo "  [$sample_name] Submitting alignment directly -> $aligned_bam"
        clean_sbatch --export=ALL,NP_ENTRY_STAGE="$downstream_stage" "${NP_SCRIPT_ROOT}/dorado_align_and_submit.sh" "$basecalled_bam" "$aligned_bam" "$sample_token"
        continue
      fi

      if [[ "$ENTRY_STAGE" == "snakemake" ]]; then
        echo "  [$sample_name] Submitting Snakemake directly -> $sample_token"
        clean_sbatch "${NP_SNAKEMAKE_SCRIPT}" "$sample_token"
        continue
      fi

      mkdir -p "$dest"
      if [[ -e "$dest/$sample_name" ]]; then
        echo "  [$sample_name] Storage target already exists; reusing $dest/$sample_name/"
      else
        echo "  [$sample_name] Copying to $dest/$sample_name/"
        sleep 10
        cp -r "$sample_dir" "$dest/"
      fi

      sleep 10
      echo "  [$sample_name] Submitting Dorado basecaller -> $basecalled_bam"

      clean_sbatch --export=ALL,NP_ENTRY_STAGE="$downstream_stage" "${BASECALLER_SBATCH}" "${dest}/${sample_name}" "${sample_name}${supsuffix}.bam" "$aligned_bam"
    else
      status=1
    fi
  done

done

exit $status
