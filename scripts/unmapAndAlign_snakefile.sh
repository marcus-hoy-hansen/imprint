#!/bin/bash

#SBATCH --account nanopore_kga
#SBATCH -c 1
#SBATCH --mem 2g
#SBATCH --time 12:00:00


# Read input arguments
if [ $# -eq 0 ]; then
    >&2 echo "Usage: bash unmapAndAlign_snakemake.sh </path/to/mapped/bams/dir/> <reference.fasta>"
    >&2 echo "Exiting"
    exit 1
fi


# Input arguments
INPUT_DIR=$1
OUTPUT_DIR=$2
REF=$3

# Inititalize
WD="${PWD}"
SNAKEFILE="${WD}/scripts/unmapAndAlign_snakefile"
DORADO="/faststorage/project/nanopore_kga/development/software/dorado-0.8.1-linux-x64/bin/dorado"
PICARD="/faststorage/project/nanopore_kga/development/software/picard.jar"

# Activate environment
source /home/$USER/miniforge3/etc/profile.d/conda.sh
conda activate snakemake_env

snakemake \
-s ${SNAKEFILE} \
--config \
inputDir="${INPUT_DIR}" \
outputDir="${OUTPUT_DIR}" \
refFile="${REF}" \
dorado="${DORADO}" \
picard="${PICARD}" \
--rerun-incomplete \
--use-conda \
--executor slurm \
--jobs 10 \
--default-resources slurm_account=nanopore_kga

# Close environment
conda deactivate


# Clean up
mv ${OUTPUT_DIR}mapped/* ${OUTPUT_DIR} && rmdir ${OUTPUT_DIR}mapped/
rm -rf ${OUTPUT_DIR}unMapped