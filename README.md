# Imprinting Nanopore Workflow

Snakemake workflow and preflight helpers for uploaded Nanopore runs. The current wrapper is `RUN.sh`, which submits the preflight pipeline with the repository-local configuration.

## Main Commands

```bash
bash RUN.sh
bash RUN.sh --watch
```

Defaults to `--entry preflight --continue`.

```bash
bash RUN.sh --entry preflight
bash RUN.sh --entry preflight --continue
bash RUN.sh --entry basecall
bash RUN.sh --entry basecall --continue
bash RUN.sh --entry align
bash RUN.sh --entry align --continue
bash RUN.sh --entry snakemake
```

Entry behavior:

- `preflight` checks uploaded run folders and `output_hash_*.csv` files.
- `basecall` starts from Dorado basecalling.
- `align` starts from the expected basecalled BAM and writes the aligned BAM.
- `snakemake` submits `scripts/runSnakemake.sh` for discovered samples.
- `--continue` continues downstream after the selected entry stage.

Typical full automated run:

```bash
bash RUN.sh --entry preflight --continue
```

## Watcher

The Slurm watcher lives at:

```bash
scripts/nanopore_preflight/nanopore_imprint_scheduler.sh
```

Default watch behavior submits:

```bash
bash RUN.sh --entry preflight --continue
```

and then resubmits the watcher after `NP_WATCH_INTERVAL`.

```bash
sbatch scripts/nanopore_preflight/nanopore_imprint_scheduler.sh --watch
```

The same watch mode can be submitted through the wrapper:

```bash
bash RUN.sh --watch
```

## Direct Snakemake

Direct sample submission is still available:

```bash
bash scripts/runSnakemake.sh sample_hg38_ASv2
sbatch scripts/runSnakemake.sh sample_hg38_ASv2
```

## External Files

The workflow expects these external resources to be available outside Git:

- Reference FASTA files, for example `hg38_noAlt.fasta` and `GCF_009914755.1_T2T-CHM13v2.0_genomic.fna`.
- Reference indexes required by the tools that consume the FASTA files.
- Workflow data resources such as chromosome sizes, DMR normal BED files, and adaptive sampling BED files.
- Dorado basecalling models, including the configured high-accuracy/super-accuracy and methylation models.
- Dorado binaries for basecalling and alignment.
- Clair3 model files, for example the configured ONT HAC model.
- Tool bundles used by the workflow, including Modkit and other non-conda executables.
- VarSeq project templates and remote submission scripts used for VarSeq import/submission.

## Notes

- Generated Slurm logs, Dorado temporary model folders, `.snakemake/`, and local watcher state are ignored by Git.
- `RUN.sh` and the preflight chain strip inherited Slurm memory variables before nested `sbatch` calls to avoid conflicting `SLURM_MEM_PER_*` settings.
