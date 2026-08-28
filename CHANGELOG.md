# Workflow changelog (IMPRINTING PIPELINE)

**ALL additions and modifications should preferably be listed here to improve debugging and overall overview.**
(CHANGELOG.md, PDF generated using pandoc CHANGELOG.md -o CHANGELOG.pdf)
/MHA

---

Updated Aug 28, 2026 /Codex

• Released workflow version `1.1.0`.

• Added a Snakemake-native preflight v2 entry point with `RUN_v2.sh`, `config/preflight_v2.yaml`, `profiles/preflight/config.yaml`, and `workflows/preflight/Snakefile_preflight`. By default it stages into `analysis_v2/` unless `--analysis-dir` is supplied.

• Routed wrapper and preflight Slurm logs into `logs/`.

• Kept `--analysis-dir` available on the front wrappers and propagated it to downstream Snakemake submissions.

• Added nested Slurm submission cleanup for inherited memory and GPU environment variables.

• Updated optional T2T output naming so mapped BAMs and T2T variant files drop `_hg38_` from the output filename.

• Removed NanoPlot ownership of the whole `QC/` directory. NanoPlot now owns only its HTML report, preventing parallel QC outputs such as `QC/validation_metrics/` from being removed during reruns.

• Updated Clair3 execution to use the configured Apptainer image and write final Clair3 outputs directly.

• Added VarSeq TEST autostart routing through `varseqProjectRoot` and `varseqProjectLabel`, currently targeting `TEST_Varseq_projects_2026` with the `In-House-ONT_LDnr_HG38_v3.1` project label.

• Replaced the accidental tracked `scripts/unlock.sh` terminal transcript with a minimal Snakemake unlock wrapper.

---

Updated Aug 5, 2026 /Codex

• Released workflow version `1.0.0`.

• Moved standard alignment responsibility fully into Snakemake. The normal workflow now starts from raw/basecalled SUP BAMs staged under `analysis_v2/<sample>/data/raw/`.

• Simplified raw BAM preparation by replacing the old `BAMlist` + `mergeBAMs` path with `prepareRawBAM`:

  - if `0` BAMs are present in `data/raw/`: fail clearly
  - if `1` BAM is present: use it directly
  - if multiple BAMs are present: merge them with `samtools`

• Updated the standard hg38 workflow path to:

  `prepareRawBAM -> alignMergedBAM -> sortMergedBAM -> indexMergedBAM`

• Extended the optional T2T branch in both AS and WGS workflows to support:

  `t2tAlignBAM`, `t2tSortBAM`, `t2tIndexBAM`, `t2tClair3`

• Kept the T2T branch outside `rule all` so it remains opt-in and does not alter the default pipeline scope.

• Collapsed the previous extra T2T Clair3 cleanup layer. `t2tClair3` now writes the final optional outputs directly:

  - `data/{sample}.t2t.sorted.bam`
  - `data/{sample}.t2t.sorted.bam.bai`
  - `data/{sample}.t2t.haplotagged.bam`
  - `data/{sample}.t2t.haplotagged.bam.bai`
  - `variants/{sample}_t2t_clair3.vcf.gz`
  - `variants/{sample}_t2t_clair3.vcf.gz.tbi`

• Updated Clair3 configuration to use the SUP model:

  `r1041_e82_400bps_sup_v520`

• Updated the configured Dorado binary path to:

  `/faststorage/project/nanopore_kga/tools/dorado-2.1.1-linux-x64/bin/dorado`

• Added and documented an Apptainer workflow test area under `apptainer_test/`, including a baked-runtime prototype, runtime wrapper scripts, and usage notes for containerized pipeline testing.

---

Updated Jul 27, 2026 /Codex

• Released workflow version `0.2.0`.

• Updated the NanoPlot environment to `nanoplot==1.47.1` on Python `3.11`.

• Updated the NanoPlot rule to use:

  `--huge --plots dot -f png`

• Added `scripts/t2t_qc_align_sort.sh` as a standalone QC helper for Dorado SUP BAM to T2T align/sort/index.

• Added an optional T2T Snakemake branch, available in both AS and WGS workflows, with rules:

  `t2tAlignBAM`, `t2tSortBAM`, `t2tIndexBAM`

• Kept the optional T2T branch out of `rule all` so the standard pipeline behavior is unchanged.

• Added config keys `t2tRefFile` and `doradoAligner` to support the optional T2T branch.

• Added profile resources for the optional T2T branch in both `profiles/AS/config.yaml` and `profiles/WGS/config.yaml`.

• Added `scripts/quality_validation.sh` integration to the workflow QC path and documented the validation outputs in `README.md`.

• Updated `scripts/runSnakemake.sh` so Snakemake can find `conda` while creating rule-specific environments.

---

Updated Jun 23, 2026 /Codex

• Added Snakemake rule `qualityValidation` to both AS and WGS workflows using `scripts/quality_validation.sh`.

• Added `QC/validation_metrics/` outputs to `rule all` for both `workflows/workflow_AS/Snakefile_AS` and `workflows/workflow_WGS/Snakefile_WGS`.

• Added profile resources for `qualityValidation` in `profiles/AS/config.yaml` and `profiles/WGS/config.yaml`:

  `threads: 1`, `mem_mb: 4096`, `runtime: 300`

• Updated `modules/common/rules/common_rules.smk` and `modules/common/rules/common_rules.smk_dev` so `clair3CleanUp` copies final outputs instead of moving them. This keeps Clair3 intermediates available for reruns and prevents unnecessary upstream Clair3 recomputation when stale incomplete metadata is present.

• Removed Snakemake `protected()` wrappers from the common rules files to avoid write-protection collisions during reruns.

---

Updated Jun 12, 2026 /MHA

• Added `scripts/target_region_mean_coverage.sh` to calculate mean coverage per target BED region from an aligned BAM, write Q1/median/Q3/mean summary values at the top of the output, and save the result as a TSV next to the BAM.

• Updated `scripts/target_region_mean_coverage.sh` to test both the standard adaptive sampling hg38 v2 BED and the RB GRCh38 v3 BED, then keep the panel with the higher mean region coverage in the saved output.

---

Updated May 8, 2026 /MHA

• Added QDNAseq CNV calling to the adaptive sampling workflow.

• Added shared-resource based hg38 QDNAseq bin annotations in `STORAGE/resources/data/qdnaseq/` and updated the workflow to use configured bin RDS files instead of package-local hg38 annotations.

• Added qDNAseq caching/resume behavior through persistent `readCounts.rds` and `copyNumbers.rds` files, with Snakemake now always passing `--continue-aborted`.

• Updated qDNAseq output naming to include `QDNAseq` in exported non-plot filenames.

• Added qDNAseq profile resources in `profiles/AS/config.yaml`.

• Switched the configured qDNAseq bin size to 500 kb using shared resource `hg38_500kb_bins.rds`.

• Added `scripts/chrom_variantallelefrequencies_panel.py` to the adaptive sampling workflow as a post-Clair3 plotting step using:

  `--vcf analysis_v2/<sample>/variants/<sample>_clair3.vcf.gz --all-chroms --depth 20`

• Added `chromVariantAlleleFrequenciesPanel` resource settings in `profiles/AS/config.yaml`.

---


Updated Apr 16, 2026 /MHA

• Added top-level `RUN.sh` wrapper for the nanopore preflight/Snakemake submission flow.

• `bash RUN.sh` now defaults to `--entry snakemake`.

• Added local `bash RUN.sh --help` output so help can be read without submitting a Slurm job.

• Added `--continue` to the preflight entry system:

  - `--entry preflight --continue`: preflight -> copy -> basecall -> align -> Snakemake.
  - `--entry basecall --continue`: basecall -> align -> Snakemake.
  - `--entry align --continue`: align -> Snakemake.

• Added `clean_sbatch` helper to strip inherited `SLURM_MEM_PER_CPU`, `SLURM_MEM_PER_GPU`, and `SLURM_MEM_PER_NODE` before nested Slurm submissions. This fixes failed nested Snakemake submissions from preflight jobs.

• Updated watcher defaults so `nanopore_imprint_scheduler.sh --watch` submits the full workflow through:

  `bash RUN.sh --entry preflight --continue`

• Added Git ignore rules for Slurm output files, Dorado temporary model directories, watcher state, and other generated files.

• Tested `bash RUN.sh --entry align` on a downsampled AS sample. Alignment completed successfully, copied the aligned BAM to `analysis_v2/.../data/raw/`, and `samtools quickcheck` passed.

---


Updated Apr 13, 2026 /MHA

• Added config key `referenceDir` to `config/config.yaml` so reference files can live outside the workflow folder.

• Added config key `dataDir` to `config/config.yaml` so workflow data files can live outside the workflow folder.

• Added config key `softwareDir` to `config/config.yaml` so workflow software resources can live outside the workflow folder.

• Updated Snakemake files in `modules/common/rules` and `workflows/workflow_(AS/WGS)` to use `referenceDir` for reference paths instead of hardcoded `references/`.

• Updated Snakemake files in `modules/common/rules` and `workflows/workflow_AS` to use `dataDir` for workflow data paths instead of hardcoded `data/`.

• Default config paths now point to `../STORAGE/resources/(references/data/software)`.

• Automated-upload script 

---


Updated Dec 4, 2025 /MHA

• Snakemake workflow/modules/common/rules/common_rules.smk and workflow/workflows/workflow_(WGS/AS)/Snakefile_(WGS/AS) updated to wait in hifiCNV renaming 


---


Updated Nov 21, 2025 /MHA

• Changelog file created (CHANGELOG.md, PDF generated using pandoc CHANGELOG.md -o CHANGELOG.pdf). ALL additions and modifications should
preferably be listed here to improve debugging and overall overview.
/MHA

- Snakemake logs were previously written to the directory from which the
  script was executed. They are now saved in the folder `workflow/logs`.
  Change added to `workflow/runSnakemake.sh`.

- Added `#SBATCH --error=logs/runSnakemake-%j.out` to
  `workflow/runSnakemake.sh` (so the error log is more informative).

- Added `#SBATCH --chdir=/faststorage/project/nanopore_kga/workflow` to
  `workflow/runSnakemake.sh` to ensure this is always the starting
  directory.

- Added the line `--conda-frontend conda \` to
  `workflow/runSnakemake.sh`, since otherwise a new conda env for
  bcftools could not be created (conda must be used and not the
  \[default\] mamba). bcftools is used for renaming the VCF header.

- Inserted Magnus' script for VCF header renaming under the rule
  `vcfrename` in `modules/common/rules/common_rules.smk`. This rule
  already existed, as renaming had been partially implemented directly
  in Snakemake. The advantage of the new script is that it is recursive,
  i.e. it collects all VCF files and will continue to do so for future
  additions to the pipeline. The script works as intended, but the
  complexity is high relative to the task and should be considered a
  point of attention for future maintenance.

• Script `rename_sample_name_VCF_recursive.sh` placed under
`workflow/scripts` (permissions `rwxr-xr--`).

• `use rule vcfrename from common` added to
`workflows/workflow_AS/Snakefile_AS`. It was already added to
`workflows/workflow_WGS/Snakefile_WGS` due to the ongoing VCF-renaming
test.

- Code line\
  `expand("../analysis/{sample}/renamed_vcfs/variants_{sample}_clair3.vcf.gz", sample=config["sample"])`\
  added to `workflows/workflow_AS/Snakefile_AS`.

• Focus point: VCF header renaming is now implemented in the pipeline,
but has not been run retrospectively. That is, it must be run manually
(e.g. `scripts/runSnakemake.sh 1561-24_hg38_ASv2`), after which the
output is simply updated for already completed analyses.

• Focus point: The current Clair3 model is `"r1041_e82_400bps_hac_v430"`
in `config/config.yaml`. This is OK for now but can be changed to a
newer version later.

• Focus point: The Clair3 model currently runs HAC for both AS and WGS.
