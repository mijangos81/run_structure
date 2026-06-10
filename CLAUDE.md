# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A portable, dataset-agnostic toolkit to run Pritchard's **STRUCTURE** for a K × replicate sweep on a single machine (macOS / Linux / Windows Git Bash). The whole tool is the Bash launcher `run_structure.sh` plus STRUCTURE's two config files; the STRUCTURE binaries are committed so no installation is needed. This is a standalone CLI tool, not an R/dartRverse analysis project (the empty `articles/`, `data/`, `scripts/`, etc. folders come from the project skeleton and are unused by the tool itself).

## Running it

From the repo root (the tool expects to run from the folder containing the `.str` file and binaries):

```bash
N_K=8 N_REP=10 ./run_structure.sh 8     # K=1..8, 10 reps, up to 8 concurrent jobs
N_K=3 N_REP=2 ./run_structure.sh 4      # quick test
```

The first positional argument is the max number of concurrent jobs (≈ CPU cores). If you get "permission denied": `chmod +x run_structure.sh structure`.

To smoke-test changes without waiting for full MCMC (BURNIN 50000 + NUMREPS 100000 is slow even at K=1), point `MAINPARAMS` at a copy with shrunk values, e.g.:

```bash
sed -E 's/^#define BURNIN .*/#define BURNIN 200/; s/^#define NUMREPS .*/#define NUMREPS 400/' mainparams > /tmp/mp.fast
MAINPARAMS=/tmp/mp.fast OUTBASE=./output_test LOGDIR=./logs_test N_K=2 N_REP=1 ./run_structure.sh 2
```

Each run writes `output_str/K<K>_rep<REP>_seed<SEED>_f` (the STRUCTURE result file used for downstream Evanno/ΔK + plotting), per-job logs to `logs_structure/`, and `output_str/mainparams.used` (the exact config used). `output_*/` and `logs_*/` are run artifacts, not source.

## How the generalisation works (the key design)

`run_structure.sh` is what makes this dataset-agnostic — understand this before editing it:

1. **Input auto-detection** — uses the single `*.str` file in the folder, or `INFILE=/path/to/file.str`.
2. **Dimension derivation** — reads the data layout from `mainparams` (via `get_def`) and computes:
   - `NUMINDS = data_rows / (ONEROWPERIND ? 1 : 2)`
   - `NUMLOCI = ncols − (LABEL + POPDATA + POPFLAG + LOCDATA + PHENOTYPE + EXTRACOLS)`
   - Both honour env overrides (`NUMINDS`, `NUMLOCI`, `LEADCOLS`, `HEADERROWS`).
3. **Non-destructive runtime config** — generates `output_str/mainparams.used` from the committed `mainparams` template with INFILE/NUMINDS/NUMLOCI/MAXPOPS substituted, and passes it to STRUCTURE via `-m` (with `-e extraparams`). The committed `mainparams` is never mutated — keep it that way.
4. **OS detection** — selects `./structure` (macOS/Linux/WSL) or `./structure.exe` (Git Bash/MSYS/Cygwin), overridable via `STRUCTURE_BIN`.
5. Per-task seed is `BASESEED + task`; set `BASESEED` to reproduce a whole run.

Invariant to preserve: `mainparams` stays a clean, human-editable template (model/MCMC settings); all data-specific values are filled in at runtime. STRUCTURE echoes `NUMINDS`/`NUMLOCI`/`DATAFILE` into each `_f` file — use that to verify ingestion after changes.

## Config files

- `mainparams` — data layout + MCMC settings. INFILE/NUMINDS/NUMLOCI are auto-filled (placeholders only); everything else (PLOIDY, MISSING, ONEROWPERIND, BURNIN, NUMREPS, the leading-column flags) is meant to be edited per dataset.
- `extraparams` — STRUCTURE's admixture/alpha-prior model settings.

When adapting to a new dataset, the user normally only drops in a new `.str`; only edit `mainparams` if the data layout differs (e.g. `ONEROWPERIND 1`, extra columns) — the derivation reads those flags.
