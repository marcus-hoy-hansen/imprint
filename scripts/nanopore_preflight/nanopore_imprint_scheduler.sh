#!/bin/bash
#SBATCH --job-name=imprint
#SBATCH --account=nanopore_KGA
#SBATCH --cpus-per-task=1
#SBATCH --mem=500M
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --output=logs/imprint-watch-%j.out
##SBATCH --mail-user=you@example.com
##SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail
umask 002

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"
# shellcheck source=/dev/null
source "${CONFIG_FILE}"
# shellcheck source=lib.sh
source "${NP_SCRIPT_ROOT}/lib.sh"

INTERVAL="${INTERVAL:-$NP_WATCH_INTERVAL}"           # watcher frequency
WEEKLY_INTERVAL_DAYS="${WEEKLY_INTERVAL_DAYS:-$NP_WEEKLY_INTERVAL_DAYS}"

RUN_CMD="${RUN_CMD:-${NP_PROJECT_ROOT}/workflow_dev/RUN.sh}"      # main workload
MAINT_CMD="${MAINT_CMD:-${NP_SCRIPT_ROOT}/weekly.sh}"     # maintenance hook (optional)

CONDA_ENV="${CONDA_ENV:-base}"
STATE_DIR="${STATE_DIR:-$NP_WATCH_STATE_DIR}"
LAST_MAINT_FILE="$STATE_DIR/last_maintenance.ts"

# ======================================================
# FLAGS
# ======================================================

WATCH=0
if [[ "${1:-}" == "--watch" ]]; then
  WATCH=1
  shift
fi

EXTRA_ARGS=("$@")
if (( ${#EXTRA_ARGS[@]} == 0 )); then
  EXTRA_ARGS=(--entry preflight --continue)
fi

mkdir -p "$STATE_DIR"

# ======================================================
# ENVIRONMENT
# ======================================================

maybe_activate_conda "$CONDA_ENV"

echo "[INFO] Watch run started at $(date)"

# ======================================================
# WEEKLY MAINTENANCE (time-based, not cron-based)
# ======================================================

now=$(date +%s)
last_maint=0

if [[ -f "$LAST_MAINT_FILE" ]]; then
  last_maint=$(cat "$LAST_MAINT_FILE")
fi

max_age=$(( WEEKLY_INTERVAL_DAYS * 24 * 3600 ))

if (( now - last_maint > max_age )); then
  if [[ -x "$MAINT_CMD" ]]; then
    echo "[INFO] Running weekly maintenance"
    "$MAINT_CMD"
    echo "$now" > "$LAST_MAINT_FILE"
  else
    echo "[INFO] Weekly maintenance script not found/executable – skipping"
  fi
else
  echo "[INFO] Weekly maintenance not due"
fi

# ======================================================
# SUBMIT MAIN WORKLOAD
# ======================================================

echo "[INFO] Submitting workload: $RUN_CMD"
bash "$RUN_CMD" "${EXTRA_ARGS[@]}"

echo "[INFO] Workload submission finished at $(date)"

# ======================================================
# SELF-RESUBMIT
# ======================================================

if [[ "$WATCH" -eq 1 ]]; then
  echo "[INFO] Rescheduling in $INTERVAL"
  clean_sbatch --begin=now+${INTERVAL} "${NP_SCRIPT_ROOT}/nanopore_imprint_scheduler.sh" --watch "${EXTRA_ARGS[@]}"
fi
