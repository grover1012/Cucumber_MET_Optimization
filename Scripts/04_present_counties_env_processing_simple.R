###############################################
# Present counties environmental data extraction
# and processing for the cucumber MET project
# (2010-2025)
#
# Main steps:
# 1. Load county metadata
# 2. Build env × year planting-harvest windows
# 3. Extract daily weather data with EnvRtype
# 4. Process daily weather data
# 5. Build an environmental covariate matrix
# 6. Create monthly summaries
# 7. Create present scenario windows (Mar-Jun and Apr-Jul)
# 8. Build county-level present environmental tables
# 9. Save outputs for downstream clustering and
#    present-vs-future comparison analyses
#
# Notes:
# - This script is for the present scenario
#   (2010-2025) and is intended for county-based
#   environmental characterization.
# - It does not perform predictor selection.
# - It creates both a full EnvRtype-based matrix
#   and simpler monthly/window summaries used in
#   later clustering comparisons.
###############################################

############################
# 0. Clean environment
############################
rm(list = ls())
gc()

############################
# 1. Load required packages
############################
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(tibble)
library(ggplot2)
library(EnvRtype)
library(lubridate)

############################
# 2. Set file paths and output folder
############################

# Set your project working directory if needed
# setwd("PATH/TO/YOUR/PROJECT")

county_file <- "Data/raw/county_acerage.xlsx"

output_dir <- "Outputs/Present_counties_2010_2025"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

############################
# 3. Read county metadata
############################

cat("Reading county metadata file...\n")

county_data <- read_excel(county_file)

############################
# 4. Check required columns
############################

required_county_cols <- c("env", "lat", "lon", "plantingDate", "harvestDate")

missing_county_cols <- setdiff(required_county_cols, names(county_data))

if (length(missing_county_cols) > 0) {
  stop("The following required columns are missing in the county metadata file:\n",
       paste(missing_county_cols, collapse = ", "))
}

############################
# 5. Prepare county metadata
############################

cat("Preparing county metadata...\n")

county_data <- county_data %>%
  mutate(
    env          = as.character(env),
    lat          = as.numeric(lat),
    lon          = as.numeric(lon),
    plantingDate = as.Date(plantingDate),
    harvestDate  = as.Date(harvestDate),
    plant_md     = format(plantingDate, "%m-%d"),
    harvest_md   = format(harvestDate, "%m-%d")
  ) %>%
  select(env, lat, lon, plant_md, harvest_md)

write.csv(county_data,
          file.path(output_dir, "present_county_metadata_clean.csv"),
          row.names = FALSE)

############################
# 6. Build env × year planting-harvest table
############################

cat("Building env × year planting-harvest table...\n")

years <- 2010:2025

df_long <- county_data %>%
  crossing(year = years) %>%
  mutate(
    start.day = as.Date(paste(year, plant_md, sep = "-")),
    end.day   = as.Date(paste(year, harvest_md, sep = "-"))
  )

write.csv(df_long,
          file.path(output_dir, "present_county_env_year_windows_2010_2025.csv"),
          row.names = FALSE)

############################
# 7. Extract daily weather data using EnvRtype
############################

cat("Starting daily weather extraction...\n")

weather_list <- vector("list", length = nrow(df_long))

for (i in seq_len(nrow(df_long))) {

  cat("Extracting weather for", df_long$env[i], "Year", df_long$year[i],
      "(", i, "of", nrow(df_long), ")...\n")

  one_row <- df_long[i, ]

  weather_try <- tryCatch(
    {
      EnvRtype::get_weather(
        env.id         = one_row$env,
        lat            = one_row$lat,
        lon            = one_row$lon,
        start.day      = one_row$start.day,
        end.day        = one_row$end.day,
        temporal.scale = "daily",
        parallel       = FALSE
      )
    },
    error = function(e) {
      cat("Weather extraction failed for", one_row$env, "Year", one_row$year, ":", e$message, "\n")
      return(NULL)
    }
  )

  if (!is.null(weather_try) && nrow(weather_try) > 0) {
    weather_try <- weather_try %>%
      mutate(
        env  = one_row$env,
        year = one_row$year
      )
    weather_list[[i]] <- weather_try
  } else {
    weather_list[[i]] <- NULL
  }
}

env.data <- bind_rows(weather_list)

if (nrow(env.data) == 0) {
  stop("No weather data were extracted. Please check internet access, coordinates, and dates.")
}

write.csv(env.data,
          file.path(output_dir, "present_raw_daily_weather_2010_2025.csv"),
          row.names = FALSE)

############################
# 8. Prepare daily weather data
############################

cat("Preparing daily weather data...\n")

aux2 <- env.data %>%
  mutate(
    YYYYMMDD = as.Date(YYYYMMDD),
    YEAR     = as.integer(format(YYYYMMDD, "%Y")),
    MM       = format(YYYYMMDD, "%m"),
    DD       = format(YYYYMMDD, "%d"),
    env_year = paste(env, YEAR, sep = "_")
  )

write.csv(aux2,
          file.path(output_dir, "present_daily_weather_prepared_2010_2025.csv"),
          row.names = FALSE)

############################
# 9. Process weather data with cucumber cardinal temperatures
############################

cat("Processing weather data with processWTH...\n")

df_clim <- processWTH(
  env.data = aux2,
  Tbase1   = 15.6,
  Tbase2   = 32.2,
  Topt1    = 21,
  Topt2    = 30
)

if (!("env_year" %in% names(df_clim))) {
  df_clim <- df_clim %>%
    mutate(
      YEAR     = as.integer(format(as.Date(YYYYMMDD), "%Y")),
      env_year = paste(env, YEAR, sep = "_")
    )
}

write.csv(df_clim,
          file.path(output_dir, "present_processed_weather_2010_2025.csv"),
          row.names = FALSE)

############################
# 10. Build full EnvRtype environmental covariate matrix
############################

cat("Building full EnvRtype environmental covariate matrix...\n")

stages <- c(
  "GERMINATION",
  "COTYLEDON",
  "TRUE_LEAVES",
  "VEG_GROWTH",
  "FLOWERING",
  "FRUIT_DEVELOPMENT",
  "RIPENING",
  "SENESCENCE"
)

intervals <- c(0, 7, 12, 22, 32, 42, 55, 70, 90)

df_clim2 <- df_clim %>%
  mutate(
    YYYYMMDD = as.Date(YYYYMMDD),
    YEAR     = as.integer(format(YYYYMMDD, "%Y")),
    env_year = paste(env, YEAR, sep = "_"),
    env_orig = env,
    env      = env_year
  )

drop_cols_weather <- c(
  "env", "env_year", "env_orig", "YYYYMMDD",
  "YEAR", "MM", "DD", "DOY", "daysFromStart",
  "year", "LON", "LAT"
)

var_i2 <- setdiff(
  names(df_clim2)[sapply(df_clim2, is.numeric)],
  drop_cols_weather
)

E_present_full <- W_matrix(
  env.data     = df_clim2,
  env.id       = "env",
  var.id       = var_i2,
  statistic    = "mean",
  scale        = FALSE,
  center       = FALSE,
  by.interval  = TRUE,
  sd.tol       = 5,
  time.window  = intervals,
  names.window = stages
)

E_present_full[is.na(E_present_full)] <- 0

E_present_full_df <- as.data.frame(E_present_full)
E_present_full_df$env_year <- rownames(E_present_full)

write.csv(E_present_full_df,
          file.path(output_dir, "present_full_W_matrix_2010_2025.csv"),
          row.names = FALSE)

############################
# 11. Convert full W matrix to county means across years
############################

cat("Creating county means from the full W matrix...\n")

E_present_df <- E_present_full_df %>%
  separate(env_year, into = c("env", "YEAR"), sep = "_(?=[0-9]{4}$)", remove = FALSE) %>%
  mutate(YEAR = as.integer(YEAR))

E_present_mean <- E_present_df %>%
  group_by(env) %>%
  summarise(
    across(where(is.numeric), ~mean(.x, na.rm = TRUE)),
    .groups = "drop"
  )

write.csv(E_present_mean,
          file.path(output_dir, "present_full_W_matrix_county_means_2010_2025.csv"),
          row.names = FALSE)

############################
# 12. Create monthly daily-weather summaries
############################

cat("Creating monthly daily-weather summaries...\n")

present_daily <- aux2 %>%
  mutate(
    date  = as.Date(YYYYMMDD),
    year  = year(date),
    month = month(date)
  ) %>%
  filter(year >= 2010, year <= 2025)

present_monthly <- present_daily %>%
  group_by(env, year, month) %>%
  summarise(
    T2M     = mean(T2M, na.rm = TRUE),
    WS2M    = mean(WS2M, na.rm = TRUE),
    SW      = mean(ALLSKY_SFC_SW_DWN, na.rm = TRUE),
    LW      = mean(ALLSKY_SFC_LW_DWN, na.rm = TRUE),
    RH2M    = mean(RH2M, na.rm = TRUE),
    QV2M    = mean(QV2M, na.rm = TRUE),
    PRECTOT = mean(PRECTOT, na.rm = TRUE),
    VPD_kPa = mean(VPD, na.rm = TRUE),
    .groups = "drop"
  )

write.csv(present_monthly,
          file.path(output_dir, "present_monthly_weather_2010_2025.csv"),
          row.names = FALSE)

############################
# 13. Create present scenario windows
############################

cat("Creating present scenario windows...\n")

vars_keep <- c("T2M", "WS2M", "SW", "LW", "RH2M", "QV2M", "PRECTOT", "VPD_kPa")

present_MJ <- present_monthly %>%
  filter(month %in% 3:6) %>%
  group_by(env, year) %>%
  summarise(
    across(all_of(vars_keep), ~mean(.x, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  mutate(window = "Mar-Jun")

present_AJ <- present_monthly %>%
  filter(month %in% 4:7) %>%
  group_by(env, year) %>%
  summarise(
    across(all_of(vars_keep), ~mean(.x, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  mutate(window = "Apr-Jul")

present_win <- bind_rows(present_MJ, present_AJ)

write.csv(present_win,
          file.path(output_dir, "present_window_weather_by_env_year_2010_2025.csv"),
          row.names = FALSE)

############################
# 14. Create final county-level present EC table
############################

cat("Creating final county-level present EC table...\n")

present_EC <- present_win %>%
  group_by(env, window) %>%
  summarise(
    across(all_of(vars_keep), ~mean(.x, na.rm = TRUE)),
    .groups = "drop"
  )

write.csv(present_EC,
          file.path(output_dir, "present_county_window_EC_2010_2025.csv"),
          row.names = FALSE)

############################
# 15. Create no-precipitation version for future matching
############################

cat("Creating no-precipitation version for future matching...\n")

present_EC_no_precip <- present_EC %>%
  select(env, window, T2M, WS2M, SW, LW, RH2M, QV2M, VPD_kPa)

write.csv(present_EC_no_precip,
          file.path(output_dir, "present_county_window_EC_2010_2025_no_precip.csv"),
          row.names = FALSE)

############################
# 16. Save R objects
############################

cat("Saving R workspace objects...\n")

save(
  county_data,
  df_long,
  env.data,
  aux2,
  df_clim,
  df_clim2,
  E_present_full,
  E_present_full_df,
  E_present_df,
  E_present_mean,
  present_daily,
  present_monthly,
  present_MJ,
  present_AJ,
  present_win,
  present_EC,
  present_EC_no_precip,
  file = file.path(output_dir, "Present_counties_2010_2025_objects.RData")
)

############################
# 17. Final message
############################

cat("--------------------------------------------------\n")
cat("Present counties workflow completed successfully.\n")
cat("Outputs saved in:", output_dir, "\n")
cat("--------------------------------------------------\n")
