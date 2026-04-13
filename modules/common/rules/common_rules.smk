# Rules that are used in both AS and WGS pipeline



##################################################
#                DATA PREPARATION                #
##################################################

# Create list of all intermediate BAM files from sequencing
rule BAMlist:
  output:
    temp("../analysis/{sample}/data/bamlist.txt")
  message:
    "Creating list of bam files to be merged: {wildcards.sample}"
  params:
    rawDir = "../analysis/{sample}/data/raw"
  shell:
    "ls -d $PWD/{params.rawDir}/*.* | grep '.bam' | grep -v '.bai' > {output}"



# Merge intermediate BAM files
rule mergeBAMs:
  input:
    "../analysis/{sample}/data/bamlist.txt"
  output:
    temp("../analysis/{sample}/data/{sample}_unSorted.bam")
  message:
    "Merging BAMs: {wildcards.sample}"
  conda:
    "../../../envs/samtools.yaml"
  shell:    
    "samtools merge "
    "-b {input} "
    "-o {output} "
    "--threads {threads}"



# Sort merged BAM
rule sortMergedBAM:
  input:
    "../analysis/{sample}/data/{sample}_unSorted.bam"
  output:
    protected("../analysis/{sample}/data/{sample}.bam")
  message:
    "Sorting BAM: {wildcards.sample}"
  conda:
    "../../../envs/samtools.yaml"
  shell:
    "samtools sort "
    "{input} "
    "-o {output} "
    "-@ {threads}"



# Index merged BAM
rule indexMergedBAM:
  input:
    "../analysis/{sample}/data/{sample}.bam"
  output:
    protected("../analysis/{sample}/data/{sample}.bam.bai")
  message:  
    "Indexing {input}"
  conda:
    "../../../envs/samtools.yaml"
  shell:
    "samtools index "
    "{input} "
    "--threads {threads}"



##################################################
#                QUALITY CONTROL                 #
##################################################

rule nanoPlot:
  input:
    bam = "../analysis/{sample}/data/{sample}.bam",
    bai = "../analysis/{sample}/data/{sample}.bam.bai"
  output:
    outDir = directory("../analysis/{sample}/QC"),
    html = "../analysis/{sample}/QC/{sample}_NanoPlot-report.html"
  message:  
    "NanoPlot: {wildcards.sample}"
  conda:
    "../../../envs/nanoPlot.yaml"
  params:
    "--prefix {sample}_",
    "--N50"
  shell:
    "NanoPlot "
    "--bam {input.bam} "
    "--outdir {output.outDir} "
    "--threads {threads} "
    "{params}"


##################################################
#                VARIANT CALLING                 #
##################################################

# Run Clair3
rule clair3:
  input:
    bam = "../analysis/{sample}/data/{sample}.bam",
    bai = "../analysis/{sample}/data/{sample}.bam.bai",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"])
  output:
    vcf = "../analysis/{sample}/variants/phased_merge_output.vcf.gz",
    tbi = "../analysis/{sample}/variants/phased_merge_output.vcf.gz.tbi",
    bam = "../analysis/{sample}/variants/phased_output.bam",
    bai = "../analysis/{sample}/variants/phased_output.bam.bai"
  message:
    "Clair3: {wildcards.sample}"
  conda:
    "../../../envs/clair3.yaml"
  params:
    "--output=../analysis/{sample}/variants/",
    "--include_all_ctgs",
    "--platform='ont'",
    "--use_whatshap_for_final_output_haplotagging",
    "--remove_intermediate_dir"
  shell:
    "run_clair3.sh "
    "--bam_fn={input.bam} "
    "--ref_fn={input.ref} "
    "--threads={threads} " 
    "--model_path={config[softwareDir]}/clair3_models/{config[clair3Model]} "
    "{params} "
  


# Rename, move and delete files
rule clair3CleanUp:
  input:
    bam = "../analysis/{sample}/variants/phased_output.bam",
    bai = "../analysis/{sample}/variants/phased_output.bam.bai",
    vcf = "../analysis/{sample}/variants/phased_merge_output.vcf.gz",
    tbi = "../analysis/{sample}/variants/phased_merge_output.vcf.gz.tbi"
  output:
    bam = protected("../analysis/{sample}/data/{sample}.haplotagged.bam"),
    bai = protected("../analysis/{sample}/data/{sample}.haplotagged.bam.bai"),
    vcf = protected("../analysis/{sample}/variants/{sample}_clair3.vcf.gz"),
    tbi = protected("../analysis/{sample}/variants/{sample}_clair3.vcf.gz.tbi")
  message:
    "Cleaning up files after variant calling"
  shell:
    "mv {input.bam} {output.bam} "
    "&& mv {input.bai} {output.bai} "
    "&& mv {input.vcf} {output.vcf} "
    "&& mv {input.tbi} {output.tbi} "
    "&& mkdir -p ../analysis/{wildcards.sample}/logs && mv ../analysis/{wildcards.sample}/variants/log ../analysis/{wildcards.sample}/logs/clair3 "
    "; mkdir -p ../analysis/{wildcards.sample}/logs/clair3 && mv ../analysis/{wildcards.sample}/variants/run_clair3.log ../analysis/{wildcards.sample}/logs/clair3/run_clair3.log "
    "; rm ../analysis/{wildcards.sample}/variants/full_alignment.vcf.gz* "
    "; rm ../analysis/{wildcards.sample}/variants/pileup.vcf.gz* "
    "; rm ../analysis/{wildcards.sample}/variants/merge_output.vcf.gz*"



##################################################
#                   METHYLATION                  #
##################################################

# Update MM tags in imprint BAM
rule updateTags:
  input:
    bam = "../analysis/{sample}/data/{sample}.haplotagged.bam",
    bai = "../analysis/{sample}/data/{sample}.haplotagged.bam.bai"
  output:
    temp("../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam")
  message:
    "Updating tags in {input.bam}"
  params:
    mode = "--mode implicit",
    log = "--log-filepath ../analysis/{sample}/logs/modkit/{sample}_updateTags.log",
    modkit = expand("{softwareDir}/modkit_{version}/modkit", softwareDir=config["softwareDir"], version=config["modkitVersion"])
  shell:
    "{params.modkit} update-tags "
    "{params.mode} "
    "{params.log} "
    "--threads {threads} "
    "{input.bam} "
    "{output}"


# Index imprint BAM with updated tags
rule indexUpdatedBAM:
  input:
    "../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam"
  output:
    temp("../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam.bai")
  message:
    "Indexing {input}"
  conda:
    "../../../envs/samtools.yaml"
  params:
    "-M"
  shell:
    "samtools index "
    "{params} "
    "{input} "
    "--threads {threads}"



# Run Modkit on BAM file to create bedMethtyl file
rule modkitPileupFull:
  input:
    bam = "../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam",
    bai = "../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam.bai",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"])
  output:
    bed = "../analysis/{sample}/methylation/{sample}_full_pileup.bed"
  message:
    "Modkit pileup: {wildcards.sample}"
  params:
    preset = "--preset traditional",
    log = "--log-filepath ../analysis/{sample}/logs/modkit/{sample}_full_pileup.log",
    thresh = expand("--filter-threshold {threshold}", threshold=config["modkitThreshold"])[0],
    modkit = expand("{softwareDir}/modkit_{version}/modkit", softwareDir=config["softwareDir"], version=config["modkitVersion"])
  shell:
    "{params.modkit} pileup "
    "{input.bam} "
    "{output.bed} "
    "--ref {input.ref} "
    "--threads {threads} "
    "{params.thresh} "
    "{params.preset} "
    "{params.log} "



# Run Modkit on haplo-specific BAMs to create haplotype-specific bedMethyl files
rule modkitPileupHaplotypes:
  input:
    bam = "../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam",
    bai = "../analysis/{sample}/methylation/{sample}.haplotagged.updated.bam.bai",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"])
  output:
    hap1 = "../analysis/{sample}/methylation/haplotypeOutput/{sample}_pileup_1.bed",
    hap2 = "../analysis/{sample}/methylation/haplotypeOutput/{sample}_pileup_2.bed",
    unHap = "../analysis/{sample}/methylation/haplotypeOutput/{sample}_pileup_ungrouped.bed"
  message:
    "Modkit pileup: {wildcards.sample}"
  params:
    outDir = "../analysis/{sample}/methylation/haplotypeOutput",
    preset = "--preset traditional",
    log = "--log-filepath ../analysis/{sample}/logs/modkit/{sample}_haplotypes_pileup.log",
    thresh = expand("--filter-threshold {threshold}", threshold=config["modkitThreshold"])[0],
    modkit = expand("{softwareDir}/modkit_{version}/modkit", softwareDir=config["softwareDir"], version=config["modkitVersion"]),
    prefix = "--prefix {sample}_pileup",
    partition = "--partition-tag HP"
  shell:
    "{params.modkit} pileup "
    "{input.bam} "
    "{params.outDir} "
    "--ref {input.ref} "
    "--threads {threads} "
    "{params.thresh} "
    "{params.preset} "
    "{params.log} "
    "{params.prefix} "
    "{params.partition}"



# Rename bedMethyls
rule renameBedMethyls:
  input:
    hap1 = "../analysis/{sample}/methylation/haplotypeOutput/{sample}_pileup_1.bed",
    hap2 = "../analysis/{sample}/methylation/haplotypeOutput/{sample}_pileup_2.bed",
    ungrouped = "../analysis/{sample}/methylation/haplotypeOutput/{sample}_pileup_ungrouped.bed"
  output:
    hap1 = temp("../analysis/{sample}/methylation/{sample}_hap1_pileup.bed"),
    hap2 = temp("../analysis/{sample}/methylation/{sample}_hap2_pileup.bed"),
    ungrouped = temp("../analysis/{sample}/methylation/{sample}_unHap_pileup.bed")
  message: 
    "Renaming output files from modkit pileup"
  shell:
    "mv {input.hap1} {output.hap1} ; "
    "mv {input.hap2} {output.hap2} ; "
    "mv {input.ungrouped} {output.ungrouped}"



# Bgzip bedMethyl files
rule bgzipBedMethyl:
  input:
    "../analysis/{sample}/methylation/{sample}_{haplotype}_pileup.bed"
  output:
    protected("../analysis/{sample}/methylation/{sample}_{haplotype}_pileup.bed.gz")
  message:
    "Bgzipping {input}"
  conda:
    "../../../envs/samtools.yaml"
  shell:
    "bgzip "
    "-k "
    "{input}"



# Index bedMethyl files
rule indexBedMethyl:
  input:
    "../analysis/{sample}/methylation/{sample}_{haplotype}_pileup.bed.gz"
  output:
    protected("../analysis/{sample}/methylation/{sample}_{haplotype}_pileup.bed.gz.tbi")
  message:
    "Indexing {input}"
  conda:
    "../../../envs/samtools.yaml"
  params:
    "-p bed"
  shell:
    "tabix "
    "{params} "
    "{input} "
    "--threads {threads}"



#-------------#
# NanoImprint #
#-------------#

# Extract imprinting regions from 
rule extractImprintRegions:
  input:
    a = "../analysis/{sample}/methylation/{sample}_{haplotype}_pileup.bed.gz",
    tbi = "../analysis/{sample}/methylation/{sample}_{haplotype}_pileup.bed.gz.tbi",
    b = expand("{dataDir}/nanoImprintRegions_{reference}.bed", dataDir=config["dataDir"], reference=config["refGenome"])
  output:
    temp("../analysis/{sample}/methylation/{sample}_{haplotype}_pileup_imprintGenes.bed")
  message:
    "Extracting imprinting genes from bedMethyl files: {wildcards.sample}"
  conda:
    "../../../envs/bedtools.yaml"
  params:
    "-wa"
  shell:
    "bedtools intersect "
    "-a {input.a} "
    "-b {input.b} "
    "{params} "
    "> {output}"
    


# Imprinting gene analysis with NanoImprint
rule nanoImprint:
  input:
    H1 = "../analysis/{sample}/methylation/{sample}_hap1_pileup_imprintGenes.bed",
    H2 = "../analysis/{sample}/methylation/{sample}_hap2_pileup_imprintGenes.bed",
    full = "../analysis/{sample}/methylation/{sample}_full_pileup_imprintGenes.bed",
    control = expand("{dataDir}/ctrls_{ref}_wChr.xlsx", dataDir=config["dataDir"], ref=config["refGenome"]),
    regions = expand("{dataDir}/nanoImprintRegions_{ref}.bed", dataDir=config["dataDir"], ref=config["refGenome"])
  output:
    "../analysis/{sample}/methylation/{sample}_NanoImprint_v2.0.html"
  message:
    "NanoImprint: {wildcards.sample} "
  conda:
    "../../../envs/nanoImprint.yaml"
  params:
    ref = config["refGenome"],
    sample = "{sample}"
  script:
    "../../../scripts/NanoImprint_v2.0.Rmd"



#---------#
#   DMR   #
#---------#

# Modkit DMR pair segment
rule dmrPairSegment:
  input:
    bed = "../analysis/{sample}/methylation/{sample}_full_pileup.bed.gz",
    tbi = "../analysis/{sample}/methylation/{sample}_full_pileup.bed.gz.tbi",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"]),
    normal1 = expand("{dataDir}/dmrNormals/1036-24_{ref}.bed.gz", dataDir=config["dataDir"], ref=config["refGenome"]),
    normal2 = expand("{dataDir}/dmrNormals/2673-24_{ref}.bed.gz", dataDir=config["dataDir"], ref=config["refGenome"]),
  output:
    bed = temp("../analysis/{sample}/methylation/DMR/{sample}_dmrPair_perCpG.bed"),
    segments = temp("../analysis/{sample}/methylation/DMR/{sample}_dmrPair_segments.bed")
  params:
    header = "--header",
    force = "--force",
    base = "C",
    batchSize = "32",
    log = "../analysis/{sample}/logs/modkit/{sample}_dmrPair.log",
    sigFac = expand("{sigFac}", sigFac=config["significanceFactor"]),
    minCov = expand("{minCov}", minCov=config["minimumCoverage"]),
    modkit = expand("{softwareDir}/modkit_{version}/modkit", softwareDir=config["softwareDir"], version=config["modkitVersion"])
  shell:
    "{params.modkit} dmr pair "
    "-a {input.normal1} "
    "-a {input.normal2} "
    "-b {input.bed} "
    "-o {output.bed} "
    "--ref {input.ref} "
    "--segment {output.segments} "
    "--threads {threads} "
    "{params.header} "
    "{params.force} "
    "--base {params.base} "
    "--batch-size {params.batchSize} "
    "--log-filepath {params.log} "
    "--significance-factor {params.sigFac} "
    "--min-valid-coverage {params.minCov}"



# Bgzip bedMethyl files (sort first or indexing will fail)
rule bgzipDmrPairBed:
  input:
    "../analysis/{sample}/methylation/DMR/{sample}_dmrPair_{X}.bed"
  output:
    "../analysis/{sample}/methylation/DMR/{sample}_dmrPair_{X}.bed.gz"
  message:
    "Bgzipping {input}"
  conda:
    "../../../envs/samtools.yaml"
  shell:
    "awk 'NR==1 && $1==\"chrom\" {{next}} {{print}}' {input} | "
    "sort -k 1,1 -k2,2n | "
    "bgzip > {output}"



# Index bedMethyl files
rule indexDmrPairBed:
  input:
    "../analysis/{sample}/methylation/DMR/{sample}_dmrPair_{X}.bed.gz"
  output:
    "../analysis/{sample}/methylation/DMR/{sample}_dmrPair_{X}.bed.gz.tbi"
  message:
    "Indexing {input}"
  conda:
    "../../../envs/samtools.yaml"
  params:
    "-p bed"
  shell:
    "tabix "
    "{params} "
    "{input} "
    "--threads {threads}"



##################################################
#               STRUCTURAL VARIANTS              #
##################################################

# Run Sniffles2
rule sniffles2:
  input:
    bam = "../analysis/{sample}/data/{sample}.bam",
    bai = "../analysis/{sample}/data/{sample}.bam.bai",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"])
  output:
    vcf = protected("../analysis/{sample}/structural_variation/{sample}_sniffles2.vcf.gz")
  message:
    "Sniffles2: {wildcards.sample} "
  conda:
    "../../../envs/sniffles2.yaml"
  shell:
    "sniffles "
    "-i {input.bam} "
    "-v {output.vcf} "
    "--reference {input.ref}"



# Run cuteSV
rule cuteSV:
  input:
    bam = "../analysis/{sample}/data/{sample}.bam",
    bai = "../analysis/{sample}/data/{sample}.bam.bai",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"])
  output:
    vcf = "../analysis/{sample}/structural_variation/{sample}_cuteSV.vcf",
    workDir = temp(directory("../analysis/{sample}/structural_variation/tmp"))
  message:
    "CuteSV: {wildcards.sample} "
  conda:
    "../../../envs/cuteSV.yaml"
  params:
    bias_INS = expand("--max_cluster_bias_INS {value}", value=config["CUTESV_max_cluster_bias_INS"]),
    ratio_INS = expand("--diff_ratio_merging_INS {value}", value=config["CUTESV_diff_ratio_merging_INS"]),
    bias_DEL = expand("--max_cluster_bias_DEL {value}", value=config["CUTESV_max_cluster_bias_DEL"]),
    ratio_DEL = expand("--diff_ratio_merging_DEL {value}", value=config["CUTESV_diff_ratio_merging_DEL"])
  shell:
    "mkdir -p {output.workDir} "
    "&& "
    "cuteSV "
    "{params.bias_INS} "
    "{params.ratio_INS} "
    "{params.bias_DEL} "
    "{params.ratio_DEL} "
    "--sample {wildcards.sample} "
    "{input.bam} "
    "{input.ref} "
    "{output.vcf} "
    "{output.workDir}"



# Bgzip cuteSV output vcf
rule bgzipVCF:
  input:
    "../analysis/{sample}/structural_variation/{sample}_cuteSV.vcf"
  output:
    protected("../analysis/{sample}/structural_variation/{sample}_cuteSV.vcf.gz")
  message:
    "Bgzipping CuteSV VCF file: {wildcards.sample}"
  conda:
    "../../../envs/samtools.yaml"
  shell:
    "bgzip "
    "{input} "
    "--threads {threads}"
  


# Index cuteSV output vcf
rule indexVCF:
  input:
    "../analysis/{sample}/structural_variation/{sample}_cuteSV.vcf.gz"
  output:
    protected("../analysis/{sample}/structural_variation/{sample}_cuteSV.vcf.gz.tbi")
  message:
    "Indexing CuteSV VCF file: {wildcards.sample}"
  conda:
    "../../../envs/samtools.yaml"
  params:
    "-p vcf"
  shell:
    "tabix "
    "{params} "
    "{input} "
    "--threads {threads}"



##################################################
#              COPY NUMBER VARIANTS              #
##################################################

# Clean up after hifiCNV
rule hifiCNV_cleanup:
  input:
    bedgraph = "../analysis/{sample}/CNV/{sample}_hifiCNV.Sample0.copynum.bedgraph",
    depth_bw = "../analysis/{sample}/CNV/{sample}_hifiCNV.Sample0.depth.bw",
    vcf = "../analysis/{sample}/CNV/{sample}_hifiCNV.Sample0.vcf.gz",
    maf_bw = "../analysis/{sample}/CNV/{sample}_hifiCNV.SAMPLE.maf.bw"
  output:
    bedgraph = "../analysis/{sample}/CNV/{sample}_hifiCNV.copynum.bedgraph",
    depth_bw = "../analysis/{sample}/CNV/{sample}_hifiCNV.depth.bw",
    vcf = "../analysis/{sample}/CNV/{sample}_hifiCNV.vcf.gz",
    maf_bw = "../analysis/{sample}/CNV/{sample}_hifiCNV.maf.bw"
  message:
    "Cleaning up after hifiCNV: {wildcards.sample}"
  shell:
    "mv {input.bedgraph} {output.bedgraph} ; "
    "mv {input.depth_bw} {output.depth_bw} ; "
    "mv {input.vcf} {output.vcf} ; "
    "mv {input.maf_bw} {output.maf_bw}"



##################################################
#                    REPEATS                     #
##################################################

# Run straglr
rule straglr:
  input:
    bam = "../analysis/{sample}/data/{sample}.bam",
    bai = "../analysis/{sample}/data/{sample}.bam.bai",
    ref = expand("{referenceDir}/{reference}", referenceDir=config["referenceDir"], reference=config["refFile"])
  output:
    "../analysis/{sample}/STR/{sample}_straglr.bed",
    "../analysis/{sample}/STR/{sample}_straglr.tsv",
    "../analysis/{sample}/STR/{sample}_straglr.vcf"
  message:
    "Straglr: {wildcards.sample}"
  conda:
    "../../../envs/straglr.yaml"
  params:
    prefix = "../analysis/{sample}/STR/{sample}_straglr",
    sample = "--sample {sample}",
    chroms = "--include_alt_chroms"
  shell:
    "python3 scripts/straglr.py "
    "{input.bam} "
    "{input.ref} "
    "{params.prefix} "
    "{params.sample} "
    "{params.chroms} "
    "--nprocs {threads}"


##################################################
#                   VCF NAMES                    #
##################################################
# Run post-modification of VCF (only required are clair3 and hifiCNV)
#

rule vcfrename:
  input:
    vcfclair = "../analysis/{sample}/variants/{sample}_clair3.vcf.gz",
    vcfhifi = "../analysis/{sample}/CNV/{sample}_hifiCNV.vcf.gz"
  output:
    vcfclair = "../analysis/{sample}/renamed_vcfs/variants_{sample}_clair3.vcf.gz",
    vcfhifi = "../analysis/{sample}/renamed_vcfs/CNV_{sample}_hifiCNV.vcf.gz"
  message:
    "Renaming VCF-header: {wildcards.sample} "
  conda:
    "../../../envs/bcftools.yaml"
  shell:
    "echo 'Required samples for renaming process:' ; "
    "echo '{input.vcfclair}' ; "
    "echo '{input.vcfhifi}' ; "
    "echo 'Output sample:' ; "
    "echo '{output.vcfclair}' ; "
    "echo '{output.vcfhifi}' ; "
    "scripts/rename_sample_name_VCF_recursive.sh ../analysis/{wildcards.sample} {wildcards.sample} ; "
