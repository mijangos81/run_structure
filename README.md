# Running STRUCTURE

This folder runs [STRUCTURE](https://web.stanford.edu/group/pritchardlab/structure.html)
(Pritchard et al.) for a range of K values, with several replicates each, in
parallel on a single computer. It works on macOS, Linux, and Windows (via Git
Bash). STRUCTURE itself is not included: download it once before the first run
(see *Installing STRUCTURE*).

A bundled example input (`platypus.str`, generated from `platypus.gl`, the
platypus test dataset in the `dartR.data` R package — 81 individuals, 1000 SNPs,
3 populations) lets you run it immediately.

## What's in this folder

| File | Purpose |
|------|---------|
| `run_structure.sh` | The launcher. Runs all K × replicate jobs in parallel. |
| `mainparams` | STRUCTURE model/MCMC settings (burn-in, ploidy, data layout). |
| `extraparams` | STRUCTURE advanced model settings (admixture, alpha priors). |
| `*.str` | Input data in STRUCTURE format (the bundled example is `platypus.str`). |
| `scripts/prepare_structure_input.R` | Builds a `.str` from a VCF / DArT report / genlight via dartRverse. |
| `run_structure.slurm` | SLURM array-job script for running on an HPC cluster. |
| `structure` / `structure.exe` | The STRUCTURE program. Not included: you download it (see below). |

## Installing STRUCTURE

STRUCTURE is not redistributed here. Download version 2.3.4 from the
[Pritchard lab download page](https://web.stanford.edu/group/pritchardlab/structure_software/release_versions/v2.3.4/html/structure.html).
Under **"Download package without front end"**, pick your system. Do not use
the packages under "Download package with graphical front end": those are the
point-and-click version, and this toolkit runs the command-line program.

| Your system | Package (without front end) | Program to copy |
|-------------|-----------------------------|-----------------|
| macOS | Mac OS X (Intel processor) · `structure_mac_console.tar.gz` | `console/structure` |
| Linux, WSL, HPC cluster | Linux · `structure_linux_console.tar.gz` | `console/structure` |
| Windows (Git Bash) | DOS/Windows · `structure_windows_console.zip` | `console/structure.exe` |

Unpack the package and copy **only the program** into this folder. The package
also contains its own `mainparams` and `extraparams`; don't copy those, because
they would replace this toolkit's settings. On macOS or Linux:

```bash
tar -xzf structure_mac_console.tar.gz      # or structure_linux_console.tar.gz
cp console/structure .
chmod +x structure
```

On Windows, unzip `structure_windows_console.zip` and copy `console/structure.exe`
into this folder. To keep the program somewhere else, skip the copy and set
`STRUCTURE_BIN=/path/to/structure` when you run the script.

If the program won't start:

- **macOS says the developer cannot be verified:** run
  `xattr -d com.apple.quarantine structure`.
- **Apple Silicon Mac, "Bad CPU type in executable":** the program is an Intel
  build and needs Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`.
- **Linux, "No such file or directory" although the file is there:** the Linux
  build is 32-bit and the machine lacks 32-bit system libraries. Build STRUCTURE
  from the C source on the same download page (unpack it and run `make`), or use
  your cluster's module if it has one.

## How to run it

1. Open a terminal:
   - **macOS:** Terminal
   - **Linux:** any shell
   - **Windows:** Git Bash (install from https://git-scm.com/) — or WSL
2. `cd` into this folder, e.g.:
   ```bash
   cd run_structure
   ```
3. Run it. For example, **K = 1–8, 10 replicates, using 8 cores**:
   ```bash
   N_K=8 N_REP=10 ./run_structure.sh 8
   ```
   The number after the script (`8`) is how many jobs run at once — set it to
   roughly the number of CPU cores on your machine.

If you get a **"permission denied"** error, make the script (and binary)
executable, then try again:
```bash
chmod +x run_structure.sh structure
```

## Options

All options are set as environment variables before the command. Defaults shown.

| Variable | Default | Meaning |
|----------|---------|---------|
| (1st argument) | `8` | Max jobs to run at once (≈ number of cores). |
| `N_K` | `8` | Run K = 1 … `N_K`. |
| `N_REP` | `10` | Replicates per K. |
| `BASESEED` | clock time | Set a fixed number to reproduce a previous run exactly (see *Seeds*). |
| `INFILE` | the `.str` in this folder | Path to the input file (only needed if you have several). |
| `OUTBASE` | `./output_str` | Where result files are written. |
| `LOGDIR` | `./logs_structure` | Where per-job logs are written. |

Examples:
```bash
# Quick test: K=1..3, 2 reps, 4 cores
N_K=3 N_REP=2 ./run_structure.sh 4

# Reproducible run with a fixed seed
N_K=8 N_REP=10 BASESEED=12345 ./run_structure.sh 8
```

## Seeds and reproducibility

STRUCTURE's MCMC is stochastic, so a run is only reproducible if you control the
seed. This toolkit handles seeds at two levels:

- **STRUCTURE run seed.** The script picks a `BASESEED` (the clock time by
  default) and gives task *t* the seed `BASESEED + t` (passed to STRUCTURE via
  `-D`). Every K × replicate therefore gets a distinct, deterministic seed.
- **`RANDOMIZE` is forced to 0.** STRUCTURE uses the `-D` seed only when
  `RANDOMIZE` is 0. With `RANDOMIZE 1`, its default, it takes the seed from the
  system clock and ignores `-D`, so replicates started in the same second run
  identical chains (same seed, same LnP) and the seed in the file name is not the
  one used. The script deletes any `RANDOMIZE` line from your `mainparams` and
  `extraparams` and passes STRUCTURE copies with `RANDOMIZE 0`
  (`output_str/extraparams.used`). Check the `SEED=` value in a `_f` file: it
  should match the seed in its name.
- **It records the seed.** At the start of each run the chosen `BASESEED` is
  written to `output_str/seed.txt`. To reproduce an entire run later, pass that
  value back in:
  ```bash
  BASESEED=$(cat output_str/seed.txt) N_K=8 N_REP=10 ./run_structure.sh 8
  ```
  Same `BASESEED` + same input + same `mainparams`/`extraparams` ⇒ identical
  results.
- **Input-prep seed.** If you build your `.str` with the R script, it calls
  `set.seed()` so any stochastic QC step (random tie-breaking, sub-sampling) is
  also reproducible. This is independent of STRUCTURE's run seed.

## Preparing an input file (your own data)

You have two options.

**A. Drop in a ready-made `.str`.** Put a STRUCTURE-format file in this folder.
If there is exactly one `.str` it is picked up automatically; otherwise set
`INFILE=/path/to/file.str`.

**B. Build one from a VCF or DArT report** with dartRverse. Edit and run the
example script (requires R with `dartRverse` / `dartR.base` installed):
```bash
Rscript scripts/prepare_structure_input.R
```
It shows how to load data with `gl.read.vcf()` or `gl.read.dart()` and exports
to STRUCTURE format with `gl2structure()`. As shipped it uses the `platypus.gl`
example and writes `platypus.str` to this folder, ready to run.

**The script reads the number of individuals and loci directly from your file**
and fills `NUMINDS` / `NUMLOCI` into STRUCTURE for you — you never edit them by
hand. It honours the data-layout flags in `mainparams` when doing so:

- The defaults match `gl2structure()` output: a **marker-name header row**
  (`MARKERNAMES 1`), **two rows per individual** (`ONEROWPERIND 0`), and **two
  leading columns** (individual label + population code; `LABEL 1`, `POPDATA 1`).
- For a different layout, edit `mainparams` (`ONEROWPERIND`, `MARKERNAMES`,
  `LABEL`, `POPDATA`, `EXTRACOLS`, …) — the script recomputes the dimensions
  from those flags. You can also override directly, e.g.
  `NUMINDS=300 NUMLOCI=5000 ./run_structure.sh 8`, or force the number of header
  rows with `HEADERROWS=1`.

Edit `mainparams` / `extraparams` to change the model and MCMC settings
(burn-in length, number of reps, admixture model, etc.).

## Output

Results go to `output_str/` (one set of files per K × replicate), named:

```
output_str/K<K>_rep<REP>_seed<SEED>_f      # the main STRUCTURE results file
```

Per-job console logs (stdout/stderr) go to `logs_structure/`. The script also
writes `output_str/mainparams.used` (the exact config used) and
`output_str/seed.txt` (the `BASESEED` for reproducing the run).

These `*_f` files are the input for downstream analysis — Evanno ΔK / best-K
selection and plotting (e.g. with the `dartRverse` R packages, CLUMPAK, or
STRUCTURE Harvester).

## Running on an HPC cluster

For a full K × replicate sweep, a cluster is far faster — every (K, replicate)
job is independent, so they can run as a **SLURM array** with one job per task.
`run_structure.slurm` does this by calling `run_structure.sh` in single-task
mode (`TASK_ID=$SLURM_ARRAY_TASK_ID`), so all the input auto-detection, dimension
derivation and seeding are shared with the local runner.

**Before submitting:**

1. **Provide a Linux STRUCTURE program.** Download the Linux package without
   front end (see *Installing STRUCTURE*) and copy `console/structure` into the
   project folder on the cluster, or `module load` STRUCTURE if your cluster
   provides it and set `STRUCTURE_BIN` in `run_structure.slurm`. The Linux build
   is 32-bit; if it won't start, build it from the C source.
2. **Prepare the input** (`platypus.str`, or your own `.str` / the R script).
3. **Edit `run_structure.slurm`** — set `--partition` / `--account` for your
   cluster, and keep the three sweep settings consistent:
   - `#SBATCH --array=1-<N_K*N_REP>`  (e.g. `1-80` for `N_K=8`, `N_REP=10`)
   - `export N_K=...` and `export N_REP=...`

**Submit:**

```bash
mkdir -p logs_structure        # SLURM needs the log dir to exist
sbatch run_structure.slurm
```

Each array task writes its result to `output_str/K<K>_rep<REP>_seed<SEED>_f` and
its SLURM logs to `logs_structure/`. All tasks share one base seed
(`BASESEED=$SLURM_ARRAY_JOB_ID`) so each task's seed (`BASESEED + task`) is stable
and the whole run is reproducible — re-submit with the same `BASESEED` to repeat
it. STRUCTURE is single-threaded, so the script requests 1 CPU per task and pins
the math libraries to one thread; scale throughput with the array size, not CPUs
per task.

> Single fat node instead of an array? Just run the local command inside one job:
> `./run_structure.sh $SLURM_CPUS_PER_TASK` with a high `--cpus-per-task`.

## Notes

- STRUCTURE is single-threaded per run; parallelism here comes from running many
  K × replicate jobs at once. Don't set the core count higher than your machine
  has.
- Each replicate uses a different seed (`BASESEED + task number`), so replicates
  are independent. Fix `BASESEED` to reproduce a whole run.
- Runtime depends mostly on `BURNIN` + `NUMREPS` (in `mainparams`), the number
  of loci, and how many jobs run concurrently.

## Citing

Results produced with this toolkit come from STRUCTURE, so cite STRUCTURE. The
bundled `extraparams` runs the admixture model with correlated allele
frequencies (`FREQSCORR 1`), which needs both of these:

- Pritchard, J. K., Stephens, M., & Donnelly, P. (2000). Inference of population
  structure using multilocus genotype data. *Genetics*, 155(2), 945–959.
  https://doi.org/10.1093/genetics/155.2.945
- Falush, D., Stephens, M., & Pritchard, J. K. (2003). Inference of population
  structure using multilocus genotype data: linked loci and correlated allele
  frequencies. *Genetics*, 164(4), 1567–1587.
  https://doi.org/10.1093/genetics/164.4.1567

If you switch on another model (for example `LOCPRIOR`, or dominant markers via
`RECESSIVEALLELES`), the STRUCTURE manual lists the paper to cite for it. If you
built your input with `scripts/prepare_structure_input.R`, also cite dartR: run
`citation("dartR.base")` in R for the references.
