#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NP_SCRIPT_ROOT:=${SCRIPT_DIR}}"
source "${NP_SCRIPT_ROOT}/lib.sh"

BASE=${1:-$NP_BASE}
STORAGE_BASE="$NP_STORAGE_BASE"
BASECALLER_SBATCH="${NP_BASECALLER_SBATCH:-${NP_SCRIPT_ROOT}/dorado_basecaller2_20260121.sh}"

# If user requests CPU/test mode but left default GPU sbatch, switch to CPU header.
if [[ "${NP_DORADO_DEVICE:-}" == "cpu" || "${NP_DORADO_TEST_MODE:-0}" == "1" ]]; then
  if [[ "$BASECALLER_SBATCH" == "${NP_SCRIPT_ROOT}/dorado_basecaller2_20260121.sh" ]]; then
    BASECALLER_SBATCH="${NP_SCRIPT_ROOT}/dorado_basecaller_cpu_test.sh"
  fi
fi

PYTHON_BIN="${NP_PYTHON:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN=python
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "ERROR: python interpreter not found (tried python3, python)" >&2
  exit 1
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
    dest_sample="$STORAGE_BASE/$exp_name/$sample_name"
    if [[ -e "$dest_sample" ]]; then
      echo "  [$sample_name] Destination already exists at $dest_sample -> skipping (already handled)"
      continue
    fi
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

      mapfile -t pod5_paths < <("$PYTHON_BIN" - "$csv_file" <<'PY'
import csv, sys
from pathlib import Path

csv_path = Path(sys.argv[1])
paths = set()
with csv_path.open(newline="") as f:
    reader = csv.reader(f)
    header_skipped = False
    for row in reader:
        if not header_skipped:
            header_skipped = True
            continue
        if len(row) < 6:
            continue
        fp = row[5].strip()
        if fp.endswith(".pod5"):
            paths.add(fp)

for p in sorted(paths):
    print(p)
PY
      )

      if (( ${#pod5_paths[@]} == 0 )); then
        echo "  [$sample_name/$run_name] ERROR: no POD5 entries found in $(basename "$csv_file")"
        sample_error=1
        continue
      fi

      missing_pod5=()
      zero_size_pod5=()
      existing_pod5=()

      for rel in "${pod5_paths[@]}"; do
        if [[ "$rel" = /* ]]; then
          full="$rel"
        else
          full="$run_dir/$rel"
        fi
        if [[ ! -f "$full" ]]; then
          missing_pod5+=("$rel")
          continue
        fi

        size_bytes=$(stat -c%s "$full" 2>/dev/null || echo -1)
        if (( size_bytes <= 0 )); then
          zero_size_pod5+=("$rel")
          continue
        fi

        existing_pod5+=("$full")
      done

      if (( ${#missing_pod5[@]} )); then
        echo "  [$sample_name/$run_name] ERROR: POD5 files listed in CSV but missing on disk: ${missing_pod5[*]}"
        sample_error=1
      fi

      if (( ${#zero_size_pod5[@]} )); then
        echo "  [$sample_name/$run_name] ERROR: POD5 files are zero bytes (likely truncated): ${zero_size_pod5[*]}"
        sample_error=1
      fi

      if (( ${#existing_pod5[@]} )); then
        pod5_recheck_secs=${NP_POD5_RECHECK_SECONDS:-10}
        (( pod5_recheck_secs < 1 )) && pod5_recheck_secs=1

        declare -A pod5_size_before=()
        for f in "${existing_pod5[@]}"; do
          pod5_size_before["$f"]=$(stat -c%s "$f" 2>/dev/null || echo -1)
        done

        sleep "$pod5_recheck_secs"

        growing_pod5=()
        for f in "${existing_pod5[@]}"; do
          size_after=$(stat -c%s "$f" 2>/dev/null || echo -1)
          if [[ "${pod5_size_before[$f]}" != "$size_after" ]]; then
            growing_pod5+=("${f#$run_dir/}")
          fi
        done

        if (( ${#growing_pod5[@]} )); then
          echo "  [$sample_name/$run_name] ERROR: POD5 files still changing size (likely still writing): ${growing_pod5[*]}"
          sample_error=1
        fi
      fi
    done

    if (( sample_error == 0 )); then
      dest="$STORAGE_BASE/$exp_name"
      echo "  [$sample_name] Preflight OK -> copying to $dest/$sample_name/"
      mkdir -p "$dest_sample"
      sleep 10
      rsync -a --ignore-existing "$sample_dir"/ "$dest_sample"/

      # After a successful move, run alignment with doradoAligner
      sleep 10
      align_input=$(find "$dest_sample" -type f -path '*/bam_pass/*.bam' | sort | head -n 1)
      if [[ -z "$align_input" ]]; then
        echo "  [$sample_name] WARNING: No BAM found under bam_pass for alignment; skipped"
      else
        ref="$NP_REFERENCE"
        suffix=$([[ "$exp_name" =~ [Ww][Gg][Ss] ]] && echo "hg38_WGS" || echo "hg38_ASv2")
        supsuffix=$([[ "$exp_name" =~ [Ww][Gg][Ss] ]] && echo "sup_WGS" || echo "sup_AS")
        prefix="$dest_sample/${sample_name}_${suffix}"
        echo "  [$sample_name] Submitting doradoAligner via sbatch -> $prefix.bam"

        sbatch "${BASECALLER_SBATCH}" "${dest_sample}" "${sample_name}${supsuffix}.bam" "${prefix}.bam"

      fi
    else
      status=1
    fi
  done

done

exit $status
