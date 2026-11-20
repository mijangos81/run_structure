#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run_structure.sh
#
# Run STRUCTURE (Pritchard et al.) for K = 1..N_K, with N_REP replicates each,
# in parallel on a single machine (macOS / Linux / Windows Git Bash).
#
# Quick start (from inside this folder):
#
#     N_K=8 N_REP=10 ./run_structure.sh 8        # K=1..8, 10 reps, 8 cores
#
# The script auto-detects the input .str file and fills NUMINDS / NUMLOCI for
# you, so to run it on a different dataset you only need to drop your own .str
# file in this folder (and review the model settings in `mainparams` /
# `extraparams`). See README.md for full details.
###############################################################################

###############################################################################
# Settings (all overridable from the environment)
###############################################################################
CORES="${1:-8}"                 # max concurrent STRUCTURE jobs
N_K="${N_K:-8}"                 # K values to run: 1..N_K
N_REP="${N_REP:-10}"            # replicates per K: 1..N_REP

OUTBASE="${OUTBASE:-./output_str}"       # all STRUCTURE outputs go here
LOGDIR="${LOGDIR:-./logs_structure}"     # per-task stdout/stderr logs go here

# Reproducibility: set BASESEED manually to reproduce a previous run exactly.
# By default it is derived from the wall clock, so each run is different.
BASESEED="${BASESEED:-$(date +%s)}"

# STRUCTURE config files (edit these for the model / MCMC settings).
MAINPARAMS="${MAINPARAMS:-./mainparams}"
EXTRAPARAMS="${EXTRAPARAMS:-./extraparams}"

###############################################################################
# Locate the input .str file
###############################################################################
# Priority: INFILE from the environment -> the single *.str file in this folder.
if [[ -z "${INFILE:-}" ]]; then
  shopt -s nullglob
  STR_FILES=( ./*.str )
  shopt -u nullglob
  if (( ${#STR_FILES[@]} == 1 )); then
    INFILE="${STR_FILES[0]}"
  elif (( ${#STR_FILES[@]} == 0 )); then
    echo "ERROR: no .str input file found in this folder." >&2
    echo "       Put your STRUCTURE input here, or set INFILE=/path/to/file.str" >&2
    exit 1
  else
    echo "ERROR: multiple .str files found; set INFILE to choose one:" >&2
    printf '       %s\n' "${STR_FILES[@]}" >&2
    exit 1
  fi
fi

if [[ ! -f "$INFILE" ]]; then
  echo "ERROR: input file not found: $INFILE" >&2
  exit 1
fi

###############################################################################
# OS detection -> default STRUCTURE binary
###############################################################################
# If STRUCTURE_BIN is already set in the environment, keep it.
if [[ -z "${STRUCTURE_BIN:-}" ]]; then
  UNAME_S="$(uname -s 2>/dev/null || echo unknown)"
  case "$UNAME_S" in
    MINGW*|MSYS*|CYGWIN*) STRUCTURE_BIN="./structure.exe" ;;  # Git Bash / MSYS / Cygwin
    *)                   STRUCTURE_BIN="./structure" ;;      # macOS / Linux / WSL
  esac
fi

###############################################################################
# Read the data layout from mainparams (so derivation honours your settings)
###############################################################################
# Pull an integer #define value out of mainparams (ignores trailing // comments).
get_def() {
  local key="$1" def="$2" val
  val="$(grep -E "^#define[[:space:]]+${key}[[:space:]]" "$MAINPARAMS" 2>/dev/null | awk '{print $3}' | head -n1)"
  [[ -n "$val" ]] && echo "$val" || echo "$def"
}

ONEROWPERIND="$(get_def ONEROWPERIND 0)"
LABEL="$(get_def LABEL 1)"
POPDATA="$(get_def POPDATA 1)"
POPFLAG="$(get_def POPFLAG 0)"
LOCDATA="$(get_def LOCDATA 0)"
PHENOTYPE="$(get_def PHENOTYPE 0)"
EXTRACOLS="$(get_def EXTRACOLS 0)"

# Number of leading (non-genotype) columns in each data row.
LEADCOLS="${LEADCOLS:-$(( LABEL + POPDATA + POPFLAG + LOCDATA + PHENOTYPE + EXTRACOLS ))}"

# Header rows before the data: STRUCTURE adds one row each for marker names,
# recessive alleles and map distances. gl2structure writes a marker-name row,
# so MARKERNAMES 1 -> one header row to skip. Overridable via HEADERROWS.
MARKERNAMES="$(get_def MARKERNAMES 0)"
RECESSIVEALLELES="$(get_def RECESSIVEALLELES 0)"
MAPDISTANCES="$(get_def MAPDISTANCES 0)"
HEADERROWS="${HEADERROWS:-$(( MARKERNAMES + RECESSIVEALLELES + MAPDISTANCES ))}"

###############################################################################
# Derive NUMINDS / NUMLOCI from the input file (unless overridden)
###############################################################################
NROWS="$(grep -c '' "$INFILE")"          # counts lines even without trailing \n
DATAROWS=$(( NROWS - HEADERROWS ))
# Column count from the first DATA row (skip header rows): a marker-name header
# has no leading columns, so counting it would undercount NUMLOCI.
NCOLS="$(awk -v skip="$HEADERROWS" 'NR>skip && NF{print NF; exit}' "$INFILE")"

if [[ -z "${NUMINDS:-}" ]]; then
  if [[ "$ONEROWPERIND" -eq 1 ]]; then
    NUMINDS="$DATAROWS"
  else
    NUMINDS=$(( DATAROWS / 2 ))
  fi
fi

if [[ -z "${NUMLOCI:-}" ]]; then
  NUMLOCI=$(( NCOLS - LEADCOLS ))
fi

if (( NUMINDS <= 0 || NUMLOCI <= 0 )); then
  echo "ERROR: derived NUMINDS=$NUMINDS NUMLOCI=$NUMLOCI from $INFILE." >&2
  echo "       Check ONEROWPERIND / leading-column settings, or set NUMINDS / NUMLOCI." >&2
  exit 1
fi

###############################################################################
# Setup
###############################################################################
mkdir -p "$OUTBASE" "$LOGDIR"

if [[ ! -x "$STRUCTURE_BIN" ]]; then
  echo "ERROR: STRUCTURE binary not found or not executable: $STRUCTURE_BIN" >&2
  echo "       On macOS/Linux try: chmod +x structure" >&2
  exit 1
fi

for f in "$MAINPARAMS" "$EXTRAPARAMS"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: config file not found: $f" >&2
    exit 1
  fi
done

# Single-task mode: if TASK_ID is set (e.g. from an HPC array job), run exactly
# that one task instead of the local parallel loop. See run_structure.slurm.
TASK_ID="${TASK_ID:-}"

# Build the mainparams actually used for this run: a copy of the template with
# INFILE / NUMINDS / NUMLOCI / MAXPOPS filled in from the data. The committed
# `mainparams` is left untouched so it stays a clean, editable template. In
# single-task mode each task writes its own copy to avoid clobbering each other.
if [[ -n "$TASK_ID" ]]; then
  RUN_MAINPARAMS="${OUTBASE}/mainparams.used.task${TASK_ID}"
  RUN_EXTRAPARAMS="${OUTBASE}/extraparams.used.task${TASK_ID}"
else
  RUN_MAINPARAMS="${OUTBASE}/mainparams.used"
  RUN_EXTRAPARAMS="${OUTBASE}/extraparams.used"
fi
# STRUCTURE uses the -D seed only when RANDOMIZE is 0. With RANDOMIZE 1, its default,
# it seeds from the system clock and ignores -D, so tasks started in the same second
# run identical chains and BASESEED cannot reproduce a run. RANDOMIZE is therefore
# removed from both configs and set to 0 in the extraparams copy passed to STRUCTURE.
sed -E \
  -e "s|^#define[[:space:]]+INFILE[[:space:]]+.*$|#define INFILE ${INFILE}|" \
  -e "s|^#define[[:space:]]+NUMINDS[[:space:]]+.*$|#define NUMINDS ${NUMINDS}|" \
  -e "s|^#define[[:space:]]+NUMLOCI[[:space:]]+.*$|#define NUMLOCI ${NUMLOCI}|" \
  -e "s|^#define[[:space:]]+MAXPOPS[[:space:]]+.*$|#define MAXPOPS ${N_K}|" \
  -e "/^#define[[:space:]]+RANDOMIZE([[:space:]]|$)/d" \
  "$MAINPARAMS" > "$RUN_MAINPARAMS"
{ grep -Ev "^#define[[:space:]]+RANDOMIZE([[:space:]]|$)" "$EXTRAPARAMS" || true; printf '\n#define RANDOMIZE 0\n'; } > "$RUN_EXTRAPARAMS"

TOTAL_TASKS=$(( N_K * N_REP ))

echo "Running STRUCTURE with up to ${CORES} concurrent workers"
echo "INFILE:        $INFILE"
echo "NUMINDS:       $NUMINDS"
echo "NUMLOCI:       $NUMLOCI"
echo "N_K:           $N_K   (K = 1..${N_K})"
echo "N_REP:         $N_REP"
echo "TOTAL_TASKS:   $TOTAL_TASKS"
echo "STRUCTURE_BIN: $STRUCTURE_BIN"
echo "OUTBASE:       $OUTBASE"
echo "LOGDIR:        $LOGDIR"
echo "BASESEED:      $BASESEED   (RANDOMIZE forced to 0 so task t uses BASESEED + t)"
echo "Start:         $(date)"
echo

# Record the seed so the run is reproducible. STRUCTURE's MCMC is stochastic;
# each task gets SEED = BASESEED + task (passed via -D). To repeat this exact
# run later, re-run with the BASESEED saved here, e.g.:
#     BASESEED=$(cat output_str/seed.txt) N_K=8 N_REP=10 ./run_structure.sh 8
# In single-task (array) mode, all tasks share one BASESEED (set it in the job
# script, e.g. to the array job id) so don't let them race on the same file.
if [[ -z "$TASK_ID" ]]; then
  echo "$BASESEED" > "${OUTBASE}/seed.txt"
  echo "Recorded BASESEED to ${OUTBASE}/seed.txt (use it to reproduce this run)."
  echo
fi

run_task() {
  local TASK="$1"
  local K REP SEED OUTPREFIX OUTLOG ERRLOG

  # Map TASK (1..TOTAL_TASKS) -> K (1..N_K) and REP (1..N_REP)
  K=$(( ((TASK - 1) % N_K) + 1 ))
  REP=$(( ((TASK - 1) / N_K) + 1 ))

  SEED=$(( BASESEED + TASK ))

  # Unique output prefix per run, all under OUTBASE
  OUTPREFIX="${OUTBASE}/K${K}_rep${REP}_seed${SEED}"

  OUTLOG="${LOGDIR}/structure.K${K}.rep${REP}.task${TASK}.out"
  ERRLOG="${LOGDIR}/structure.K${K}.rep${REP}.task${TASK}.err"

  echo "Task=${TASK}/${TOTAL_TASKS}  K=${K}  REP=${REP}  SEED=${SEED}"

  "$STRUCTURE_BIN" -m "$RUN_MAINPARAMS" -e "$RUN_EXTRAPARAMS" \
    -K "$K" -o "$OUTPREFIX" -D "$SEED" \
    >"$OUTLOG" 2>"$ERRLOG"
}

# Single-task mode (HPC array job): run just this task and exit.
if [[ -n "$TASK_ID" ]]; then
  if (( TASK_ID < 1 || TASK_ID > TOTAL_TASKS )); then
    echo "ERROR: TASK_ID=$TASK_ID out of range 1..$TOTAL_TASKS (= N_K*N_REP)." >&2
    exit 1
  fi
  run_task "$TASK_ID"
  rm -f "$RUN_MAINPARAMS" "$RUN_EXTRAPARAMS"   # per-task copies no longer needed
  echo "Task ${TASK_ID} finished. End: $(date)"
  exit 0
fi

# Local mode: run all tasks, up to CORES at a time.
max_jobs="$CORES"

for TASK in $(seq 1 "$TOTAL_TASKS"); do
  while (( $(jobs -rp | wc -l) >= max_jobs )); do
    sleep 0.2
  done
  run_task "$TASK" &
done

wait

echo
echo "All jobs finished."
echo "End: $(date)"

echo "Result files created in ${OUTBASE}:"
find "$OUTBASE" -maxdepth 1 -type f -name 'K*_rep*_f' | wc -l
