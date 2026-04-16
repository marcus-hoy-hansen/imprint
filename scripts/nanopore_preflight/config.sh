#!/usr/bin/env bash

# Central configuration for the nanopore preflight pipeline. Override any of
# these via environment variables before running the scripts.

: "${NP_PROJECT_ROOT:=/faststorage/project/nanopore_kga}"
: "${NP_BASE:=${NP_PROJECT_ROOT}/uploaded}"
: "${NP_OUT:=${NP_PROJECT_ROOT}/analysis_v2}"
: "${NP_SCRIPT_ROOT:=${NP_PROJECT_ROOT}/workflow_dev/scripts/nanopore_preflight}"

: "${NP_STORAGE_BASE:=${NP_PROJECT_ROOT}/STORAGE}"
: "${NP_REFERENCE:=${NP_PROJECT_ROOT}/STORAGE/resources/references/hg38_noAlt.fasta}"
: "${NP_SNAKEMAKE_SCRIPT:=${NP_PROJECT_ROOT}/workflow_dev/scripts/runSnakemake.sh}"

: "${NP_BASECALLER_SBATCH:=${NP_SCRIPT_ROOT}/dorado_basecaller.sh}"

: "${NP_DORADO_BASECALLER:=/home/marcushh/dorado-1.1.1-linux-x64/bin/dorado}"
: "${NP_DORADO_ALIGNER:=/home/marcushh/dorado-1.2.0-linux-x64/bin/dorado}"
: "${NP_DORADO_MODEL:=sup,5mCG_5hmCG,6mA}" # default dorado model string
: "${NP_DORADO_TEST_MODEL:=fast}"          # lighter model for CPU/test runs
: "${NP_DORADO_DEVICE:=cuda:all}"          # set to "cpu" for quick tests (submit with CPU partition)
: "${NP_DORADO_TEST_LIMIT:=1000}"          # max reads to basecall when NP_DORADO_DEVICE=cpu or NP_DORADO_TEST_MODE=1
: "${NP_DORADO_TEST_MODE:=0}"              # set to 1 to force CPU device and cap max reads for fast test runs

# Conda settings used to reach samtools (and other CLI tools if needed).
: "${NP_CONDA_PROFILE:=/home/$USER/miniforge3/etc/profile.d/conda.sh}"
: "${NP_CONDA_ENV:=bwa}"

# Scheduler defaults for the optional watch script.
: "${NP_WATCH_INTERVAL:=12hours}"
: "${NP_WEEKLY_INTERVAL_DAYS:=7}"
: "${NP_WATCH_STATE_DIR:=.watch_state}"
