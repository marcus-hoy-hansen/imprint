# Apptainer Notes

This folder contains Apptainer experiments for the nanopore workflow.

The current useful path is the baked workflow runtime:

- workflow code is baked into `workflow_runtime.sif`
- tool environments are baked from `runtime_envs.tar`
- references, models, input BAMs, and output folders remain outside the image
- Snakemake runs locally inside the container

This is not yet a production release path. It is a working prototype and test harness.

## Current Status

As of August 5, 2026, the following parts are working:

- building `apptainer_test/containers/workflow_runtime.sif`
- launching the real AS workflow from inside the container
- binding host paths such as `/faststorage` and `/home`
- using a writable host-mounted `.snakemake` state directory
- subset smoke testing from the host wrapper via `--subset-reads`

Known limitations:

- the workflow runs with `--executor local` inside the container
- the Slurm executor plugin is not used inside the container
- some heavy steps, especially `dorado aligner`, still require real compute resources
- stale intermediate files can confuse reruns if a previous test was killed

## Main Files

- `Apptainer.workflow_runtime.def`
  - definition for the main workflow runtime image
- `build_baked_runtime_envs.sh`
  - builds the host-side env prefixes under `runtime_envs/`
- `build_workflow_runtime.sh`
  - builds `containers/workflow_runtime.sif`
- `run_baked_workflow.sh`
  - host-side launcher for the baked runtime
- `container_entrypoint_baked.sh`
  - entrypoint executed inside the container
- `runtime_site.conf`
  - site-specific runtime paths for references, models, and resources
- `runtime_envs/`
  - host-side env prefixes used to create `runtime_envs.tar`
- `runtime_envs.tar`
  - tarball baked into the image and extracted into `/opt/workflow/runtime_envs`

Older files such as the samtools-only test and the earlier model docs are still here for reference, but the baked runtime path is the main one to use.

## Build Flow

Commands are run from:

```bash
/faststorage/project/nanopore_kga/workflow_dev
```

### 1. Build env prefixes

```bash
bash apptainer_test/build_baked_runtime_envs.sh
```

This builds multiple env prefixes under:

```bash
apptainer_test/runtime_envs/
```

### 2. Create or refresh the tarball

If needed:

```bash
tar -cf apptainer_test/runtime_envs.tar -C apptainer_test runtime_envs
```

### 3. Build the runtime image

```bash
bash apptainer_test/build_workflow_runtime.sh baked-envs
```

This creates:

```bash
apptainer_test/containers/workflow_runtime.sif
```

## Run Flow

### Recommended: run on a compute node

Do not run the full workflow test from a login node. Steps like `dorado aligner` can be killed even with tiny subset BAMs because the aligner still needs to load the reference index.

Example allocation:

```bash
srun --account nanopore_kga --mem 32g -c 8 --time=04:00:00 --pty bash
```

Then run:

```bash
bash apptainer_test/run_baked_workflow.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /faststorage/project/nanopore_kga/STORAGE/260602v3_Nanopore_Adaptiv/05483-13 \
  --output-dir /faststorage/project/nanopore_kga/analysis_v2/apptainer \
  --site-config /faststorage/project/nanopore_kga/workflow_dev/apptainer_test/runtime_site.conf \
  --subset-reads 1000 \
  --cores 8
```

### Full-data run

```bash
bash apptainer_test/run_baked_workflow.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /faststorage/project/nanopore_kga/STORAGE/260602v3_Nanopore_Adaptiv/05483-13 \
  --output-dir /faststorage/project/nanopore_kga/analysis_v2/apptainer \
  --site-config /faststorage/project/nanopore_kga/workflow_dev/apptainer_test/runtime_site.conf \
  --cores 8
```

### Dry run

```bash
bash apptainer_test/run_baked_workflow.sh \
  --sample 05483-13_hg38_ASv2 \
  --input-dir /faststorage/project/nanopore_kga/STORAGE/260602v3_Nanopore_Adaptiv/05483-13 \
  --output-dir /faststorage/project/nanopore_kga/analysis_v2/apptainer \
  --site-config /faststorage/project/nanopore_kga/workflow_dev/apptainer_test/runtime_site.conf \
  --dry-run
```

## What `run_baked_workflow.sh` Does

The host wrapper:

- checks that `workflow_runtime.sif` exists
- checks that `runtime_envs/` exists
- creates a writable state directory:
  - `OUTPUT_DIR/SAMPLE/.snakemake_container_state`
- bind-mounts that directory to:
  - `/opt/workflow/.snakemake`
- optionally creates a small BAM subset under:
  - `OUTPUT_DIR/SAMPLE/.wrapper_subset_input`
- runs the baked container

The container entrypoint then:

- parses the sample token
- chooses the AS or WGS Snakefile
- stages BAMs into:
  - `OUTPUT_DIR/SAMPLE/data/raw/`
- runs Snakemake from `/opt/workflow`

## Why `--subset-reads` Is in the Host Wrapper

`--subset-reads` is intentionally handled in `run_baked_workflow.sh`, not in the baked entrypoint.

Reason:

- changing host wrapper logic does not require rebuilding the image
- changing baked entrypoint logic does require rebuilding the image

So for development convenience, BAM subsetting is done before entering the container.

## Common Failure Modes

### 1. Read-only `.snakemake`

Symptom:

```text
Read-only file system: /opt/workflow/.snakemake
```

Fix:

- use `run_baked_workflow.sh`
- it bind-mounts a writable host directory onto `/opt/workflow/.snakemake`

### 2. Old container behavior after script edits

Symptom:

- usage text or behavior does not match the latest local script edits

Cause:

- the baked image still contains the older script copy

Fix:

- if the changed logic is inside the image, rebuild the image
- if possible, prefer putting fast-changing logic in the host wrapper

### 3. Killed `dorado aligner`

Symptom:

```text
Killed
exit status 137
```

Likely cause:

- login-node kill or insufficient memory

Fix:

- run inside `srun` or `sbatch`
- request real memory

### 4. Stale zero-byte intermediates

Symptom:

- later rules fail on malformed or headerless BAMs

Cause:

- earlier killed run left an empty file behind

Example:

```text
..._aligned_unSorted.bam = 0 bytes
```

Fix:

- clean the test sample output tree before rerun

For example:

```bash
rm -rf /faststorage/project/nanopore_kga/analysis_v2/apptainer/05483-13_hg38_ASv2
```

### 5. Stale Snakemake lock/state

If a run was killed, remove the test state or unlock it before retrying.

Blunt cleanup:

```bash
rm -rf /faststorage/project/nanopore_kga/analysis_v2/apptainer/05483-13_hg38_ASv2/.snakemake_container_state
```

## Design Choice

Current design:

- image contains workflow code and runtime tool stack
- host provides:
  - references
  - models
  - input BAMs
  - output directory
  - site config

This keeps the image reasonably portable while avoiding baking large, change-prone resources such as references and models into every build.

## Operational Advice

- Build images on whichever node class allows Apptainer build reliably.
- Run the workflow on compute nodes, not login nodes.
- Use `--subset-reads 1000` for smoke testing the full container path.
- Clean the apptainer test sample output tree between incompatible test runs.
- Treat `analysis_v2/apptainer/` as disposable test output.

## Older Samtools Smoke Test

The original minimal smoke test is still available:

```bash
bash apptainer_test/build_samtools_container.sh
bash apptainer_test/run_samtools_test.sh
```

That path is useful for verifying basic Apptainer plus Snakemake behavior, but it is separate from the real baked workflow runtime.
