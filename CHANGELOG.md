# Workflow changelog (IMPRINTING PIPELINE)

**ALL additions and modifications should preferably be listed here to improve debugging and overall overview.**
(CHANGELOG.md, PDF generated using pandoc CHANGELOG.md -o CHANGELOG.pdf)
/MHA

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
