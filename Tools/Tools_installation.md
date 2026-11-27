
# Commande d'installation des outils

Afin d'installer les outils, on recommande fortement de tout mettre dans un seul et même environnement virtuel Conda, facilitant ainsi la gestion des dépendances et l'exécution des scripts.

Lancez donc ces commandes dans votre terminal :

```bash
conda create -n devoir_2 -c conda-forge -c bioconda fastqc cutadapt bwa samtools bcftools snpeff parallel
conda activate devoir_2
```

Toutefois, **Sabre** doit être installé manuellement (non disponible pour toutes les architectures sur Bioconda, notamment `osx-arm64`).
Une fois l'environnement `devoir_2` activé, lancez les commandes suivantes depuis la racine du projet :

```bash
cd Tools
git clone https://github.com/najoshi/sabre.git
cd sabre
make
cp sabre "$CONDA_PREFIX/bin/"
sabre --help
```

Ou suivez les instructions du dépôt officiel : [Sabre](https://github.com/najoshi/sabre).