#!/bin/bash
# run_structure.slurm — run STRUCTURE as a SLURM array job (one task per K×rep).
#
# Each array task runs exactly one (K, replicate) STRUCTURE job, reusing all the
# dimension/seed logic in run_structure.sh via TASK_ID. Submit from the project
# folder:  sbatch run_structure.slurm
#
# IMPORTANT: the --array range MUST equal N_K * N_REP (set below). For N_K=8,
# N_REP=10 that is 1-80.

#SBATCH --job-name=structure
#SBATCH --array=1-80
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=12:00:00
#SBATCH --output=logs_structure/slurm.%x.%A_%a.out
#SBATCH --error=logs_structure/slurm.%x.%A_%a.err
## --- adapt these to your cluster, then uncomment ---
## #SBATCH --partition=<your-partition>
## #SBATCH --account=<your-account>

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-.}"
mkdir -p logs_structure

# --- sweep size: keep in sync with the --array range above (N_K * N_REP) ---
export N_K=8
export N_REP=10

# All array tasks must share ONE base seed, otherwise each task would pick its
# own clock-based seed. Tie it to the array job id so per-(K,rep) seeds are
# stable and the whole run is reproducible (re-submit with the same value).
export BASESEED="${SLURM_ARRAY_JOB_ID}"

# STRUCTURE is not bundled. Use the Linux package "without front end" from the
# STRUCTURE 2.3.4 download page (README, "Installing STRUCTURE"): copy
# console/structure into this folder, or point STRUCTURE_BIN at it. That build is
# 32-bit; if it won't start on your cluster, build it from the C source or
# `module load` it.
# export STRUCTURE_BIN=/path/to/linux/structure
## module load structure        # if your cluster provides it

# STRUCTURE is single-threaded; stop math libraries grabbing extra cores.
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1

# Run just this array task.
TASK_ID="${SLURM_ARRAY_TASK_ID}" ./run_structure.sh
