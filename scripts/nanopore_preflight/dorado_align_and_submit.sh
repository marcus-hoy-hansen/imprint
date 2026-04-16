#!/bin/bash

#SBATCH --account nanopore_kga
#SBATCH -c 32
#SBATCH --mem 32g
#SBATCH --time 12:00:00

set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh}"
# shellcheck source=/dev/null
source "${CONFIG_FILE}"
# shellcheck source=lib.sh
source "${NP_SCRIPT_ROOT}/lib.sh"

#Check if sample name was provided in command
if [ $# -lt 2 ]; then
    >&2 echo "Usage: bash dorado_align.sh </path/to/ubam> </path/to/bam> [<sample_name>]"
    >&2 echo "Exiting"
    exit 1
fi

#Read arguments
uBAM=$1
BAM=$2
SAMPLE=${3:-$(basename "$BAM" .bam)}
REF="$NP_REFERENCE"
ENTRY_STAGE="${NP_ENTRY_STAGE:-snakemake}"

DORADO="$NP_DORADO_ALIGNER"

# Align
${DORADO} aligner \
    ${REF} \
    ${uBAM} \
    --mm2-opts "-Y" \
    --threads 32 \
    > ${BAM}

# START NANO
NANODIR="${NP_OUT}/${SAMPLE}/data/raw/"

mkdir -p "$NANODIR"

cp "${BAM}" "${NANODIR}" -u

if [[ "$ENTRY_STAGE" == "align" ]]; then
    echo "Alignment-only mode; Snakemake submission skipped"
    exit 0
fi

clean_sbatch --export=ALL,CONFIG_FILE="${CONFIG_FILE:-}",NP_CONFIG_FILE="${NP_CONFIG_FILE:-}",NP_ANALYSIS_DIR="${NP_OUT}" "${NP_SNAKEMAKE_SCRIPT}" "${SAMPLE}"

#rmdir -p tmp
#rm -rf ${UNMAPPED_BAM_DIR}
