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

Rep_dir=pwd

cd $Rep_dir

# Create a folder for all results
mkdir -p ${Rep_dir}/results

# 1. Quality control on raw reads
conda run -n devoir_2 fastqc $FASTQ -o ${Rep_dir}/results

# 2. Demultiplex barcodes (creates .fq files in the current folder)
sabre se -f $FASTQ -b $BARCODES -u ${Rep_dir}/results/unknown.fq

# 3. Cut adapters and filter low-quality/short reads
for file in *.fq; do
    conda run -n devoir_2 cutadapt -a $ADAPTER -q 20 -m 50 -o ${Rep_dir}/results/$file.fastq $file
done

# 4. Quality control after trimming
conda run -n devoir_2 fastqc ${Rep_dir}/results/*.fastq -o ${Rep_dir}/results

# 5. Index reference genome and align reads (BWA)
conda run -n devoir_2 bwa index $REF

for file in ${Rep_dir}/results/*.fastq; do
    conda run -n devoir_2 bwa mem $REF $file > $file.sam
done

# 6. Convert SAM to BAM, sort, and index (SAMtools)
for file in ${Rep_dir}/results/*.sam; do
    conda run -n samtools view -bS $file > $file.bam
    conda run -n samtools sort $file.bam -o $file.sort.bam
    conda run -n samtools index $file.sort.bam
done

# 7. Call variants (BCFtools)
conda run -n devoir_2 bcftools mpileup -Ob -f $REF results/*.sort.bam > results/variants.bcf
conda run -n devoir_2 bcftools call -mv -Ov results/variants.bcf > results/variants.vcf

# 8. Annotate variants (SnpEff - Bonus)
conda run -n devoir_2 snpeff download $SNPEFF_DB
conda run -n devoir_2 snpeff -stats results/snpeff.html $SNPEFF_DB results/variants.vcf > results/variants.ann.vcf
