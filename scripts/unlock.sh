#!/bin/bash

#SBATCH --account nanopore_kga
#SBATCH -c 1
#SBATCH --mem 2g
#SBATCH --time 48:00:00

# Read input arguments (go to workflow folder and run: bash scripts/unlock.sh <sampleID>)
if [ $# -eq 0 ]; then
    >&2 echo "Usage: bash scripts/unlock.sh <sampleID>"
    >&2 echo "SampleID consists of Langtved ID, the reference (T2T/hg38) and type of sequencing(AS/WGS)"
    >&2 echo "Reference is name of reference. Must be either hg38 or T2T"
    >&2 echo "If the sample is adaptive you need to provide the version of the adaptive sampling bed file used during sequencing (eg. ASv1)"
    >&2 echo "Example of running whole genome sample: bash runSnakemake.sh 1234-23_hg38_WGS"
    >&2 echo "Example of running adaptive sample: bash runSnakemake.sh 1234-23_hg38_ASv1"
    >&2 echo "Exiting"
    exit 1
fi

# Input arguments
SAMPLE=$1


# Split input to get sampleID, reference and type (AS or WGS)
IFS="_"
read -ra test <<< "$SAMPLE"
SAMPLE_ID="${test[0]}"
REF="${test[1]}"
TYPE="${test[2]}"



# Define reference file 
if [ ${REF} == "hg38" ]; then
    REFFILE="hg38_noAlt.fasta"
elif [ ${REF} == "T2T" ]; then
    REFFILE="GCF_009914755.1_T2T-CHM13v2.0_genomic.fna"
else
    echo "${REF} is not a valid reference genome. Reference must either T2T or hg38"; exit 1;
fi



# Activate environment
source /home/$USER/miniforge3/etc/profile.d/conda.sh
conda activate snakemake_env

#############
# AS PIPELINE
if [[ $TYPE =~ "AS" ]]; then

    # Find AS version
    IFS="AS"
    read -ra split <<< "$TYPE"
    VERSION="${split[-1]}"
    echo ${VERSION}

    # Run snakemake
    snakemake \
    -s workflows/workflow_AS/Snakefile_AS \
    --config \
    sample="${SAMPLE}" \
    refGenome="${REF}" \
    refFile="${REFFILE}" \
    ASversion="${VERSION}" \
    --use-conda \
    --rerun-incomplete \
    --profile profiles/AS/ \
    --unlock


##############
# WGS PIPELINE
elif [[ $TYPE == "WGS" ]]; then

    # Run snakemake
    snakemake \
    -s workflows/workflow_WGS/Snakefile_WGS \
    --config \
    sample="${SAMPLE}" \
    refGenome="${REF}" \
    refFile="${REFFILE}" \
    --use-conda \
    --rerun-incomplete \
    --profile profiles/WGS/ \
    --unlock
fi


# Close environment
conda deactivate