#!/bin/bash

#SBATCH --account nanopore_kga
#SBATCH -c 1
#SBATCH --mem 2g
#SBATCH --time 24:00:00
#SBATCH --output=logs/runSnakemake-%j.out
#SBATCH --error=logs/runSnakemake-%j.out
#SBATCH --chdir=/faststorage/project/nanopore_kga/workflow_dev

# Read input arguments
if [ $# -eq 0 ]; then
    >&2 echo "Usage: bash runSnakemake.sh <sampleID> [--analysis-dir /path] [snakemake args/targets...]"
    >&2 echo "SampleID consists of Langtved ID, the reference (T2T/hg38) and type of sequencing(AS/WGS)"
    >&2 echo "Reference is name of reference. Must be either hg38 or T2T"
    >&2 echo "If the sample is adaptive you need to provide the version of the adaptive sampling bed file used during sequencing (eg. ASv1)"
    >&2 echo "Example of running whole genome sample: bash runSnakemake.sh sample_hg38_WGS"
    >&2 echo "Example of running adaptive sample: bash runSnakemake.sh sample_hg38_ASv1"
    >&2 echo "Example with alternative output root: bash runSnakemake.sh sample_hg38_ASv2 --analysis-dir /faststorage/project/nanopore_kga/analysis_test"
    >&2 echo "Exiting"
    exit 1
fi

CONFIG_FILE="${NP_CONFIG_FILE:-config/config.yaml}"
ANALYSIS_DIR="${NP_ANALYSIS_DIR:-}"
SAMPLE=""
EXTRA_ARGS=()

while (( $# )); do
    case "$1" in
        --analysis-dir)
            shift
            [[ $# -gt 0 ]] || { echo "ERROR: --analysis-dir requires a value" >&2; exit 1; }
            ANALYSIS_DIR="$1"
            ;;
        -h|--help)
            >&2 echo "Usage: bash runSnakemake.sh <sampleID> [--analysis-dir /path] [snakemake args/targets...]"
            exit 0
            ;;
        *)
            if [[ -z "$SAMPLE" ]]; then
                SAMPLE="$1"
            else
                EXTRA_ARGS+=("$1")
            fi
            ;;
    esac
    shift
done

if [[ -z "$SAMPLE" ]]; then
    echo "ERROR: sampleID is required" >&2
    exit 1
fi


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
export PATH="/home/$USER/miniforge3/condabin:/home/$USER/miniforge3/bin:$PATH"
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
    --configfile "${CONFIG_FILE}" \
    --config \
    sample="${SAMPLE}" \
    refGenome="${REF}" \
    refFile="${REFFILE}" \
    ASversion="${VERSION}" \
    ${ANALYSIS_DIR:+analysisDir="${ANALYSIS_DIR}"} \
    --use-conda \
    --conda-frontend conda \
    --rerun-incomplete \
    --profile profiles/AS/ \
    "${EXTRA_ARGS[@]}"


##############
# WGS PIPELINE
elif [[ $TYPE == "WGS" ]]; then

    # Run snakemake
    snakemake \
    -s workflows/workflow_WGS/Snakefile_WGS \
    --configfile "${CONFIG_FILE}" \
    --config \
    sample="${SAMPLE}" \
    refGenome="${REF}" \
    refFile="${REFFILE}" \
    ${ANALYSIS_DIR:+analysisDir="${ANALYSIS_DIR}"} \
    --use-conda \
    --conda-frontend conda \
    --rerun-incomplete \
    --profile profiles/WGS/ \
    "${EXTRA_ARGS[@]}"
fi


# Close environment
conda deactivate
