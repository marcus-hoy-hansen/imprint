# Full Pipeline Apptainer Pilot

This is a broader pilot than `run_samtools_test.sh`.

Goal:

- take a real SUP BAM
- create a `1000`-read subset
- stage it into an isolated analysis directory
- run the actual AS Snakemake workflow from an Apptainer Snakemake runner

This does **not** containerize every rule. Instead it tests a practical intermediate model:

- Apptainer container runs Snakemake itself
- the real workflow is used
- Snakemake still creates rule-specific conda environments from the repo `envs/`
- host paths remain exactly as they are now

## Files

- `Apptainer.snakemake_runner.def`
- `build_snakemake_runner.sh`
- `fullpipe_test.conf`
- `prepare_fullpipe_subset.sh`
- `run_fullpipe_test.sh`

## Default Example

The default example uses:

- sample token: `05483-13-appt1000_hg38_ASv2`
- source SUP BAM:

```bash
/faststorage/project/nanopore_kga/STORAGE/260602v3_Nanopore_Adaptiv/05483-13/05483-13sup_AS.bam
```

- isolated analysis root:

```bash
/faststorage/project/nanopore_kga/workflow_dev/apptainer_test/fullpipe_analysis
```

## Build

Build the small `samtools` helper image:

```bash
bash apptainer_test/build_samtools_container.sh
```

Build the Snakemake runner image:

```bash
bash apptainer_test/build_snakemake_runner.sh
```

## Run

```bash
bash apptainer_test/run_fullpipe_test.sh
```

## What It Does

1. Builds a `1000`-read subset BAM from the configured SUP BAM.
2. Places that subset in:

```bash
apptainer_test/fullpipe_analysis/<sample>/data/raw/
```

3. Runs the actual AS workflow:

```bash
workflows/workflow_AS/Snakefile_AS
```

with:

- `sample=<TEST_SAMPLE>`
- `refGenome=hg38`
- `refFile=hg38_noAlt.fasta`
- `ASversion=v2`
- `analysisDir=<ANALYSIS_DIR>`

## Caveats

- A `1000`-read test may still fail in some downstream tools because it is biologically tiny.
- That is acceptable for this pilot. The main purpose is to test:
  - Apptainer runner behavior
  - path visibility
  - Snakemake + conda inside the runner container
  - workflow wiring from raw SUP BAM onward
