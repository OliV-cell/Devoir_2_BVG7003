#!/bin/bash
set -euo pipefail

eval "$(conda shell.bash hook)"
conda activate devoir_2

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
CPU=$(( NB_CPU / 2 ))
if (( CPU < 1 )); then
    CPU=1
fi
echo "Nombre de CPU détectés : $NB_CPU"
echo "Nombre de CPU utilisés pour l'analyse : $CPU"

# Entrées (passées en arguments après le nom du script lors de l'exécution)
# Exemple : ./Pipeline.sh ../input_data/GBS_data/FC20150701_1.fq.gz ref/genome.fa ../input_data/GBS_data/FC20150701_1.txt ../Tools/sabre/sabre
abs_path() {
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

FASTQ="$(abs_path "$1")"
REF="$(abs_path "$2")"
BARCODES="$(abs_path "$3")"
if [[ -e "$4" ]]; then
    SABRE="$(abs_path "$4")"
else
    SABRE="$4"
fi

ADAPTER="AGATCGGAA"
SNPEFF_DB="Glycine_max"

# Dossiers de sortie toujours créés à la racine du projet (en dehors de Script/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DIR="${PROJECT_DIR}/output"
DEMUX_DIR="${OUTPUT_DIR}/demux"
TRIMMED_DIR="${OUTPUT_DIR}/trimmed"
SAM_DIR="${OUTPUT_DIR}/sam"
BAM_DIR="${OUTPUT_DIR}/bam"

RESULTS_DIR="${PROJECT_DIR}/results"
QC_RAW_DIR="${RESULTS_DIR}/fastqc_raw"
QC_TRIM_DIR="${RESULTS_DIR}/fastqc_trimmed"

# Créer l'arborescence output/ (intermédiaires) et results/ (résultats importants)
mkdir -p "${DEMUX_DIR}" "${TRIMMED_DIR}" "${SAM_DIR}" "${BAM_DIR}" "${QC_RAW_DIR}" "${QC_TRIM_DIR}"

# 1. Contrôle de qualité sur les lectures brutes
echo "=============================================="
echo "1. Contrôle de qualité sur les lectures brutes"
fastqc -t "$CPU" --outdir "${QC_RAW_DIR}" "$FASTQ"

# 2. Démultiplexage des codes-barres (fichiers .fq rangés dans output/demux/)
echo "=============================================="
echo "2. Démultiplexage des codes-barres"
(
    cd "${DEMUX_DIR}"
    "$SABRE" se -f "$FASTQ" -b "$BARCODES" -u "${OUTPUT_DIR}/unknown.fq"
)

# 3. Coupure des adaptateurs et filtrage des lectures courtes ou de faible qualité
echo "=============================================="
echo "3. Coupure des adaptateurs et filtrage (Cutadapt)"
for file in "${DEMUX_DIR}"/*.fq; do
    sample="$(basename "$file" .fq)"
    cutadapt -j "$CPU" -a "$ADAPTER" -q 20 -m 50 -o "${TRIMMED_DIR}/${sample}.fastq" "$file"
done

# 4. Contrôle de qualité après découpage
echo "=============================================="
echo "4. Contrôle de qualité sur les lectures sans adaptateur"
fastqc -t "$CPU" --outdir "${QC_TRIM_DIR}" "${TRIMMED_DIR}"/*.fastq

# 5. Indexation du génome de référence (si absente) et alignement des lectures (BWA)
echo "=============================================="
echo "5. Indexation du génome de référence et alignement des lectures"
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

echo "=============================================="
echo "Mapping des lectures"
for file in "${TRIMMED_DIR}"/*.fastq; do
    sample="$(basename "$file" .fastq)"
    bwa mem -t "$CPU" "$REF" "$file" > "${SAM_DIR}/${sample}.sam"
done

# 6. Conversion SAM vers BAM, tri et indexation (SAMtools)
echo "=============================================="
echo "6. Conversion SAM vers BAM, tri et indexation"
for file in "${SAM_DIR}"/*.sam; do
    sample="$(basename "$file" .sam)"
    samtools view -@ "$CPU" -bS "$file" -o "${BAM_DIR}/${sample}.bam"
    samtools sort -@ "$CPU" "${BAM_DIR}/${sample}.bam" -o "${BAM_DIR}/${sample}.sort.bam"
    samtools index "${BAM_DIR}/${sample}.sort.bam"
done

# 7. Appel de variants (BCFtools)
echo "=============================================="
echo "7. Appel de variants (BCFtools)"
bcftools mpileup -Ob -f "$REF" -o "${OUTPUT_DIR}/variants.bcf" "${BAM_DIR}"/*.sort.bam
bcftools call -mv -Ov -o "${RESULTS_DIR}/variants.vcf" "${OUTPUT_DIR}/variants.bcf"

# 8. Annotation des variants (SnpEff - Bonus)
echo "=============================================="
echo "8. Annotation des variants (SnpEff)"
snpEff download "$SNPEFF_DB"
snpEff -stats "${RESULTS_DIR}/snpeff.html" "$SNPEFF_DB" "${RESULTS_DIR}/variants.vcf" > "${RESULTS_DIR}/variants.ann.vcf"

echo "=============================================="
echo "Terminé !"
echo "  Fichiers intermédiaires : ${OUTPUT_DIR}"
echo "  Résultats importants    : ${RESULTS_DIR}"
