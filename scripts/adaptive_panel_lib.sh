#!/usr/bin/env bash

ADAPTIVE_PANEL_BED_FILES=(
  "/faststorage/project/nanopore_kga/uploaded/adaptiveSampling_hg38_v2.bed"
  "/faststorage/project/nanopore_kga/uploaded/RB_adaptiveSampling_GRCh38_v3.bed"
)

select_best_adaptive_panel() {
  local bam_file="$1"
  local best_bed=""
  local best_mean=""
  local bed_file
  local panel_mean

  for bed_file in "${ADAPTIVE_PANEL_BED_FILES[@]}"; do
    if [[ ! -f "$bed_file" ]]; then
      echo "ERROR: BED file not found: $bed_file" >&2
      return 1
    fi

    panel_mean="$(
      samtools bedcov "$bed_file" "$bam_file" \
        | awk '
            {
              len = $3 - $2
              if (len <= 0) {
                next
              }
              sum += ($NF / len)
              n += 1
            }
            END {
              if (n == 0) {
                print 0
              } else {
                printf "%.10f\n", sum / n
              }
            }
          '
    )"

    if [[ -z "$best_mean" ]] || awk -v current="$panel_mean" -v best="$best_mean" 'BEGIN { exit !(current > best) }'; then
      best_mean="$panel_mean"
      best_bed="$bed_file"
    fi
  done

  printf '%s\n' "$best_bed"
}
