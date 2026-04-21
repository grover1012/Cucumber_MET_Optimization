# 01_prepare_phenotypes.R
# Prepare historical multi-location and multi-year phenotype datasets

source("R/functions.R")
library(dplyr)
library(readr)

mlt_raw <- read_csv("Data/raw/mlt_yield.csv", show_col_types = FALSE)
myt_raw <- read_csv("Data/raw/myt_yield.csv", show_col_types = FALSE)

# Multi-location trial: 7 locations x 3 years = 21 location-year environments
mlt <- mlt_raw %>%
  rename_with(tolower) %>%
  mutate(
    genotype = as.character(genotype),
    year = as.integer(year),
    location = as.character(location),
    env = paste0(location, "_", year)
  )

location_county_map <- tibble::tribble(
  ~location, ~state_county,
  "Leesburg", "Florida_Lake",
  "Clinton", "North_Carolina_Wake",
  "Bixby", "Oklahoma_Wagoner",
  "Napoleon", "Ohio_Henry",
  "East Lansing", "Michigan_Ingham",
  "Hancock", "Wisconsin_Waushara",
  "Brooks", "Oregon_Marion"
)

mlt <- mlt %>%
  left_join(location_county_map, by = "location") %>%
  mutate(state_county = ifelse(is.na(state_county), location, state_county))

if ("gy" %in% names(mlt)) mlt <- rename(mlt, GY = gy)
if ("yield" %in% names(mlt)) mlt <- rename(mlt, GY = yield)

if (n_distinct(mlt$env) != 21) {
  warning("Expected 21 MLT location-year environments. Check location/year coding.")
}

# Multi-year trial: yield is sum across six harvests unless total yield already exists
myt <- myt_raw %>%
  rename_with(tolower) %>%
  mutate(genotype = as.character(genotype), year = as.integer(year)) %>%
  filter(year != 2017)

harvest_cols <- grep("^harvest|^h[1-6]$", names(myt), value = TRUE)

if (!"gy" %in% names(myt) && !"yield" %in% names(myt)) {
  if (length(harvest_cols) >= 6) {
    myt <- myt %>% mutate(GY = rowSums(across(all_of(harvest_cols)), na.rm = TRUE))
  } else {
    stop("MYT file must contain either gy/yield or six harvest columns.")
  }
} else if ("gy" %in% names(myt)) {
  myt <- rename(myt, GY = gy)
} else {
  myt <- rename(myt, GY = yield)
}

myt <- myt %>%
  mutate(location = "Clinton",
         state_county = "North_Carolina_Wake",
         env = paste0("NC_Wake_", year))

write_csv(mlt, "Data/processed/mlt_clean.csv")
write_csv(myt, "Data/processed/myt_clean.csv")

message("Phenotype data prepared.")
