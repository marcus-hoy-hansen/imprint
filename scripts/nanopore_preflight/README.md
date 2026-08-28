# Nanopore Preflight Pipeline

A helper bundle to check uploaded Nanopore runs, copy them to storage, basecall with Dorado, and launch downstream Snakemake analysis.

## Layout

- `config.sh` — central settings for paths, Dorado binaries, reference, and Snakemake entrypoint.
- `lib.sh` — shared config loading and helper functions.
- `preflight.sh` — checks uploaded run structure, copies passing samples to `STORAGE`, and starts the downstream chain.
- `dorado_basecaller.sh` — GPU basecalling job; can stop after basecalling or continue to alignment.
- `dorado_align_and_submit.sh` — legacy alignment helper retained for manual use.
- `dorado_basecaller_cpu_test.sh` — CPU-only limited-read test wrapper.
- `nanopore_imprint_scheduler.sh` — optional Slurm watcher for periodic preflight runs.

## Entry Stages

`preflight.sh` and the repository wrapper `RUN.sh` support these entry modes:

- `preflight` — file checks only
- `basecall` — checks, copy to storage if needed, then submit Dorado basecalling
- `align` — legacy alias that stages an existing basecalled SUP BAM into the analysis tree
- `snakemake` — checks, derive the sample token, then submit `runSnakemake.sh` directly

Add `--continue` to continue downstream after `preflight`, `basecall`, or `align`.

## Usage

From the workflow repository root:

```bash
bash RUN.sh
bash RUN.sh --watch
bash RUN.sh --entry preflight
bash RUN.sh --entry preflight --continue
bash RUN.sh --entry basecall
bash RUN.sh --entry basecall --continue
bash RUN.sh --entry align
bash RUN.sh --entry align --continue
bash RUN.sh --entry snakemake
```

With no arguments, `bash RUN.sh` defaults to `--entry preflight --continue`.

### Rerunning Snakemake For Finished Samples

`--entry preflight --continue` is conservative: if a sample already has the final VarSeq marker
`analysis_v2/<sample>/varseq/<sample>_varseq_submitted.txt`, preflight treats the sample as already
finished and skips downstream resubmission.

If you want to rerun Snakemake for samples that were already completed before, use:

```bash
bash RUN.sh --entry snakemake
```

This bypasses the preflight `varseq_submitted.txt` skip and submits `runSnakemake.sh` directly for
the discovered samples.

If you want to rerun only one sample, run the launcher directly:

```bash
bash scripts/runSnakemake.sh 02346-26_hg38_ASv2
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

The wrapper can submit the watcher directly:

```bash
bash RUN.sh --watch
```

## External Files

The preflight chain expects these external resources to be available outside Git:

- Uploaded run folders with POD5 input and `output_hash_*.csv` files.
- Reference FASTA files, for example `hg38_noAlt.fasta`.
- Dorado basecalling models, including the configured high-accuracy/super-accuracy and methylation models.
- Dorado binaries for basecalling and alignment.
- Snakemake workflow resources used after alignment, including reference indexes, workflow data files, tool bundles, and VarSeq templates.

## Notes

- The current preflight checks require run directories and `output_hash_*.csv` files.
- Preflight no longer checks for BAM files and supports POD5-only input.
- Samples are moved from `uploaded` to `STORAGE` with `mv` when the storage target does not already exist.
- `--entry align` assumes the expected basecalled BAM already exists in `STORAGE/<experiment>/<sample>/`.
- `--entry align --continue` copies that SUP BAM into `<analysis-dir>/<sample>/data/raw/` and then submits Snakemake.
- `--entry snakemake` will also stage the SUP BAM into `<analysis-dir>/<sample>/data/raw/` when it is present in storage but not yet copied.
- `--entry preflight --continue` skips samples that already have the final VarSeq marker.
- Use `--entry snakemake` when you need to resubmit Snakemake for already-finished samples.
- Default analysis output root is `${NP_PROJECT_ROOT}/analysis_v2`.
- Override the analysis output root with `--analysis-dir /path` or `NP_ANALYSIS_DIR=/path`.
- Default reference is `${NP_PROJECT_ROOT}/STORAGE/resources/references/hg38_noAlt.fasta`.
- Default Snakemake launcher is `${NP_PROJECT_ROOT}/workflow_dev/scripts/runSnakemake.sh`.
