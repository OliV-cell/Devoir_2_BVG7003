# Pipeline automatisé d'appel de variants

## 1. Objective & Functionality
This repository contains an automated Bash pipeline (`Script/Pipeline.sh`) that processes raw single-end sequencing data (FASTQ) into a functionally annotated Variant Call Format (VCF) file. It is designed to be reproducible, flexible across different datasets, and easy to run using relative paths.

Le pipeline exécute les étapes suivantes dans l'ordre :
1. **Contrôle de qualité brut (`FastQC`) :** évalue la qualité des bases, le contenu en GC, la présence d'adaptateurs et les séquences surreprésentées sur les lectures brutes.
2. **Démultiplexage (`Sabre`) :** sépare les lectures regroupées en fichiers `.fq` individuels par échantillon à partir d'un fichier de codes-barres.
3. **Découpage et filtrage (`Cutadapt`) :** retire les séquences d'adaptateurs Illumina (`AGATCGGAA` par défaut, modifiable via `$5`), rogne les bases de faible qualité en 3' (`-q 20`) et élimine les lectures de moins de 50 pb (`-m 50`).
4. **Contrôle de qualité après découpage (`FastQC`) :** réévalue la qualité des lectures nettoyées pour vérifier le retrait des adaptateurs et l'amélioration de la qualité.
5. **Alignement sur le génome de référence (`BWA`) :** indexe le génome de référence (`bwa index`, s'il ne l'est pas déjà) et aligne les lectures filtrées (`bwa mem`) pour produire des fichiers SAM.
6. **Post-traitement BAM (`SAMtools`) :** convertit les fichiers SAM en BAM, trie les alignements par coordonnées génomiques et indexe les fichiers BAM triés.
7. **Appel de variants (`BCFtools`) :** calcule les vraisemblances de génotypes (`bcftools mpileup`) et appelle les SNP et indels (`bcftools call -mv`) afin de générer un fichier VCF.
8. **Annotation fonctionnelle (`SnpEff` — Bonus) :** télécharge la base de données génomique spécifiée et annote les variants appelés avec leurs effets fonctionnels prédits.

> **Note sur les duplicats PCR :** le retrait des duplicats est volontairement omis car ce pipeline est conçu pour des données GBS (*Genotyping-by-Sequencing*), où les lectures issues d'un même site de coupure d'enzyme de restriction partagent naturellement les mêmes coordonnées de départ.

---

## 2. Structure du dépôt
```text
.
├── LICENSE                   # GNU GPL v3 license
├── README.md                 # Project documentation and usage guide
├── Wiki.md                   # Step-by-step documentation & troubleshooting
├── Script/
│   └── Pipeline.sh           # Script principal automatisé d'appel de variants
├── Tools/
│   └── Tools_installation.md # Instructions d'installation des outils et de Sabre
├── input_data/
│   └── GBS_data/             # Input files (FASTQ, barcodes)
├── output/                   # Intermediate files (created automatically when run)
│   ├── demux/                # Demultiplexed .fq files
│   ├── trimmed/              # Cutadapt-trimmed .fastq files
│   ├── sam/                  # Raw BWA .sam alignments
│   └── bam/                  # Converted, sorted, and indexed .bam files
├── results/                  # Final outputs (created automatically when run)
│   ├── fastqc_raw/           # FastQC reports on raw reads
│   └── fastqc_trimmed/       # FastQC reports on trimmed reads
├── README.md                 # Project documentation and usage guide
└── pipeline.log              # Example execution log
```

---

## 3. Formats d'entrée et de sortie

### Required Inputs
- **Raw sequencing reads (`.fq.gz` or `.fastq.gz`):** Single-end raw FASTQ file.
- **Reference genome (`.fa` or `.fasta`):** Reference genome sequence.
- **Barcodes file (`.txt`):** Tab-delimited file mapping sample barcodes to output `.fq` filenames (standard `sabre se` format).

### Fichiers générés

**Résultats finaux (dans `results/`) :**
| Fichier(s) | Outil | Description |
|---|---|---|
| `fastqc_raw/*_fastqc.html`, `.zip` | FastQC | Rapports de qualité sur les lectures brutes |
| `fastqc_trimmed/*_fastqc.html`, `.zip` | FastQC | Rapports de qualité sur les lectures nettoyées |
| `variants.vcf` | BCFtools | Fichier final des SNP et indels appelés |
| `variants.ann.vcf`, `snpeff.html` | SnpEff | Fichier VCF annoté et rapport récapitulatif HTML |

**Fichiers intermédiaires (dans `output/`) :**
| Fichier(s) | Outil | Description |
|---|---|---|
| `demux/*.fq`, `unknown.fq` | Sabre | Lectures démultiplexées par échantillon et lectures non reconnues |
| `trimmed/*.fastq` | Cutadapt | Lectures sans adaptateurs et filtrées par qualité |
| `sam/*.sam` | BWA | Alignements bruts des séquences |
| `bam/*.bam`, `*.sort.bam`, `*.sort.bam.bai` | SAMtools | Alignements binaires, triés par coordonnées et indexés |
| `variants.bcf` | BCFtools | Fichier binaire issu de `mpileup` |

---

## 4. Dépendances et installation

Tous les outils bioinformatiques sont gérés dans un seul environnement Conda nommé **`devoir_2`** :
- `fastqc`
- `sabre`
- `cutadapt`
- `bwa`
- `samtools`
- `bcftools`
- `snpeff`

### Étapes d'installation
1. **Cloner le dépôt :**
   ```bash
   git clone <url-du-depot>
   cd <nom-du-depot>
   ```

2. **Create the `devoir_2` Conda environment (and build `sabre` if on Apple Silicon):**
   See `Tools/Tools_installation.md` for full details:
   ```bash
   conda create -n devoir_2 -c conda-forge -c bioconda \
       fastqc cutadapt bwa samtools bcftools snpeff parallel
   ```

3. **Rendre le script exécutable :**
   ```bash
   chmod +x Script/Pipeline.sh
   ```

---

## 5. Exécution du pipeline

Run the script from the root of the repository using **relative paths** for your input files (pass a 4th argument if `sabre` is not in your `$PATH`):

```bash
./Script/Pipeline.sh <path/to/reads.fq.gz> <path/to/reference.fa> <path/to/barcodes.txt> [path/to/sabre]
```

### Example (Test Dataset)
```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz chemin/vers/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt Tools/sabre/sabre AGATCGGAA Glycine_max
```

*(Les arguments `$5` et `$6` sont optionnels : s'ils sont omis, le script utilise automatiquement l'adaptateur **Illumina** `AGATCGGAA` et la base SnpEff `Glycine_max`.)*

L'allocation des cœurs CPU est réglée automatiquement à la **moitié des cœurs détectés sur la machine** (`NB_CPU / 2`, minimum `1`).

### Adapting to Another Dataset
To run the pipeline on a different organism or sequencing kit:
- Pass your new FASTQ, reference FASTA, and barcode files as the command-line arguments.
- If your dataset uses a different adapter sequence or organism database, update the `ADAPTER` and `SNPEFF_DB` variables at the top of `Script/Pipeline.sh`.

---

## 6. Log Files and Troubleshooting

### Capturing Execution Logs
The script uses `set -euo pipefail`, meaning it will **stop immediately** if any command fails so that corrupted files are not passed to downstream steps. To save a complete record of both standard output and error messages to a log file (`pipeline.log`), run the script with `tee`:

```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz chemin/vers/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt Tools/sabre/sabre AGATCGGAA Glycine_max 2>&1 | tee pipeline.log
```

### Quick Troubleshooting
- **Conda environment error:** Verify that the environment exists and is named exactly `devoir_2` by running `conda env list`.
- **Sabre not found:** Build `sabre` in `Tools/sabre` (see `Tools/Tools_installation.md`) and pass `Tools/sabre/sabre` as the 4th argument.
- **SnpEff command not found:** `Pipeline.sh` calls `snpEff` (capital `E`). Depending on your Conda build, the binary may be lowercase (`snpeff`); check with `conda run -n devoir_2 which snpEff snpeff`.
- **Empty VCF file:** Check alignment rates using `conda run -n devoir_2 samtools flagstat output/bam/<sample>.sort.bam` to confirm reads mapped to the reference genome.

For step-by-step descriptions, expected warnings, and detailed troubleshooting, see the repository **Wiki**.
