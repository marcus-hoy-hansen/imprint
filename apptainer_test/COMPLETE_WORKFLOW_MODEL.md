# Complete Workflow Model

This file describes a practical full containerized workflow model for this repository.

It is a target architecture, not a claim that every current rule is already fully converted.

## Purpose

The production container should:

- contain the workflow code
- contain the resolved software stack
- accept only a small runtime interface
- keep site-specific heavy resources outside the image

This avoids:

- cluster-side conda solving
- drift in package resolution
- mixed host/tool environment behavior
- redundant path assumptions spread across preflight and Snakemake

## Runtime Interface

Recommended runtime interface:

```bash
apptainer exec workflow_runtime.sif \
  bash /opt/workflow/container_entrypoint.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /data/05483-13 \
  --output-dir /data/analysis_v2 \
  --site-config /data/site_config.conf
```

Required runtime inputs:

- `--sample`
  - full sample token, e.g. `05483-13_hg38_ASv2`
- `--input-dir`
  - directory containing one or more SUP BAM files for that sample
- `--output-dir`
  - root corresponding to the current `analysis_v2`
- `--site-config`
  - site/resource configuration file

## What The Image Should Contain

- Snakemake
- workflow code
- helper scripts
- shell runtime
- resolved tool environments
- a small container entrypoint wrapper

This should include the downstream workflow software stack, for example:

- `samtools`
- `NanoPlot`
- `Clair3`
- `whatshap`
- `sniffles2`
- `cuteSV`
- `modkit`
- `hifiCNV`
- `QDNAseq`
- `straglr`
- support utilities used by helper scripts

The `envs/*.yaml` files remain in Git as build specifications, but the production runtime should not solve them dynamically.

## What Should Stay Outside The Image

- references and indexes
- Clair3 models
- Dorado models
- optional Dorado binaries
- adaptive BED/data resources that are maintained separately
- sample input BAMs
- output directories
- institution-specific submission integrations such as VarSeq

## Expected Runtime Flow

1. Read site config.
2. Validate the sample token and derive `AS` or `WGS`.
3. Create:

```bash
<output-dir>/<sample>/data/raw/
```

4. Stage or symlink SUP BAMs from `--input-dir` into `data/raw/`.
5. Launch the corresponding Snakemake workflow:
   - `workflows/workflow_AS/Snakefile_AS`
   - or `workflows/workflow_WGS/Snakefile_WGS`
6. Write all results to the provided output directory.

## Clean Data Model

Inside the output tree:

- `data/raw/`
  - raw basecalled SUP BAM inputs
- `data/<sample>.bam`
  - canonical aligned BAM
- `data/<sample>.haplotagged.bam`
  - downstream haplotagged BAM

Optional T2T branch:

- `data/<sample>.t2t.sorted.bam`

This keeps raw, aligned, and derived BAMs separate and avoids the old duplication problem.

## Configuration Model

The image should not hardcode site paths. Those belong in a site config file.

Minimal config categories:

- reference directory
- data/resource directory
- software/model directory
- reference file names
- Clair3 model name
- optional Dorado binary path
- optional VarSeq integration settings

## Suggested Build Strategy

1. Keep `envs/*.yaml` as source-of-truth build specs.
2. Build resolved environments into the image.
3. Copy the repo workflow code into `/opt/workflow/`.
4. Provide one stable entrypoint:

```bash
/opt/workflow/container_entrypoint.sh
```

5. Mount host data/resources at runtime.

## Migration Strategy

Recommended order:

1. Containerized Snakemake runner plus host-mounted resources
2. Bake downstream tool stack into the image
3. Stop using runtime conda solves
4. Optionally split Dorado/basecalling into a second GPU-focused image

## Current Gap

The current repo now has a useful model and pilot scaffolding, but not yet a final fully baked runtime image containing the complete resolved downstream stack.

The files added here are meant to make that target concrete enough to implement incrementally.
