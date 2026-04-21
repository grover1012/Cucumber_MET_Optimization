# 02_prepare_environmental_covariates.R
# Prepare environmental covariates and phenology-stage table

source("R/functions.R")
library(dplyr)
library(readr)

ec_raw <- read_csv("Data/raw/environmental_covariates_raw.csv", show_col_types = FALSE)
soil_raw <- read_csv("Data/raw/soil_covariates.csv", show_col_types = FALSE)

phenology <- tibble::tibble(
  stage = c("GERMINATION","COTYLEDON","TRUE_LEAVES","VEG_GROWTH",
            "FLOWERING","FRUIT_DEVELOPMENT","RIPENING","SENESCENCE"),
  start_day = c(0, 7, 12, 22, 32, 42, 55, 70),
  end_day   = c(7, 12, 22, 32, 42, 55, 70, 90)
)

write_csv(phenology, "Output/tables/phenology_stages.csv")

ec <- ec_raw %>%
  rename_with(~gsub("\\s+", "_", .x)) %>%
  mutate(state_county = std_county_name(state_county))

soil <- soil_raw %>%
  rename_with(~gsub("\\s+", "_", .x)) %>%
  mutate(state_county = std_county_name(state_county))

ec_all <- ec %>% left_join(soil, by = "state_county")
write_csv(ec_all, "Data/processed/ec_all_stage_aggregated.csv")

message("Environmental covariates prepared.")
