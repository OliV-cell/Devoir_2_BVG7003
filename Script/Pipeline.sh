#!/bin/bash
set -euo pipefail

#choix du nombre de CPU

while true; do
	printf "Quelle nombre de CPU voulez vous utiliser?: " >/dev/tty
	read -r rep </dev/tty || exit 1
	case "$rep" in  
		[1-9]*[0-9]) CPU="$rep"; break ;;
		*) echo "Veuillez entrer un nombre de CPU valide" >/dev/tty ;;
	esac
done

#!/bin/bash

# Inputs (typed after the script name when you run it)
# Example: ./pipeline.sh data/reads.fq.gz ref/genome.fa data/barcodes.txt
FASTQ=$1
REF=$2
BARCODES=$3
ADAPTER="AGATCGGAA"
SNPEFF_DB="Glycine_max"

# Create a folder for all results
mkdir -p results

# 1. Quality control on raw reads
fastqc $FASTQ -o results

# 2. Demultiplex barcodes (creates .fq files in the current folder)
sabre se -f $FASTQ -b $BARCODES -u results/unknown.fq

# 3. Cut adapters and filter low-quality/short reads
for file in *.fq; do
    cutadapt -a $ADAPTER -q 20 -m 50 -o results/$file.fastq $file
done

# 4. Quality control after trimming
fastqc results/*.fastq -o results

# 5. Index reference genome and align reads (BWA)
bwa index $REF

for file in results/*.fastq; do
    bwa mem $REF $file > $file.sam
done

# 6. Convert SAM to BAM, sort, and index (SAMtools)
for file in results/*.sam; do
    samtools view -bS $file > $file.bam
    samtools sort $file.bam -o $file.sort.bam
    samtools index $file.sort.bam
done

# 7. Call variants (BCFtools)
bcftools mpileup -Ob -f $REF results/*.sort.bam > results/variants.bcf
bcftools call -mv -Ov results/variants.bcf > results/variants.vcf

# 8. Annotate variants (SnpEff - Bonus)
snpEff download $SNPEFF_DB
snpEff -stats results/snpeff.html $SNPEFF_DB results/variants.vcf > results/variants.ann.vcf
