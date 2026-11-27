#!/bin/bash
set -euo pipefail

# Choix du nombre de CPU
get_cpu_count() {
    if command -v nproc >/dev/null 2>&1; then
        # Linux et Windows (Git Bash / MSYS2 / WSL)
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        # macOS (et FreeBSD)
        sysctl -n hw.ncpu
    elif [[ -n "${NUMBER_OF_PROCESSORS:-}" ]]; then
        # Fallback natif Windows si nproc est absent
        echo "$NUMBER_OF_PROCESSORS"
    else
        # Valeur par défaut de sécurité
        echo 1
    fi
}

NB_CPU=$(get_cpu_count)
CPU=$(( NB_CPU / 3 ))
if (( CPU < 1 )); then
    CPU=1
fi
echo "Nombre de CPU détectés : $NB_CPU"
echo "Nombre de CPU utilisés pour l'analyse : $CPU"

# Entrées (passées en arguments après le nom du script lors de l'exécution)
# Exemple : ./Pipeline.sh data/reads.fq.gz ref/genome.fa data/barcodes.txt /chemin/vers/sabre

echo "Merci d'entrer les entrées du pipeline :"
echo "Chemin du fichier FastQ :"
FASTQ=$1
echo "Chemin du fichier du génome de référence :"
REF=$2
echo "Chemin du fichier de codes-barres :"
BARCODES=$3
echo "Chemin vers Sabre (outil de démultiplexage par codes-barres) :"
SABRE=$4

ADAPTER="AGATCGGAA"
SNPEFF_DB="Glycine_max"

Rep_dir="$(pwd)"
RESULTS_DIR="${Rep_dir}/results"
DEMUX_DIR="${RESULTS_DIR}/demux"

# Créer les dossiers pour tous les résultats
mkdir -p "${RESULTS_DIR}" "${DEMUX_DIR}"

conda activate devoir_2

# 1. Contrôle de qualité sur les lectures brutes
echo "=============================================="
echo "Contrôle de qualité sur les lectures brutes"
conda run -n devoir_2 fastqc -t $CPU $FASTQ -o ${Rep_dir}/results

# 2. Démultiplexage des codes-barres (fichiers .fq rangés dans results/demux/)
echo "=============================================="
echo "Démultiplexage des codes-barres"
$SABRE se -f $FASTQ -b $BARCODES -u ${Rep_dir}/results/unknown.fq

# 3. Coupure des adaptateurs et filtrage des lectures courtes ou de faible qualité
echo "=============================================="
for file in *.fq; do
    conda run -n devoir_2 cutadapt -a $ADAPTER -q 20 -m 50 -o ${Rep_dir}/results/$file.fastq $file
done

# 4. Contrôle de qualité après découpage
echo "=============================================="
echo "Contrôle de qualité sur les lectures sans adaptateur"
conda run -n devoir_2 fastqc -t $CPU ${Rep_dir}/results/*.fastq -o ${Rep_dir}/results

# 5. Indexation du génome de référence et alignement des lectures (BWA)
echo "=============================================="
echo "Indexation du génome de référence et alignement des lectures"
conda run -n devoir_2 bwa index $REF

echo "=============================================="
echo "Mapping des lectures"
for file in ${Rep_dir}/results/*.fastq; do
    conda run -n devoir_2 bwa mem -t $CPU $REF $file > $file.sam
done

# 6. Conversion SAM vers BAM, tri et indexation (SAMtools)
echo "=============================================="
echo "Conversion SAM vers BAM, tri et indexation"
for file in ${Rep_dir}/results/*.sam; do
    conda run -n devoir_2 samtools view -bS $file > $file.bam
    conda run -n devoir_2 samtools sort -@ $CPU $file.bam -o $file.sort.bam
    conda run -n devoir_2 samtools index $file.sort.bam
done

# 7. Appel de variants (BCFtools)
echo "=============================================="
conda run -n devoir_2 bcftools mpileup -Ob -f $REF ${Rep_dir}/results/*.sort.bam > ${Rep_dir}/results/variants.bcf
conda run -n devoir_2 bcftools call -mv -Ov ${Rep_dir}/results/variants.bcf > ${Rep_dir}/results/variants.vcf

# 8. Annotation des variants (SnpEff - Bonus)
echo "=============================================="
conda run -n devoir_2 snpEff download $SNPEFF_DB
conda run -n devoir_2 snpEff -stats ${Rep_dir}/results/snpeff.html $SNPEFF_DB ${Rep_dir}/results/variants.vcf > ${Rep_dir}/results/variants.ann.vcf
