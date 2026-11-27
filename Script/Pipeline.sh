#!/bin/bash

#path

DATA_dir=~/input_data/GBS_data
TOOL=path/to/sabre
REF=/home/dator/refgenome/Gmax_275_v2.0.fa
CPU=3
THR=2
BWA=/home/dator/bwa/bwa



OUT=variantcalling
CPU=4

#FASTQ, traitement de qualiter des séquences pre_adaptateur

fastqc ~/input_data/GBS_data/FC20150701_1.fq.gz

while true; do
	printf "Inspect the fastqc report, is everything in order? [y/n]: " >/dev/tty
	read -r rep </dev/tty || exit 1
	case "$rep" in
		[yY]*) break ;;
		[nN]*) echo "Pipeline aborted"; exit 0 ;;
		*) echo "Please answer y or n" >/dev/tty ;;
	esac
done

#Demultiplex les code bar

exec &> sabre.log

$TOOL se -f $DATA -b $BARCODE -u unk.fastq
	
#Coupe les adpatateur et code bar
cd NGS
ADAP=AGATCGGAA 
exec &> cutadapt.log
parallel -j 4 cutadapt -a $ADAP -m 50 -o {}.fastq {}.fq ::: $(ls -1 *.fq | sed 's/.fq//')
	if [ $? -ne 0 ]
		then
			printf There is error in the cutadapt
			exit 1
	fi

#FASTQ, traitement de qualiter des séquences post_adaptateur



fastqc ~/input_data/GBS_data/

while true; do
	printf "Inspect the fastqc report, is everything in order? [y/n]: " >/dev/tty
	read -r rep </dev/tty || exit 1
	case "$rep" in
		[yY]*) break ;;
		[nN]*) echo "Pipeline aborted"; exit 0 ;;
		*) echo "Please answer y or n" >/dev/tty ;;
	esac
done



#mapping des read sur le génome de référence

exec &> bwa.log
cd $DATA
		parallel -j $CPU $BWA mem -t $THR $REF {}.fastq ">" {}.sam ::: $(ls -1 *.fastq | sed 's/.fastq//')
		if [ $? -ne 0 ]
			then 
				printf There is a problem in the alignment step
				exit 1
		fi


#conversiton Sam -> Bam

CPU=4

cd NGS
# create a log file
exec &> convert.log

# convert SAM format to BAM format

parallel -j $CPU samtools view -b -S -h {}.sam ">" {}.temp.bam ::: $(ls -1 *.sam | sed 's/.sam//')
		if [ $? -ne 0 ]
			then 
				printf "There is a problem in the samtools-view step"
				exit 1
		fi
# sort BAM files

parallel -j $CPU samtools sort {}.temp.bam -o {}.sort.bam ::: $(ls -1 *.temp.bam | sed 's/.temp.bam//')
		if [ $? -ne 0 ]
			then 
				printf "There is a problem in the samtools-sort step"
				exit 1
		fi

# indexing of BAM files
parallel -j $CPU samtools index {} ::: $(ls -1 *.sort.bam)
		if [ $? -ne 0 ]
			then 
				printf "There is a problem in the samtools-index step"
				exit 1
		fi

# create a list of BAM files with path

for i in $(ls -1 *.sort.bam)
			do
				printf "$PWD/${i}\n" >> "bamlist"
				if [ $? -ne 0 ]
					then 
					printf "There is a problem in the production of the bam file list"
					exit 1
				fi
			done



#BCF tools, appelle des variants


DATA=/home/dator/NGS/bamlist
REF=/home/dator/refgenome/Gmax_275_v2.0.fa
OUT=variantcalling
CPU=4

mkdir results1
cd results1

exec &> samt_var.log

samtools mpileup -g -f $REF -b $DATA > variants.bcf

	if [ $? -ne 0 ]
                        then
                                printf "There is a problem at the samtools_mpileup step"
                                exit 1
                fi


bcftools call -mv variants.bcf > variants.vcf

	if [ $? -ne 0 ]
                        then
                                printf "There is a problem at the bcf2vcf step"
                                exit 1
                fi



#SnpEff, annotation du génome
snpEff databases | grep -i glycine
snpEff -v -stats variants.snpeff.html DATABASE_ID variants.vcf > variants.ann.vcf
