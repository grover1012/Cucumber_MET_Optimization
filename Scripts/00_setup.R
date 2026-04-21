# 00_setup.R
# Load packages and create folder structure

required_pkgs <- c(
  "dplyr", "tidyr", "readr", "stringr", "ggplot2", "ggrepel",
  "ggalluvial", "caret", "olsrr", "MASS", "car", "sommer",
  "pheatmap", "factoextra", "EnvRtype", "tibble"
)

install_if_missing <- function(pkgs) {
  for (p in pkgs) {
    if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
  }
}
install_if_missing(required_pkgs)
invisible(lapply(required_pkgs, library, character.only = TRUE))

dirs <- c("Data/raw", "Data/processed", "Output/tables", "Output/models",
          "Output/intermediate", "Figures", "R", "Scripts")
invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))

source("R/functions.R")
message("Setup complete.")
