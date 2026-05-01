#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
app_dir <- if (length(args) >= 1) args[[1]] else "."

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", repos = "https://cloud.r-project.org")
}

rsconnect::writeManifest(
  appDir = app_dir,
  appPrimaryDoc = "app.R"
)

cat("Wrote manifest.json in:", normalizePath(app_dir), "\n")
