#' Install R packages required for the Census BDS Shiny app.
#' Run once: Rscript install_deps.R (or in R: source("install_deps.R"))

pkgs = c(
  "shiny", "bslib", "DT", "httr", "jsonlite",
  "dplyr", "purrr", "readr", "tidyr", "ggplot2",
  "lubridate", "glue"
)

missing = pkgs[!sapply(pkgs, function(p) requireNamespace(p, quietly = TRUE))]
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
  message("Installed: ", paste(missing, collapse = ", "))
} else {
  message("All required packages are already installed.")
}
