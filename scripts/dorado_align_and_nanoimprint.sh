#!/bin/bash

#SBATCH --job-name=dorado-align
#SBATCH --account nanopore_kga
#SBATCH -c 32
#SBATCH --mem 32g
#SBATCH --time 12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err


set -euo pipefail

# shellcheck source=lib.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NP_SCRIPT_ROOT:=${SCRIPT_DIR}}"
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

DORADO="$NP_DORADO_ALIGNER"

# Align (skip if output already exists)
if [[ -s "$BAM" ]]; then
    echo "Aligned BAM already present; skipping alignment: $BAM"
else
    ${DORADO} aligner \
        ${REF} \
        ${uBAM} \
        --mm2-opts "-Y" \
        --threads 32 \
        > ${BAM}
fi

# START NANO
NANODIR="/faststorage/project/nanopore_kga/analysis/${SAMPLE}/data/raw/"

mkdir -p "$NANODIR"

cp "${BAM}" "${NANODIR}" -u

sbatch "${NP_SNAKEMAKE_SCRIPT}" "${SAMPLE}"

#rmdir -p tmp
#rm -rf ${UNMAPPED_BAM_DIR}
