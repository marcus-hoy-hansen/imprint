# Nanopore Preflight Pipeline

A helper bundle to check uploaded Nanopore runs, copy them to storage, basecall with Dorado, align, and launch downstream nanoimprint analysis.

## Layout

- `config.sh` — central settings for paths, Dorado binaries, reference, and Snakemake entrypoint.
- `lib.sh` — shared config loading and helper functions.
- `preflight.sh` — checks uploaded run structure, copies passing samples to `STORAGE`, and starts the downstream chain.
- `dorado_basecaller.sh` — GPU basecalling job; can stop after basecalling or continue to alignment.
- `dorado_align_and_submit.sh` — alignment job; copies aligned BAM into the analysis tree and can stop before or continue to Snakemake.
- `dorado_basecaller_cpu_test.sh` — CPU-only limited-read test wrapper.
- `nanopore_imprint_scheduler.sh` — optional Slurm watcher for periodic preflight runs.

## Entry Stages

`preflight.sh` and the repository wrapper `RUN.sh` support these entry modes:

- `preflight` — file checks only
- `basecall` — checks, copy to storage if needed, then submit Dorado basecalling
- `align` — checks, derive the expected basecalled BAM path, then submit alignment directly
- `snakemake` — checks, derive the sample token, then submit `runSnakemake.sh` directly

Add `--continue` to continue downstream after `preflight`, `basecall`, or `align`.

## Usage

From the workflow repository root:

```bash
bash RUN.sh
bash RUN.sh --entry preflight
bash RUN.sh --entry preflight --continue
bash RUN.sh --entry basecall
bash RUN.sh --entry basecall --continue
bash RUN.sh --entry align
bash RUN.sh --entry align --continue
bash RUN.sh --entry snakemake
```

Direct preflight script usage is also available:

```bash
sbatch --export=ALL,CONFIG_FILE=/faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/config.sh \
  /faststorage/project/nanopore_kga/workflow_dev/scripts/nanopore_preflight/preflight.sh \
  --entry preflight --continue
```

## Watcher

The watcher defaults to the full workflow:

```bash
bash RUN.sh --entry preflight --continue
```

Submit periodic watch mode with:

```bash
sbatch scripts/nanopore_preflight/nanopore_imprint_scheduler.sh --watch
```

## Notes

- The current preflight checks require run directories and `output_hash_*.csv` files.
- Preflight no longer checks for BAM files and supports POD5-only input.
- Samples are currently copied from `uploaded` to `STORAGE` with `cp -r`.
- `--entry align` assumes the expected basecalled BAM already exists in `STORAGE/<experiment>/<sample>/`.
- `--entry align --continue` runs alignment and then submits Snakemake.
- `--entry snakemake` assumes the workflow inputs already exist where `runSnakemake.sh` expects them.
- Default analysis output root is `${NP_PROJECT_ROOT}/analysis_v2`.
- Default reference is `${NP_PROJECT_ROOT}/STORAGE/resources/references/hg38_noAlt.fasta`.
- Default Snakemake launcher is `${NP_PROJECT_ROOT}/workflow_dev/scripts/runSnakemake.sh`.
