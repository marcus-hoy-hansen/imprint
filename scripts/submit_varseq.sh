#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 <sample> <vcf> <template> <project_dir> <host> <remote_script>" >&2
  exit 1
fi

SAMPLE="$1"
VCF="$2"
TEMPLATE="$3"
PROJECT_DIR="$4"
HOST="$5"
REMOTE_SCRIPT="$6"
REMOTE_LOG="${PROJECT_DIR}/varseq_remote.log"

ssh -o BatchMode=yes "$HOST" bash -s <<EOF
set -euo pipefail
mkdir -p "$PROJECT_DIR"
exec "$REMOTE_SCRIPT" "$SAMPLE" "$VCF" "$TEMPLATE" "$PROJECT_DIR" > "$REMOTE_LOG" 2>&1
EOF
