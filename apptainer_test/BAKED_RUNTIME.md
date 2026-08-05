# Baked Runtime

This scaffold models a production-style runtime image where:

- workflow code is inside the image
- tool environments are built before image build and copied inside the image
- references and model files stay outside
- runtime takes only sample, input-dir, output-dir, and site-config

## Build Steps

1. Build the tool environments on the host:

```bash
bash apptainer_test/build_baked_runtime_envs.sh
```

2. Build the lightweight runtime image:

```bash
bash apptainer_test/build_workflow_runtime.sh
```

This default build is the recommended mode for iteration. It expects the env folder to be bind-mounted at runtime:

```bash
/home/marcushh/nanopore_kga/workflow_dev/apptainer_test/runtime_envs
  -> /opt/workflow/runtime_envs
```

## Run

Dry-run:

```bash
bash apptainer_test/run_baked_workflow.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /faststorage/project/nanopore_kga/STORAGE/260602v3_Nanopore_Adaptiv/05483-13 \
  --output-dir /faststorage/project/nanopore_kga/analysis_v2 \
  --site-config /faststorage/project/nanopore_kga/workflow_dev/apptainer_test/runtime_site.conf \
  --dry-run
```

Real run:

```bash
bash apptainer_test/run_baked_workflow.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /faststorage/project/nanopore_kga/STORAGE/260602v3_Nanopore_Adaptiv/05483-13 \
  --output-dir /faststorage/project/nanopore_kga/analysis_v2 \
  --site-config /faststorage/project/nanopore_kga/workflow_dev/apptainer_test/runtime_site.conf
```

## Notes

- This runtime ignores Snakemake `conda:` directives at execution time.
- Instead, it exposes baked tools through wrappers in `/opt/workflow/runtime_bin`.
- References, models, and resource files are still configured from the outside.
- Dorado is still expected from the host path in the site config.
- The default runtime image is intentionally small and uses the physical external `runtime_envs/` folder through an Apptainer bind mount.
