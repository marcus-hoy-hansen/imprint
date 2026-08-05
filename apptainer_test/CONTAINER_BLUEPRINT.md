# Container Blueprint

This is a proposed production layout for a containerized version of the workflow.

Goal:

- bake the workflow code and tool environments into the image
- keep references, models, sample data, and outputs outside the image
- run the workflow with a small site config plus simple input/output arguments

## What Goes Inside The Image

- Snakemake
- workflow code under `workflow_dev/`
- helper scripts under `scripts/`
- fixed runtime utilities
- resolved tool environments for:
  - `samtools`
  - `NanoPlot`
  - `Clair3`
  - `sniffles2`
  - `cuteSV`
  - `modkit`
  - `hifiCNV`
  - `straglr`
  - other downstream analysis tools

The `envs/*.yaml` files should stay in Git as build specifications, but the runtime image should not solve them at execution time.

## What Stays Outside The Image

- reference FASTA files and indexes
- Clair3 model files
- Dorado models and optional Dorado binaries
- adaptive BED/data resources if they are maintained independently
- sample SUP BAM input folder
- output analysis folder
- optional site-specific VarSeq configuration

## Runtime Interface

Recommended user-facing interface:

```bash
apptainer exec workflow_runtime.sif \
  bash /opt/workflow/run_containerized_workflow.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /data/sup_bams/05483-13 \
  --output-dir /data/analysis_v2 \
  --site-config /data/site_config.yaml
```

## Runtime Behavior

1. Read the site config.
2. Stage or link SUP BAMs from `--input-dir` into `<output-dir>/<sample>/data/raw/`.
3. Run Snakemake on the real workflow.
4. Write all outputs under `--output-dir`.

## Why This Split

- The image becomes the versioned release artifact.
- Site-specific paths remain configurable.
- Large references and models do not need to be rebuilt into each image.
- Runtime becomes reproducible without solving conda envs on the cluster.

## Notes On Dorado

Two reasonable options:

1. Keep Dorado outside the image at first.
   - simplest operationally
   - especially if GPU/site runtime details vary

2. Build a separate GPU-oriented Dorado image later.
   - better long-term standardization
   - more operational complexity

For now, the cleanest first milestone is to containerize the downstream Snakemake workflow from SUP BAM onward.
