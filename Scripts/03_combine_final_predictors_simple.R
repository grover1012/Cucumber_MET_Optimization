###############################################
# Combine final predictors from the multi-year
# and multi-location workflows
#
# Main steps:
# 1. Read final predictor files from MYT and MLT
# 2. Standardize predictor names
# 3. Compare overlap between predictor sets
# 4. Create combined predictor tables
# 5. Create optional frequency tables
# 6. Save outputs for downstream analyses
#
# Notes:
# - This script assumes that the previous two scripts
#   have already been run successfully.
# - It does not re-run weather extraction or model fitting.
# - It is intended to produce the final predictor list
#   used in later clustering, ERM, and present/future
#   comparison analyses.
###############################################

############################
# 0. Clean environment
############################
rm(list = ls())
gc()

############################
# 1. Load required packages
############################
library(dplyr)
library(readr)
library(stringr)
library(tidyr)

############################
# 2. Set file paths and output folder
############################

# Set your project working directory if needed
# setwd("PATH/TO/YOUR/PROJECT")

myt_file <- "Data/processed/selected_EC_MYT.csv"
mlt_file <- "Data/processed/selected_EC_MLT.csv"

output_dir <- "Outputs/Final_predictors"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

############################
# 3. Read predictor files
############################

cat("Reading final predictor files...\n")

if (!file.exists(myt_file)) {
  stop("MYT final predictor file not found:\n", myt_file)
}

if (!file.exists(mlt_file)) {
  stop("MLT final predictor file not found:\n", mlt_file)
}

myt_pred <- read_csv(myt_file, show_col_types = FALSE)
mlt_pred <- read_csv(mlt_file, show_col_types = FALSE)

############################
# 4. Check required columns
############################

if (!("predictor" %in% names(myt_pred))) {
  stop("Column 'predictor' not found in MYT final predictor file.")
}

if (!("predictor" %in% names(mlt_pred))) {
  stop("Column 'predictor' not found in MLT final predictor file.")
}

############################
# 5. Standardize predictor tables
############################

cat("Standardizing predictor names...\n")

myt_pred <- myt_pred %>%
  transmute(
    predictor = str_trim(as.character(predictor)),
    source    = "MYT"
  ) %>%
  filter(!is.na(predictor), predictor != "")

mlt_pred <- mlt_pred %>%
  transmute(
    predictor = str_trim(as.character(predictor)),
    source    = "MLT"
  ) %>%
  filter(!is.na(predictor), predictor != "")

write.csv(myt_pred,
          file.path(output_dir, "MYT_final_predictors_clean.csv"),
          row.names = FALSE)

write.csv(mlt_pred,
          file.path(output_dir, "MLT_final_predictors_clean.csv"),
          row.names = FALSE)

############################
# 6. Create predictor sets
############################

cat("Creating predictor sets...\n")

myt_set <- sort(unique(myt_pred$predictor))
mlt_set <- sort(unique(mlt_pred$predictor))

common_predictors <- intersect(myt_set, mlt_set)
myt_only_predictors <- setdiff(myt_set, mlt_set)
mlt_only_predictors <- setdiff(mlt_set, myt_set)
union_predictors <- sort(unique(c(myt_set, mlt_set)))

############################
# 7. Save simple predictor lists
############################

cat("Saving simple predictor lists...\n")

write.csv(
  data.frame(predictor = common_predictors),
  file.path(output_dir, "common_predictors_MYT_MLT.csv"),
  row.names = FALSE
)

write.csv(
  data.frame(predictor = myt_only_predictors),
  file.path(output_dir, "MYT_only_predictors.csv"),
  row.names = FALSE
)

write.csv(
  data.frame(predictor = mlt_only_predictors),
  file.path(output_dir, "MLT_only_predictors.csv"),
  row.names = FALSE
)

write.csv(
  data.frame(predictor = union_predictors),
  file.path(output_dir, "union_predictors_MYT_MLT.csv"),
  row.names = FALSE
)

############################
# 8. Create comparison table
############################

cat("Creating comparison table...\n")

comparison_table <- data.frame(
  predictor = union_predictors,
  in_MYT    = union_predictors %in% myt_set,
  in_MLT    = union_predictors %in% mlt_set,
  stringsAsFactors = FALSE
) %>%
  mutate(
    category = case_when(
      in_MYT & in_MLT ~ "Common to MYT and MLT",
      in_MYT & !in_MLT ~ "MYT only",
      !in_MYT & in_MLT ~ "MLT only",
      TRUE ~ "Other"
    )
  )

write.csv(
  comparison_table,
  file.path(output_dir, "predictor_comparison_table_MYT_MLT.csv"),
  row.names = FALSE
)

############################
# 9. Create frequency table
############################

cat("Creating frequency table...\n")

all_pred_long <- bind_rows(myt_pred, mlt_pred)

predictor_frequency <- all_pred_long %>%
  count(predictor, name = "n_sources") %>%
  arrange(desc(n_sources), predictor)

write.csv(
  predictor_frequency,
  file.path(output_dir, "predictor_frequency_table.csv"),
  row.names = FALSE
)

############################
# 10. Create final candidate predictor tables
############################

cat("Creating final candidate predictor tables...\n")

# Table A: strict shared predictors only
final_predictors_shared <- data.frame(
  predictor = common_predictors,
  selection_rule = "Selected in both MYT and MLT",
  stringsAsFactors = FALSE
)

# Table B: union of all predictors from both workflows
final_predictors_union <- data.frame(
  predictor = union_predictors,
  selection_rule = "Selected in at least one of MYT or MLT",
  stringsAsFactors = FALSE
)

# Table C: prioritized table with overlap information
final_predictors_priority <- comparison_table %>%
  mutate(
    priority = case_when(
      category == "Common to MYT and MLT" ~ 1,
      category == "MYT only" ~ 2,
      category == "MLT only" ~ 3,
      TRUE ~ 4
    )
  ) %>%
  arrange(priority, predictor)

write.csv(
  final_predictors_shared,
  file.path(output_dir, "final_predictors_shared_only.csv"),
  row.names = FALSE
)

write.csv(
  final_predictors_union,
  file.path(output_dir, "final_predictors_union.csv"),
  row.names = FALSE
)

write.csv(
  final_predictors_priority,
  file.path(output_dir, "final_predictors_priority_table.csv"),
  row.names = FALSE
)

############################
# 11. Optional final choice for downstream analyses
############################

cat("Creating downstream-ready final predictor file...\n")

# Default choice:
# Use the union so that no potentially important predictor is lost.
# If you want a stricter set, replace this with common_predictors.
final_predictors_for_downstream <- final_predictors_union

write.csv(
  final_predictors_for_downstream,
  file.path(output_dir, "final_predictors_for_downstream_analysis.csv"),
  row.names = FALSE
)

############################
# 12. Create summary text output
############################

cat("Writing summary report...\n")

summary_lines <- c(
  "Final predictor combination summary",
  "----------------------------------",
  paste("Number of MYT predictors:", length(myt_set)),
  paste("Number of MLT predictors:", length(mlt_set)),
  paste("Number of common predictors:", length(common_predictors)),
  paste("Number of MYT-only predictors:", length(myt_only_predictors)),
  paste("Number of MLT-only predictors:", length(mlt_only_predictors)),
  paste("Number of union predictors:", length(union_predictors)),
  "",
  "Files created:",
  "- common_predictors_MYT_MLT.csv",
  "- MYT_only_predictors.csv",
  "- MLT_only_predictors.csv",
  "- union_predictors_MYT_MLT.csv",
  "- predictor_comparison_table_MYT_MLT.csv",
  "- predictor_frequency_table.csv",
  "- final_predictors_shared_only.csv",
  "- final_predictors_union.csv",
  "- final_predictors_priority_table.csv",
  "- final_predictors_for_downstream_analysis.csv"
)

writeLines(
  summary_lines,
  con = file.path(output_dir, "final_predictor_summary.txt")
)

############################
# 13. Save R objects
############################

cat("Saving R workspace objects...\n")

save(
  myt_pred,
  mlt_pred,
  myt_set,
  mlt_set,
  common_predictors,
  myt_only_predictors,
  mlt_only_predictors,
  union_predictors,
  comparison_table,
  predictor_frequency,
  final_predictors_shared,
  final_predictors_union,
  final_predictors_priority,
  final_predictors_for_downstream,
  file = file.path(output_dir, "final_predictor_objects.RData")
)

############################
# 14. Final message
############################

cat("--------------------------------------------------\n")
cat("Final predictor combination workflow completed successfully.\n")
cat("Outputs saved in:", output_dir, "\n")
cat("--------------------------------------------------\n")
