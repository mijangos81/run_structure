#!/usr/bin/env Rscript
# prepare_structure_input.R
#
# Build a STRUCTURE-format input file (.str) from a genlight object using
# dartRverse's gl2structure(). Run it from the project root so the output
# lands where run_structure.sh can auto-detect it:
#
#     Rscript scripts/prepare_structure_input.R
#
# This worked example uses the bundled `platypus.gl` dataset. To use your own
# data, load it with one of the readers below instead (see the commented block).

# dartRverse is the maintained successor to dartR. Load the meta-package, or
# just the base sub-package which provides the readers and gl2structure().
suppressMessages({
  library(dartRverse)      # or: library(dartR.base)
})

# --- Reproducibility -------------------------------------------------------
# Several dartRverse steps (random tie-breaking in filters, gl.subsample,
# any resampling) are stochastic. Set a seed so the prepared input - and any
# filtering you add below - is reproducible. This is separate from STRUCTURE's
# own MCMC seed, which run_structure.sh sets per run (see output_str/seed.txt).
set.seed(42)

# --- 1. Load your data -----------------------------------------------------
# Pick the reader that matches your source, then (optionally) QC-filter.
# Both return a genlight object, the input gl2structure() expects.
#
# From a VCF:
#   gl <- gl.read.vcf("path/to/your_data.vcf")
#
# From a DArT report (SNP CSV + individual metadata):
#   gl <- gl.read.dart(
#     filename     = "path/to/Report_DArT_SNP.csv",
#     ind.metafile = "path/to/individual_metadata.csv"
#   )
#
# Example QC you might apply before exporting (optional):
#   gl <- gl.filter.callrate(gl, threshold = 0.95)
#   gl <- gl.filter.maf(gl, threshold = 0.05)

# For this example we use the bundled platypus dataset (81 inds, 1000 SNPs,
# 3 populations) instead of an external file.
data(platypus.gl, package = "dartR.data", envir = environment())
gl <- platypus.gl

cat(sprintf("genlight: %d individuals, %d loci, %d populations\n",
            nInd(gl), nLoc(gl), nPop(gl)))

# --- 2. Export to STRUCTURE format ----------------------------------------
# gl2structure() writes two rows per individual (diploid), a marker-name header
# row, and the individual label as the first column. We pass the population as
# an extra column (add.columns) so STRUCTURE has a predefined population code -
# this matches POPDATA 1 / LABEL 1 / MARKERNAMES 1 in mainparams.
outfile <- "platypus.str"
gl2structure(
  gl,
  add.columns         = as.integer(pop(gl)),  # population code column
  export.marker.names = TRUE,                 # marker-name header row
  ploidy              = 2,
  outfile             = outfile,
  outpath             = ".",                   # project root (run from there)
  verbose             = 1
)

cat(sprintf("Wrote %s - now run:  N_K=8 N_REP=10 ./run_structure.sh 8\n", outfile))
