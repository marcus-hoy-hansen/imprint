#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 8 ]]; then
  echo "Usage: $0 <sample> <vcf> <template> <project_dir> <submit_host> <host> <remote_script> <marker_out>" >&2
  exit 1
fi

SAMPLE="$1"
VCF="$2"
TEMPLATE="$3"
PROJECT_DIR="$4"
SUBMIT_HOST="$5"
HOST="$6"
REMOTE_SCRIPT="$7"
MARKER_OUT="$8"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_SESSION="varseq_${SAMPLE}"
SUBMIT_SCRIPT="${SCRIPT_DIR}/submit_varseq.sh"

mkdir -p "$(dirname "$MARKER_OUT")"

ssh -o BatchMode=yes "$SUBMIT_HOST" bash -s <<EOF
set -euo pipefail
tmux has-session -t "$TMUX_SESSION" 2>/dev/null && tmux kill-session -t "$TMUX_SESSION"
tmux new-session -d -s "$TMUX_SESSION" "bash '$SUBMIT_SCRIPT' '$SAMPLE' '$VCF' '$TEMPLATE' '$PROJECT_DIR' '$HOST' '$REMOTE_SCRIPT'"
EOF

{
  echo "sample=$SAMPLE"
  echo "submit_host=$SUBMIT_HOST"
  echo "host=$HOST"
  echo "remote_script=$REMOTE_SCRIPT"
  echo "vcf=$VCF"
  echo "template=$TEMPLATE"
  echo "project_dir=$PROJECT_DIR"
  echo "tmux_session=$TMUX_SESSION"
  echo "submitted_at=$(date --iso-8601=seconds)"
} > "$MARKER_OUT"
