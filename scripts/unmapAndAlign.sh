#!/bin/bash

#SBATCH --account nanopore_kga
#SBATCH -c 32
#SBATCH --mem 32g
#SBATCH --time 12:00:00

#Check if sample name was provided in command
if [ $# -eq 0 ]; then
    >&2 echo "Usage: bash unmapManyBAMs.sh </path/to/mapped/bams/dir/> <reference.fasta>"
    >&2 echo "REMEMBER: Path to dir with mapped bams has to end with '/'"
    >&2 echo "This will work: /path/to/mapped/bams/dir/"
    >&2 echo "This won't work: /path/to/mapped/bams/dir"
    >&2 echo "Exiting"
    exit 1
fi

#Read arguments
MAPPED_BAM_DIR=$1
REF=$2

#Dorado location
DORADO="/faststorage/project/nanopore_kga/development/software/dorado-0.8.1-linux-x64/bin/dorado"

# Make directory for unmapped bam file
UNMAPPED_BAM_DIR="unMapped"
mkdir -p ${UNMAPPED_BAM_DIR}



# Activate environment
source /home/$USER/miniforge3/etc/profile.d/conda.sh
conda activate picard_env

# Unmap all bam files in directory
for bam in ${MAPPED_BAM_DIR}*.bam
do
    # Find file prefix
    bam_base=$(basename -- "$bam")
    prefix="${bam_base%.*}"

    # Name of unmapped file
    UNMAPPED_BAM=${UNMAPPED_BAM_DIR}/"$prefix"_unMapped.bam

    # Unmap
    java -Xmx100G -jar /faststorage/project/nanopore_kga/development/software/picard.jar RevertSam \
    I="$bam" \
    O=${UNMAPPED_BAM} \
    VALIDATION_STRINGENCY=SILENT \
    TMP_DIR=./tmp

    # Align
    ${DORADO} aligner \
    ${REF} \
    ${UNMAPPED_BAM} \
    --threads 32 \
    > ${prefix}.bam
done

# Close environment
conda deactivate

# Clean up
rmdir -p tmp
rm -rf ${UNMAPPED_BAM_DIR}