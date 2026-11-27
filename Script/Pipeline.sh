#!/bin/bash
set -euo pipefail

<<<<<<< HEAD
#path
DATA_dir=~/input_data/GBS_data
REF=/home/dator/refgenome/Gmax_275_v2.0.fa
OUT=variantcalling
CPU=4

#FASTQ, traitement de qualiter des séquences pre_adaptateur
fastqc ~/input_data/GBS_data/FC20150701_1.fq.gz -o ~/output_data/fastqc_output
=======
# Vérification des 2 arguments obligatoires : FASTQ et Génome de référence
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <reads.fq.gz> <ref.fa> [barcodes.txt] [snpeff_db] [adaptateur]"
    exit 1
fi

# Paramètres (chemins relatifs et valeurs par défaut flexibles)
FASTQ="$1"
REF="$2"
BARCODES="${3:-}"
SNPEFF_DB="${4:-}"
ADAPTER="${5:-AGATCGGAAGAGC}"
OUT="results"
CPU=4

# Création des dossiers de sortie
mkdir -p "$OUT"/{qc,demux,trimmed,bam,vcf,logs}

# 1. Contrôle de qualité (QC) des données brutes
fastqc -t "$CPU" -o "$OUT/qc" "$FASTQ" &> "$OUT/logs/1_fastqc_raw.log"
>>>>>>> 3d9b5edcc00c54e51f4d2a0134fbdcb4a46c1836

# 2. Démultiplexage (si fichier de codes-barres fourni) + Découpage/Filtrage
if [[ -n "$BARCODES" ]]; then
    (cd "$OUT/demux" && sabre se -f "$(realpath "$FASTQ")" -b "$(realpath "$BARCODES")" -u unk.fq) &> "$OUT/logs/2_sabre.log"
    INPUTS=("$OUT"/demux/*.fq)
else
    INPUTS=("$FASTQ")
fi

<<<<<<< HEAD
#Demultiplex les code bar
exec &> sabre.log

conda run -n ngs_gbs sabre se -f "/Users/olivier_v/Desktop/Devoir_BVG_7003/Devoir_2/input_data/GBS_data/FC20150701_1.fq.gz" -b "/Users/olivier_v/Desktop/Devoir_BVG_7003/Devoir_2/input_data/GBS_data/FC20150701_1.txt" -u "/Users/olivier_v/Desktop/Devoir_BVG_7003/Devoir_2/input_data/GBS_data/unk.fastq"
	
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
=======
parallel -j "$CPU" "cutadapt -a $ADAPTER -q 20 -m 50 -o $OUT/trimmed/{/.}.fastq {}" ::: "${INPUTS[@]}" &> "$OUT/logs/2_cutadapt.log"
fastqc -t "$CPU" -o "$OUT/qc" "$OUT"/trimmed/*.fastq &> "$OUT/logs/2_fastqc_trimmed.log"

# 3 & 4. Indexation (si absente), Alignement (BWA) et Post-traitement (SAMtools)
[[ ! -f "${REF}.bwt" ]] && bwa index "$REF" &> "$OUT/logs/3_bwa_index.log"
[[ ! -f "${REF}.fai" ]] && samtools faidx "$REF"

parallel -j "$CPU" \
    "bwa mem -t 2 $REF {} | samtools sort -o $OUT/bam/{/.}.bam - && samtools index $OUT/bam/{/.}.bam" \
    ::: "$OUT"/trimmed/*.fastq &> "$OUT/logs/3_align_sort.log"
>>>>>>> 3d9b5edcc00c54e51f4d2a0134fbdcb4a46c1836

# 5. Appel de variants (BCFtools)
bcftools mpileup -Ou -f "$REF" "$OUT"/bam/*.bam 2> "$OUT/logs/5_mpileup.log" | \
    bcftools call -mv -Ov -o "$OUT/vcf/variants.vcf" 2> "$OUT/logs/5_call.log"

# 6. Annotation fonctionnelle (SnpEff - bonus optionnel)
if [[ -n "$SNPEFF_DB" ]]; then
    snpEff download "$SNPEFF_DB" &> "$OUT/logs/6_snpeff_dl.log" || true
    snpEff -stats "$OUT/vcf/snpeff.html" "$SNPEFF_DB" "$OUT/vcf/variants.vcf" \
        > "$OUT/vcf/variants.ann.vcf" 2> "$OUT/logs/6_snpeff.log"
fi

echo "Terminé ! Fichiers générés dans : $OUT/"
