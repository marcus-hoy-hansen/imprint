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
Usage: preflight.sh [BASE] [--entry preflight|basecall|align|snakemake] [--analysis-dir /path] [--continue]

Stages:
  preflight  Run upload checks only. Add --continue to run the full workflow.
  basecall   Start at Dorado basecalling. Add --continue to stage SUP BAM and run Snakemake.
  align      Legacy alias that stages an existing SUP BAM and optionally runs Snakemake.
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
    --analysis-dir)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --analysis-dir requires a value" >&2; usage; exit 1; }
      NP_OUT="$1"
      NP_ANALYSIS_DIR="$1"
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
LOCK_ROOT="${NP_WATCH_STATE_DIR}/sample_locks"

# Ensure downstream sbatch jobs inherit any runtime overrides such as
# --analysis-dir instead of falling back to config defaults.
export NP_OUT
export NP_ANALYSIS_DIR
export NP_BASE
export NP_STORAGE_BASE

# If user requests CPU/test mode but left default GPU sbatch, switch to CPU header.
if [[ "${NP_DORADO_DEVICE:-}" == "cpu" || "${NP_DORADO_TEST_MODE:-0}" == "1" ]]; then
  if [[ "$BASECALLER_SBATCH" == "${NP_SCRIPT_ROOT}/dorado_basecaller.sh" ]]; then
    BASECALLER_SBATCH="${NP_SCRIPT_ROOT}/dorado_basecaller_cpu_test.sh"
  fi
fi

status=0

submit_stage_with_lock() {
  local lock_file="$1"
  local sample_token="$2"
  local stage="$3"
  shift 3

  local submit_output
  local jobid

  sample_lock_write "$lock_file" "$stage" "pending" "$sample_token"

  if ! submit_output="$(clean_sbatch "$@")"; then
    sample_lock_clear "$lock_file"
    return 1
  fi

  echo "$submit_output"

  jobid="$(awk '/Submitted batch job/ {print $4}' <<< "$submit_output")"
  if [[ -z "$jobid" ]]; then
    echo "ERROR: failed to parse sbatch job id for $sample_token ($stage)" >&2
    sample_lock_clear "$lock_file"
    return 1
  fi

  sample_lock_write "$lock_file" "$stage" "$jobid" "$sample_token"
}

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
      analysis_sample_dir="${NP_OUT}/${sample_token}"
      analysis_raw_dir="${analysis_sample_dir}/data/raw"
      analysis_raw_bam="${analysis_raw_dir}/${sample_name}${supsuffix}.bam"
      varseq_marker="${analysis_sample_dir}/varseq/${sample_token}_varseq_submitted.txt"
      lock_file="${LOCK_ROOT}/${sample_token}.lock"
      downstream_stage="$ENTRY_STAGE"
      if [[ "$CONTINUE_AFTER_ENTRY" -eq 1 ]]; then
        downstream_stage="snakemake"
      fi

      if [[ -f "$lock_file" ]]; then
        lock_stage="$(awk -F= '/^stage=/{print $2}' "$lock_file" | tail -n 1)"
        lock_jobid="$(awk -F= '/^jobid=/{print $2}' "$lock_file" | tail -n 1)"

        if [[ "$lock_jobid" == "pending" ]]; then
          echo "  [$sample_name] Submission lock exists for stage $lock_stage; skipping"
          continue
        fi

        if [[ -n "$lock_jobid" ]] && command -v squeue >/dev/null 2>&1 && squeue -h -j "$lock_jobid" 2>/dev/null | grep -q .; then
          echo "  [$sample_name] Active lock exists for stage $lock_stage (job $lock_jobid); skipping"
          continue
        fi

        case "$lock_stage" in
          basecall)
            lock_expected="$basecalled_bam"
            ;;
          *)
            echo "  [$sample_name] Unknown lock stage '$lock_stage'; skipping for manual review"
            continue
            ;;
        esac

        if [[ -s "$lock_expected" ]]; then
          echo "  [$sample_name] Clearing stale $lock_stage lock; expected output exists"
          sample_lock_clear "$lock_file"
        else
          echo "  [$sample_name] Stale $lock_stage lock detected; expected output missing; skipping"
          continue
        fi
      fi

      if [[ "$ENTRY_STAGE" == "align" ]]; then
        if [[ -s "$analysis_raw_bam" ]]; then
          if [[ "$CONTINUE_AFTER_ENTRY" -eq 1 ]]; then
            echo "  [$sample_name] Analysis raw BAM exists; submitting Snakemake -> $sample_token"
            clean_sbatch "${NP_SNAKEMAKE_SCRIPT}" "$sample_token"
          else
            echo "  [$sample_name] Analysis raw BAM exists; Snakemake-ready input already present"
          fi
          continue
        fi

        if [[ -s "$basecalled_bam" ]]; then
          mkdir -p "$analysis_raw_dir"
          cp -u "$basecalled_bam" "$analysis_raw_bam"
          if [[ "$CONTINUE_AFTER_ENTRY" -eq 1 ]]; then
            echo "  [$sample_name] SUP BAM exists; copied to analysis and submitting Snakemake -> $sample_token"
            clean_sbatch "${NP_SNAKEMAKE_SCRIPT}" "$sample_token"
          else
            echo "  [$sample_name] SUP BAM exists; copied to analysis"
          fi
          continue
        fi

        echo "  [$sample_name] Expected SUP BAM missing; cannot continue from align entry"
        continue
      fi

      if [[ "$ENTRY_STAGE" == "snakemake" ]]; then
        if [[ ! -s "$analysis_raw_bam" && -s "$basecalled_bam" ]]; then
          mkdir -p "$analysis_raw_dir"
          cp -u "$basecalled_bam" "$analysis_raw_bam"
          echo "  [$sample_name] Copied SUP BAM into analysis raw -> $analysis_raw_bam"
        fi
        echo "  [$sample_name] Submitting Snakemake directly -> $sample_token"
        clean_sbatch "${NP_SNAKEMAKE_SCRIPT}" "$sample_token"
        continue
      fi

      if [[ "$CONTINUE_AFTER_ENTRY" -eq 1 ]]; then
        if [[ -s "$varseq_marker" ]]; then
          echo "  [$sample_name] Final workflow marker exists; downstream skipped -> $varseq_marker"
          continue
        fi

        if [[ -s "$analysis_raw_bam" ]]; then
          echo "  [$sample_name] Analysis raw BAM exists; submitting Snakemake -> $sample_token"
          clean_sbatch "${NP_SNAKEMAKE_SCRIPT}" "$sample_token"
          continue
        fi

        if [[ -s "$basecalled_bam" ]]; then
          mkdir -p "$analysis_raw_dir"
          cp -u "$basecalled_bam" "$analysis_raw_bam"
          echo "  [$sample_name] SUP BAM exists; copied to analysis and submitting Snakemake -> $sample_token"
          clean_sbatch "${NP_SNAKEMAKE_SCRIPT}" "$sample_token"
          continue
        fi
      elif [[ "$ENTRY_STAGE" == "basecall" && -s "$basecalled_bam" ]]; then
        echo "  [$sample_name] Basecalled BAM exists; basecalling skipped"
        continue
      fi

      mkdir -p "$dest"
      if [[ -e "$dest/$sample_name" ]]; then
        echo "  [$sample_name] Storage target already exists; reusing $dest/$sample_name/"
      else
        echo "  [$sample_name] Moving to $dest/$sample_name/"
        sleep 10
        mv "$sample_dir" "$dest/"
      fi

      sleep 10
      echo "  [$sample_name] Submitting Dorado basecaller -> $basecalled_bam"

      submit_stage_with_lock "$lock_file" "$sample_token" "basecall" \
        --export=ALL,NP_ENTRY_STAGE="$downstream_stage",NP_SAMPLE_LOCK_FILE="$lock_file",NP_SAMPLE_TOKEN="$sample_token" \
        "${BASECALLER_SBATCH}" "${dest}/${sample_name}" "${sample_name}${supsuffix}.bam" "$analysis_raw_bam"
    else
      status=1
    fi
  done

done

exit $status
