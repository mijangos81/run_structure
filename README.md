# Running STRUCTURE

This folder runs [STRUCTURE](https://web.stanford.edu/group/pritchardlab/structure.html)
(Pritchard et al.) for a range of K values, with several replicates each, in
parallel on a single computer. It works on macOS, Linux, and Windows (via Git
Bash). No installation is needed — the STRUCTURE binaries are included.

## What's in this folder

| File | Purpose |
|------|---------|
| `run_structure.sh` | The launcher. Runs all K × replicate jobs in parallel. |
| `mainparams` | STRUCTURE model/MCMC settings (burn-in, ploidy, data layout). |
| `extraparams` | STRUCTURE advanced model settings (admixture, alpha priors). |
| `*.str` | Your input data in STRUCTURE format (no header row). |
| `structure` | STRUCTURE binary for macOS / Linux. |
| `structure.exe` | STRUCTURE binary for Windows (Git Bash). |

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
| `BASESEED` | clock time | Set a fixed number to reproduce a previous run exactly. |
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

## Using your own data

To run a different dataset, just **drop your own STRUCTURE-format `.str` file
into this folder** (and remove or keep the existing one — if there is exactly
one `.str` file it is picked up automatically; otherwise set `INFILE`).

- The script reads the **number of individuals** and **number of loci**
  directly from your file and fills them into STRUCTURE for you — you do **not**
  need to edit `NUMINDS` / `NUMLOCI` by hand.
- It assumes the default layout in `mainparams`: **two rows per individual**
  (`ONEROWPERIND 0`), with **2 leading columns** (an individual label + a
  population code), and **no header row**.
- If your file uses a different layout, edit `mainparams` (e.g. set
  `ONEROWPERIND 1`, `LABEL`, `POPDATA`, `EXTRACOLS`) — the script honours those
  settings when computing the dimensions. You can also override the auto-derived
  values directly, e.g. `NUMINDS=300 NUMLOCI=5000 ./run_structure.sh 8`, or set
  `HEADERROWS=1` if your file has a marker-name header row.

Edit `mainparams` / `extraparams` to change the model and MCMC settings
(burn-in length, number of reps, admixture model, etc.).

## Output

Results go to `output_str/` (one set of files per K × replicate), named:

```
output_str/K<K>_rep<REP>_seed<SEED>_f      # the main STRUCTURE results file
```

Per-job console logs (stdout/stderr) go to `logs_structure/`. The script also
writes `output_str/mainparams.used`, the exact config used for the run.

These `*_f` files are the input for downstream analysis — Evanno ΔK / best-K
selection and plotting (e.g. with the `dartRverse` R packages, CLUMPAK, or
STRUCTURE Harvester).

## Notes

- STRUCTURE is single-threaded per run; parallelism here comes from running many
  K × replicate jobs at once. Don't set the core count higher than your machine
  has.
- Each replicate uses a different seed (`BASESEED + task number`), so replicates
  are independent. Fix `BASESEED` to reproduce a whole run.
- Runtime depends mostly on `BURNIN` + `NUMREPS` (in `mainparams`), the number
  of loci, and how many jobs run concurrently.
