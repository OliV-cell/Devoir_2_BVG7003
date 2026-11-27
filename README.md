# Automated Variant Calling Pipeline

## 1. Objective & Functionality
This repository contains an automated Bash pipeline ([`Script/Pipeline.sh`](Script/Pipeline.sh)) that processes raw single-end sequencing data (FASTQ) into a functionally annotated Variant Call Format (VCF) file. It is designed to be reproducible, adaptable across datasets, and easy to run using relative paths.

The pipeline executes the following steps in order:
1. **Raw Quality Control (`FastQC`):** Evaluates base quality, GC content, adapter content, and overrepresented sequences in raw reads.
2. **Demultiplexing (`Sabre`):** Splits pooled sequencing reads into individual sample `.fq` files using a barcode file.
3. **Trimming & Filtering (`Cutadapt`):** Removes adapter sequences (`AGATCGGAA`), trims low-quality 3' bases (`-q 20`), and discards reads shorter than 50 bp (`-m 50`).
4. **Post-Trimming Quality Control (`FastQC`):** Re-evaluates read quality after trimming to verify adapter removal and quality improvement.
5. **Reference Alignment (`BWA`):** Indexes the reference genome (`bwa index`, if not already indexed) and aligns trimmed reads (`bwa mem`) to produce SAM files.
6. **BAM Post-Processing (`SAMtools`):** Converts SAM to BAM, sorts alignments by genomic coordinates, and indexes the sorted BAM files.
7. **Variant Calling (`BCFtools`):** Computes genotype likelihoods (`bcftools mpileup`) and calls SNPs and indels (`bcftools call -mv`) to generate a VCF file.
8. **Functional Annotation (`SnpEff` - Bonus):** Downloads the specified genome database and annotates called variants with predicted functional effects.

> **Note on PCR duplicates:** Duplicate removal is intentionally omitted because this workflow is tailored for GBS (Genotyping-by-Sequencing) data, where reads originating from the same restriction enzyme cut site naturally share identical start coordinates.

---

## 2. Repository Structure
```text
.
├── LICENSE                   # GNU GPL v3 license
├── README.md                 # Project documentation and usage guide
├── Wiki.md                   # Step-by-step documentation & troubleshooting
├── Script/
│   └── Pipeline.sh           # Main automated variant calling script
├── Tools/
│   └── Tools_installation.md # Tool & Sabre installation instructions
├── input_data/
│   └── GBS_data/             # Example input files (FASTQ, barcodes)
├── output/                   # Intermediate files (created automatically when run)
│   ├── demux/                # Demultiplexed .fq files
│   ├── trimmed/              # Cutadapt-trimmed .fastq files
│   ├── sam/                  # Raw BWA .sam alignments
│   └── bam/                  # Converted, sorted, and indexed .bam files
├── results/                  # Final outputs (created automatically when run)
│   ├── fastqc_raw/           # FastQC reports on raw reads
│   ├── fastqc_trimmed/       # FastQC reports on trimmed reads
│   ├── variants.vcf          # Called SNPs and indels
│   ├── variants.ann.vcf      # SnpEff-annotated variants
│   └── snpeff.html           # SnpEff summary report
└── pipeline.log              # Execution log (when captured with tee)
```

---

## 3. Input and Output Formats

### Required Inputs
- **Raw sequencing reads (`.fq.gz` or `.fastq.gz`):** Single-end raw FASTQ file (`$1`).
- **Reference genome (`.fa` or `.fasta`):** Reference genome sequence (`$2`).
- **Barcodes file (`.txt`):** Whitespace-delimited (tab or space) file mapping sample barcodes to output `.fq` filenames in standard `sabre se` format (`$3`).
- **Sabre executable (`$4`):** Command name (`sabre` if on your `$PATH`) or relative path to the compiled `sabre` binary (e.g., `Tools/sabre/sabre`).

### Generated Outputs

**Final results (in `results/`):**
| File(s) | Tool | Description |
|---|---|---|
| `fastqc_raw/*_fastqc.html`, `.zip` | FastQC | Quality reports on raw reads |
| `fastqc_trimmed/*_fastqc.html`, `.zip` | FastQC | Quality reports on trimmed reads |
| `variants.vcf` | BCFtools | Final called SNPs and indels |
| `variants.ann.vcf`, `snpeff.html` | SnpEff | Annotated VCF and HTML summary report |

**Intermediate files (in `output/`):**
| File(s) | Tool | Description |
|---|---|---|
| `demux/*.fq`, `unknown.fq` | Sabre | Demultiplexed sample reads and unmatched reads |
| `trimmed/*.fastq` | Cutadapt | Adapter-trimmed and quality-filtered reads |
| `sam/*.sam` | BWA | Raw sequence alignments |
| `bam/*.bam`, `*.sort.bam`, `*.sort.bam.bai` | SAMtools | Binary, coordinate-sorted, and indexed alignments |
| `variants.bcf` | BCFtools | Binary call format file from `mpileup` |

---

## 4. Dependencies and Installation

All bioinformatics tools are managed inside a single Conda environment named **`devoir_2`**:
- `fastqc`
- `sabre`
- `cutadapt`
- `bwa`
- `samtools`
- `bcftools`
- `snpeff`

### Installation Steps
1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. **Create the `devoir_2` Conda environment (and build `sabre` from source if needed):**
   See [`Tools/Tools_installation.md`](Tools/Tools_installation.md) for full details:
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

Run the script from the root of the repository using **relative paths** for all 4 arguments (pass `sabre` as the 4th argument if it is already in your `devoir_2` `$PATH`, or `Tools/sabre/sabre` if built locally):

```bash
./Script/Pipeline.sh <path/to/reads.fq.gz> <path/to/reference.fa> <path/to/barcodes.txt> <sabre_or_path>
```

### Example (Test Dataset)
```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz path/to/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt Tools/sabre/sabre
```

CPU thread allocation is automatically set to **half of detected system cores** (`NB_CPU / 2`, minimum `1`).

### Adapting to Another Dataset
To run the pipeline on a different organism or sequencing kit:
- Pass your new FASTQ, reference FASTA, barcode file, and `sabre` command/path as the 4 command-line arguments.
- If your dataset uses a different adapter sequence or organism database, update the `ADAPTER` and `SNPEFF_DB` variables in [`Script/Pipeline.sh`](Script/Pipeline.sh).

---

## 6. Log Files and Troubleshooting

### Capturing Execution Logs
The script uses `set -euo pipefail`, meaning it will **stop immediately** if any command fails so that corrupted files are not passed to downstream steps. To save a complete record of both standard output and error messages to `pipeline.log`, run the script with `tee`:

```bash
./Script/Pipeline.sh input_data/GBS_data/FC20150701_1.fq.gz path/to/Gmax_275_v2.0.fa input_data/GBS_data/FC20150701_1.txt Tools/sabre/sabre 2>&1 | tee pipeline.log
```

### Quick Troubleshooting
- **Conda environment error:** Verify that the environment exists and is named exactly `devoir_2` (`conda env list`), and ensure `conda` is initialized in your shell before running.
- **`$4: unbound variable`:** All 4 arguments are required because `set -u` is enabled — pass `sabre` (or `Tools/sabre/sabre`) as the 4th argument.
- **Sabre not found:** Build `sabre` in `Tools/sabre` (see [`Tools/Tools_installation.md`](Tools/Tools_installation.md)) and pass `Tools/sabre/sabre` as the 4th argument.
- **SnpEff command not found:** `Pipeline.sh` calls `snpEff` (capital `E`). Depending on your Conda build, the binary may be lowercase (`snpeff`); check with `conda run -n devoir_2 which snpEff snpeff`.
- **Empty VCF file:** Check alignment rates using `conda run -n devoir_2 samtools flagstat output/bam/<sample>.sort.bam` to confirm reads mapped to the reference genome.

For step-by-step descriptions, expected warnings, and detailed troubleshooting, see [`Wiki.md`](Wiki.md) and the repository **Wiki**.
