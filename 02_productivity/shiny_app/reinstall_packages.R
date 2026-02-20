# Reinstall packages in your current R version to remove
# "was built under R version 4.5.2" warnings.
# Run in R (from project root): source("02_productivity/shiny_app/reinstall_packages.R")
# Or from shiny_app: source("reinstall_packages.R")

pkgs = c("purrr", "readr", "tidyr", "ggplot2")
# type = "source" rebuilds for your R version (may need Rtools on Windows, Xcode CLT on Mac).
install.packages(pkgs, type = "source")
message("Done. Restart R and run the app again to see if warnings are gone.")
