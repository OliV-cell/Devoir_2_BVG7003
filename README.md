# Automated Variant Calling Pipeline

## 1. Objective & Functionality
This repository contains an automated Bash pipeline (`Script/Pipeline.sh`) that processes raw single-end sequencing data (FASTQ) into a functionally annotated Variant Call Format (VCF) file. It is designed to be reproducible, flexible across different datasets, and easy to run using relative paths.

The pipeline executes the following steps in order:
1. **Raw Quality Control (`FastQC`):** Evaluates base quality, GC content, adapter content, and overrepresented sequences in raw reads.
2. **Demultiplexing (`Sabre`):** Splits pooled sequencing reads into individual sample `.fq` files using a barcode file.
3. **Trimming & Filtering (`Cutadapt`):** Removes adapter sequences (`AGATCGGAA`), trims low-quality 3' bases (`-q 20`), and discards reads shorter than 50 bp (`-m 50`).
4. **Post-Trimming Quality Control (`FastQC`):** Re-evaluates read quality after trimming to verify adapter removal and quality improvement.
5. **Reference Alignment (`BWA`):** Indexes the reference genome (`bwa index`) and aligns trimmed reads (`bwa mem`) to produce SAM files.
6. **BAM Post-Processing (`SAMtools`):** Converts SAM to BAM, sorts alignments by genomic coordinates, and indexes the sorted BAM files.
7. **Variant Calling (`BCFtools`):** Computes genotype likelihoods (`bcftools mpileup`) and calls SNPs and indels (`bcftools call -mv`) to generate a VCF file.
8. **Functional Annotation (`SnpEff` - Bonus):** Downloads the specified genome database and annotates called variants with predicted functional effects.

> **Note on PCR duplicates:** Duplicate removal is intentionally omitted because this workflow is tailored for GBS (Genotyping-by-Sequencing) data, where reads originating from the same restriction enzyme cut site naturally share identical start coordinates.

---

## 2. Repository Structure
```text
.
├── Script/
│   └── Pipeline.sh      # Main automated variant calling script
├── Tools/
│   └── Tools_installation.md # Tool & Sabre installation instructions
├── input_data/
│   └── GBS_data/        # Input files (FASTQ, barcodes)
├── README.md            # Project documentation and usage guide
└── results/             # Output directory (created automatically when run)
```

---

## 3. Input and Output Formats

### Required Inputs
* **Raw sequencing reads (`.fq.gz` or `.fastq.gz`):** Single-end raw FASTQ file.
* **Reference genome (`.fa` or `.fasta`):** Reference genome sequence.
* **Barcodes file (`.txt`):** Tab-delimited file mapping sample barcodes to output `.fq` filenames (standard `sabre se` format).

### Generated Outputs (in `results/`)
| File(s) | Tool | Description |
|---|---|---|
| `*_fastqc.html`, `*_fastqc.zip` | FastQC | Quality reports before and after trimming |
| `unknown.fq` | Sabre | Reads whose barcodes did not match any sample |
| `*.fastq` | Cutadapt | Adapter-trimmed and quality-filtered reads |
| `*.sam` | BWA | Raw sequence alignments |
| `*.bam`, `*.sort.bam`, `*.sort.bam.bai` | SAMtools | Binary, coordinate-sorted, and indexed alignments |
| `variants.bcf` | BCFtools | Binary call format file from `mpileup` |
| `variants.vcf` | BCFtools | Final called SNPs and indels |
| `variants.ann.vcf`, `snpeff.html` | SnpEff | Annotated VCF and HTML summary report |

---

## 4. Dependencies and Installation

All bioinformatics tools are managed inside a single Conda environment named **`devoir_2`**:
* `fastqc`
* `sabre`
* `cutadapt`
* `bwa`
* `samtools`
* `bcftools`
* `snpeff`

### Installation Steps
1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. **Create the `devoir_2` Conda environment (and build `sabre` if on Apple Silicon):**
   See `Tools/Tools_installation.md` for full details:
   ```bash
   conda create -n devoir_2 -c conda-forge -c bioconda \
       fastqc cutadapt bwa samtools bcftools snpeff parallel
   ```

3. **Make the pipeline script executable:**
   ```bash
   chmod +x Script/Pipeline.sh
   ```

---

## 5. How to Run the Pipeline

Run the script from the root of the repository using **relative paths** for your three input files (an optional 4th argument can specify a custom path to `sabre` if not in `devoir_2` or `Tools/sabre/sabre`):

```bash
./Script/Pipeline.sh <path/to/reads.fq.gz> <path/to/reference.fa> <path/to/barcodes.txt> [path/to/sabre]
```

### Example (Test Dataset)
```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz path/to/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt
```

CPU thread allocation is automatically set to one-third of detected system cores (minimum `1`).

### Adapting to Another Dataset
To run the pipeline on a different organism or sequencing kit:
* Pass your new FASTQ, reference FASTA, and barcode files as the three command-line arguments.
* If your dataset uses a different adapter sequence or organism database, update the `ADAPTER` and `SNPEFF_DB` variables at the top of `Script/Pipeline.sh`.

---

## 6. Log Files and Troubleshooting

### Capturing Execution Logs
The script uses `set -euo pipefail`, meaning it will **stop immediately** if any command fails so that corrupted files are not passed to downstream steps. To save a complete record of both standard output and error messages to a log file (`pipeline.log`), run the script with `tee`:

```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz path/to/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt 2>&1 | tee pipeline.log
```

### Quick Troubleshooting
* **Conda environment error:** Verify that the environment exists and is named exactly `devoir_2` by running `conda env list`.
* **Sabre not found:** Build `sabre` in `Tools/sabre` (see `Tools/Tools_installation.md`) or pass its binary path as the 4th argument.
* **SnpEff command not found:** The script automatically checks both `snpEff` and `snpeff` in the `devoir_2` environment.
* **Empty VCF file:** Check alignment rates using `conda run -n devoir_2 samtools flagstat results/<sample>.sort.bam` to confirm reads mapped to the reference genome.
