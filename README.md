# Pipeline automatisé d'appel de variants

## 1. Objectif et fonctionnement
Ce dépôt contient un pipeline Bash automatisé (`Script/Pipeline.sh`) qui transforme des données brutes de séquençage simple brin (*single-end*, FASTQ) en un fichier VCF (*Variant Call Format*) annoté fonctionnellement. Il est conçu pour être reproductible, adaptable à différents jeux de données et simple à exécuter à l'aide de chemins relatifs.

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
├── Script/
│   └── Pipeline.sh           # Script principal automatisé d'appel de variants
├── Tools/
│   └── Tools_installation.md # Instructions d'installation des outils et de Sabre
├── input_data/
│   └── GBS_data/             # Fichiers d'entrée (FASTQ, codes-barres)
├── output/                   # Fichiers intermédiaires (créé automatiquement)
│   ├── demux/                # Fichiers .fq démultiplexés
│   ├── trimmed/              # Fichiers .fastq nettoyés par Cutadapt
│   ├── sam/                  # Alignements bruts BWA (.sam)
│   └── bam/                  # Fichiers .bam convertis, triés et indexés
├── results/                  # Résultats finaux (créé automatiquement)
│   ├── fastqc_raw/           # Rapports FastQC sur les lectures brutes
│   └── fastqc_trimmed/       # Rapports FastQC sur les lectures nettoyées
├── README.md                 # Documentation du projet et guide d'utilisation
└── pipeline.log              # Exemple de fichier journal (log) d'exécution
```

---

## 3. Formats d'entrée et de sortie

### Entrées requises
- **Lectures de séquençage brutes (`.fq.gz` ou `.fastq.gz`) :** fichier FASTQ brut *single-end*.
- **Génome de référence (`.fa` ou `.fasta`) :** séquence du génome de référence.
- **Fichier de codes-barres (`.txt`) :** fichier délimité par des tabulations associant chaque code-barres au nom du fichier `.fq` de sortie (format standard `sabre se`).

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

2. **Créer l'environnement Conda `devoir_2` (et compiler `sabre` si vous êtes sur Mac Apple Silicon) :**
   Consultez `Tools/Tools_installation.md` pour tous les détails :
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

Lancez le script depuis la racine du dépôt en utilisant des **chemins relatifs** pour vos fichiers d'entrée :

```bash
./Script/Pipeline.sh <chemin/vers/lectures.fq.gz> <chemin/vers/reference.fa> <chemin/vers/barcodes.txt> <chemin/vers/sabre> [adaptateur] [base_snpeff]
```

| Argument | Variable | Description | Valeur par défaut |
|---|---|---|---|
| `$1` | `FASTQ` | Fichier de lectures brutes (`.fq.gz` / `.fastq.gz`) | *(obligatoire)* |
| `$2` | `REF` | Génome de référence (`.fa` / `.fasta`) | *(obligatoire)* |
| `$3` | `BARCODES` | Fichier de codes-barres (`.txt`) | *(obligatoire)* |
| `$4` | `SABRE` | Chemin vers l'exécutable `sabre` (ou `sabre` s'il est dans le `$PATH`) | *(obligatoire)* |
| `$5` | `ADAPTER` | Séquence de l'adaptateur à couper (ici **adaptateur Illumina** `AGATCGGAA`, modifiable au besoin selon le kit de séquençage) | `AGATCGGAA` |
| `$6` | `SNPEFF_DB` | Nom de la base de données génomique SnpEff (modifiable selon l'organisme étudié) | `Glycine_max` |

### Exemple (jeu de données de test)
```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz chemin/vers/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt Tools/sabre/sabre AGATCGGAA Glycine_max
```

*(Les arguments `$5` et `$6` sont optionnels : s'ils sont omis, le script utilise automatiquement l'adaptateur **Illumina** `AGATCGGAA` et la base SnpEff `Glycine_max`.)*

L'allocation des cœurs CPU est réglée automatiquement à la **moitié des cœurs détectés sur la machine** (`NB_CPU / 2`, minimum `1`).

### Adapter à un autre jeu de données
Pour exécuter le pipeline sur un autre organisme ou un autre kit de séquençage :
- Passez vos nouveaux fichiers FASTQ (`$1`), FASTA de référence (`$2`) et codes-barres (`$3`) en arguments.
- Si votre jeu de données n'utilise pas l'adaptateur **Illumina** (`AGATCGGAA`) ou porte sur un autre organisme que le soja (`Glycine_max`), fournissez simplement la nouvelle séquence d'adaptateur en **`$5`** et le nom de la base SnpEff correspondante en **`$6`** directement dans la commande initiale.

---

## 6. Fichiers journaux (logs) et dépannage

### Enregistrer les journaux d'exécution
Le script utilise `set -euo pipefail`, ce qui signifie qu'il **s'arrête immédiatement** dès qu'une commande échoue afin d'éviter de transmettre des fichiers corrompus aux étapes suivantes. Pour sauvegarder l'ensemble de la sortie standard et des messages d'erreur dans un fichier journal (`pipeline.log`), exécutez le script avec `tee` :

```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz chemin/vers/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt Tools/sabre/sabre AGATCGGAA Glycine_max 2>&1 | tee pipeline.log
```

### Dépannage rapide
- **Erreur d'environnement Conda :** vérifiez que l'environnement existe et s'appelle exactement `devoir_2` avec `conda env list`.
- **Sabre introuvable :** compilez `sabre` dans `Tools/sabre` (voir `Tools/Tools_installation.md`) et passez `Tools/sabre/sabre` en 4e argument.
- **Commande SnpEff introuvable :** `Pipeline.sh` appelle `snpEff` (avec un `E` majuscule). Selon votre version Conda, l'exécutable peut être en minuscules (`snpeff`) ; vérifiez avec `conda run -n devoir_2 which snpEff snpeff`.
- **Fichier VCF vide :** vérifiez les taux d'alignement avec `conda run -n devoir_2 samtools flagstat output/bam/<echantillon>.sort.bam` pour confirmer que les lectures se sont alignées sur le génome de référence.

Pour les descriptions étape par étape, les avertissements attendus et le dépannage détaillé, consultez le **Wiki** du dépôt.
