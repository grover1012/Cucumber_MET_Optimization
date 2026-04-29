###############################################
# Multi-location environmental data extraction,
# processing, predictor selection, and clustering
# for cucumber yield
#
# Main steps:
# 1. Load metadata and yield data
# 2. Extract daily weather data with EnvRtype
# 3. Process weather data using cucumber cardinal temperatures
# 4. Build the weather environmental covariate matrix
# 5. Extract soil covariates with SoilType
# 6. Combine weather and soil covariates
# 7. Prepare environment-year mean yield
# 8. Run stepwise regression
# 9. Run recursive feature elimination (RFE)
# 10. Create clustering outputs
# 11. Save all important outputs
#
# Notes:
# - This script is intended for the historical
#   multi-location dataset (for example, the 7
#   historical cucumber trial locations).
# - The script expects metadata with one row per
#   env-year planting-harvest window.
# - Clustering is done in two ways:
#   (a) env_year clustering
#   (b) environment-level clustering after averaging
#       selected covariates across years
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
library(SoilType)
library(caret)
library(sommer)
library(MASS)
library(ggrepel)
library(factoextra)

############################
# 2. Set file paths and output folder
############################

# Set your project working directory if needed
# setwd("PATH/TO/YOUR/PROJECT")

# Update these file names to match your repo
site_file  <- "Data/raw/MLT_metadata.xlsx"
yield_file <- "Data/raw/MLT_yield.xlsx"

output_dir <- "Outputs/MLT_historical"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

############################
# 3. Read input files
############################

cat("Reading metadata and yield files...\n")

met <- read_excel(site_file)
yld <- read_excel(yield_file)

############################
# 4. Check required columns
############################

required_met_cols <- c("env", "Year", "lat", "lon", "Alt", "plantingDate", "harvestDate")
required_yld_cols <- c("env", "Year", "genotype", "replicate", "yield")

missing_met_cols <- setdiff(required_met_cols, names(met))
missing_yld_cols <- setdiff(required_yld_cols, names(yld))

if (length(missing_met_cols) > 0) {
  stop("The following required columns are missing in the metadata file:\n",
       paste(missing_met_cols, collapse = ", "))
}

if (length(missing_yld_cols) > 0) {
  stop("The following required columns are missing in the yield file:\n",
       paste(missing_yld_cols, collapse = ", "))
}

############################
# 5. Prepare metadata and yield data
############################

cat("Preparing metadata and phenotype data...\n")

met <- met %>%
  mutate(
    env          = as.character(env),
    Year         = as.integer(Year),
    lat          = as.numeric(lat),
    lon          = as.numeric(lon),
    Alt          = as.numeric(Alt),
    plantingDate = as.Date(plantingDate),
    harvestDate  = as.Date(harvestDate),
    start.day    = as.Date(plantingDate),
    end.day      = as.Date(harvestDate)
  ) %>%
  arrange(env, Year)

yld <- yld %>%
  mutate(
    env       = as.character(env),
    Year      = as.integer(Year),
    genotype  = as.factor(genotype),
    replicate = as.factor(replicate),
    yield     = as.numeric(yield)
  ) %>%
  filter(env %in% met$env)

write.csv(met, file.path(output_dir, "MLT_metadata_clean.csv"), row.names = FALSE)
write.csv(yld, file.path(output_dir, "MLT_yield_clean.csv"), row.names = FALSE)

############################
# 6. Extract daily weather data using EnvRtype
############################

cat("Starting daily weather extraction...\n")

weather_list <- vector("list", length = nrow(met))

for (i in seq_len(nrow(met))) {

  cat("Extracting weather for", met$env[i], "Year", met$Year[i],
      "(", i, "of", nrow(met), ")...\n")

  one_row <- met[i, ]

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
      cat("Weather extraction failed for", one_row$env, "Year", one_row$Year, ":", e$message, "\n")
      return(NULL)
    }
  )

  if (!is.null(weather_try) && nrow(weather_try) > 0) {
    weather_try <- weather_try %>%
      mutate(
        env  = one_row$env,
        Year = one_row$Year,
        Alt  = one_row$Alt
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
          file.path(output_dir, "MLT_raw_daily_weather.csv"),
          row.names = FALSE)

############################
# 7. Prepare daily weather data
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
          file.path(output_dir, "MLT_daily_weather_prepared.csv"),
          row.names = FALSE)

############################
# 8. Process weather data with cucumber cardinal temperatures
############################

cat("Processing weather data with processWTH...\n")

df_clim <- processWTH(
  env.data = aux2,
  Tbase1   = 15.6,
  Tbase2   = 32.2,
  Topt1    = 21,
  Topt2    = 30,
  Alt      = aux2$Alt
)

if (!("env_year" %in% names(df_clim))) {
  df_clim <- df_clim %>%
    mutate(
      YEAR     = as.integer(format(as.Date(YYYYMMDD), "%Y")),
      env_year = paste(env, YEAR, sep = "_")
    )
}

write.csv(df_clim,
          file.path(output_dir, "MLT_processed_weather.csv"),
          row.names = FALSE)

############################
# 9. Build weather environmental covariate matrix
############################

cat("Building weather environmental covariate matrix...\n")

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
  "year", "LON", "LAT", "Alt"
)

var_i2 <- setdiff(
  names(df_clim2)[sapply(df_clim2, is.numeric)],
  drop_cols_weather
)

E_weather <- W_matrix(
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

E_weather[is.na(E_weather)] <- 0

E_weather_df <- as.data.frame(E_weather)
E_weather_df$env_year <- rownames(E_weather_df)

write.csv(E_weather_df,
          file.path(output_dir, "MLT_weather_W_matrix.csv"),
          row.names = FALSE)

############################
# 10. Extract soil covariates using SoilType
############################

cat("Extracting soil covariates...\n")

# Soil is extracted once per unique environment because
# soil does not change across years in this workflow.
met_unique_env <- met %>%
  distinct(env, lat, lon, Alt)

soil_list <- vector("list", length = nrow(met_unique_env))

for (i in seq_len(nrow(met_unique_env))) {

  cat("Extracting soil data for", met_unique_env$env[i],
      "(", i, "of", nrow(met_unique_env), ")...\n")

  one_row <- met_unique_env[i, ]

  soil_try <- tryCatch(
    {
      get_soil(
        env.id = one_row$env,
        lat    = one_row$lat,
        long   = one_row$lon
      )
    },
    error = function(e) {
      cat("Soil extraction failed for", one_row$env, ":", e$message, "\n")
      return(NULL)
    }
  )

  if (!is.null(soil_try) && nrow(soil_try) > 0) {
    soil_list[[i]] <- soil_try
  } else {
    soil_list[[i]] <- NULL
  }
}

soil_raw <- bind_rows(soil_list)

if (nrow(soil_raw) == 0) {
  stop("No soil data were extracted. Please check coordinates and SoilType setup.")
}

write.csv(soil_raw,
          file.path(output_dir, "MLT_raw_soil_data.csv"),
          row.names = FALSE)

############################
# 11. Prepare soil matrix
############################

cat("Preparing soil covariate matrix...\n")

soil_df <- soil_raw %>%
  distinct(env.id, .keep_all = TRUE) %>%
  rename(env = env.id)

soil_drop_cols <- c("env", "lat", "long", "longitude", "latitude")

soil_vars <- setdiff(names(soil_df)[sapply(soil_df, is.numeric)], soil_drop_cols)

E_soil_env <- soil_df %>%
  select(env, all_of(soil_vars))

met_env_year <- met %>%
  mutate(env_year = paste(env, Year, sep = "_")) %>%
  select(env, Year, env_year)

E_soil_df <- met_env_year %>%
  left_join(E_soil_env, by = "env")

write.csv(E_soil_df,
          file.path(output_dir, "MLT_soil_matrix.csv"),
          row.names = FALSE)

############################
# 12. Combine weather and soil matrices
############################

cat("Combining weather and soil matrices...\n")

E_weather_df <- E_weather_df %>%
  separate(env_year, into = c("env", "YEAR"), sep = "_(?=[0-9]{4}$)", remove = FALSE) %>%
  mutate(YEAR = as.integer(YEAR))

E_combined <- E_weather_df %>%
  left_join(E_soil_df, by = c("env", "YEAR" = "Year", "env_year"))

write.csv(E_combined,
          file.path(output_dir, "MLT_combined_weather_soil_matrix.csv"),
          row.names = FALSE)

############################
# 13. Prepare phenotype means for predictor selection
############################

cat("Preparing phenotype means...\n")

yield_env_year <- yld %>%
  group_by(env, Year) %>%
  summarise(
    mean_yield = mean(yield, na.rm = TRUE),
    n_obs      = n(),
    .groups    = "drop"
  ) %>%
  mutate(env_year = paste(env, Year, sep = "_"))

write.csv(yield_env_year,
          file.path(output_dir, "MLT_env_year_mean_yield.csv"),
          row.names = FALSE)

analysis_df <- E_combined %>%
  left_join(yield_env_year, by = c("env", "YEAR" = "Year", "env_year")) %>%
  filter(!is.na(mean_yield))

write.csv(analysis_df,
          file.path(output_dir, "MLT_analysis_dataset_for_predictor_selection.csv"),
          row.names = FALSE)

############################
# 14. Prepare predictor matrix
############################

cat("Preparing predictor matrix...\n")

drop_cols_analysis <- c("env", "YEAR", "env_year", "mean_yield", "n_obs")
predictor_names <- setdiff(names(analysis_df), drop_cols_analysis)
predictor_names <- predictor_names[sapply(analysis_df[, predictor_names, drop = FALSE], is.numeric)]

predictor_df <- analysis_df %>%
  select(all_of(predictor_names))

nzv_info <- nearZeroVar(predictor_df, saveMetrics = TRUE)
predictor_names_keep <- rownames(nzv_info)[!nzv_info$nzv]

predictor_df <- predictor_df[, predictor_names_keep, drop = FALSE]

model_df <- bind_cols(
  analysis_df %>% select(env, YEAR, env_year, mean_yield),
  predictor_df
)

write.csv(model_df,
          file.path(output_dir, "MLT_predictor_model_dataset.csv"),
          row.names = FALSE)

############################
# 15. Stepwise regression
############################

cat("Running stepwise regression...\n")

full_formula <- as.formula(
  paste("mean_yield ~", paste(colnames(predictor_df), collapse = " + "))
)

null_model <- lm(mean_yield ~ 1, data = model_df)
full_model <- lm(full_formula, data = model_df)

step_model <- stepAIC(
  null_model,
  scope = list(lower = null_model, upper = full_model),
  direction = "both",
  trace = FALSE
)

stepwise_selected <- names(coef(step_model))
stepwise_selected <- setdiff(stepwise_selected, "(Intercept)")

stepwise_table <- data.frame(
  predictor = stepwise_selected,
  stringsAsFactors = FALSE
)

write.csv(stepwise_table,
          file.path(output_dir, "MLT_stepwise_selected_predictors.csv"),
          row.names = FALSE)

capture.output(
  summary(step_model),
  file = file.path(output_dir, "MLT_stepwise_model_summary.txt")
)

############################
# 16. Recursive feature elimination (RFE)
############################

cat("Running recursive feature elimination (RFE)...\n")

set.seed(123)

x_rfe <- predictor_df
y_rfe <- model_df$mean_yield

rfe_ctrl <- rfeControl(
  functions = lmFuncs,
  method    = "repeatedcv",
  number    = 5,
  repeats   = 5
)

rfe_sizes <- seq(5, min(30, ncol(x_rfe)), by = 1)
if (length(rfe_sizes) == 0) {
  rfe_sizes <- seq_len(min(5, ncol(x_rfe)))
}

rfe_fit <- rfe(
  x          = x_rfe,
  y          = y_rfe,
  sizes      = rfe_sizes,
  rfeControl = rfe_ctrl
)

rfe_selected <- predictors(rfe_fit)

rfe_table <- data.frame(
  predictor = rfe_selected,
  stringsAsFactors = FALSE
)

write.csv(rfe_table,
          file.path(output_dir, "MLT_RFE_selected_predictors.csv"),
          row.names = FALSE)

capture.output(
  print(rfe_fit),
  file = file.path(output_dir, "MLT_RFE_summary.txt")
)

############################
# 17. Combine selected predictors
############################

cat("Combining selected predictors from stepwise and RFE...\n")

final_predictors <- sort(unique(c(stepwise_selected, rfe_selected)))

final_predictor_table <- data.frame(
  predictor = final_predictors,
  stringsAsFactors = FALSE
)

write.csv(final_predictor_table,
          file.path(output_dir, "MLT_final_selected_predictors.csv"),
          row.names = FALSE)

selected_data <- model_df %>%
  select(env, YEAR, env_year, mean_yield, all_of(final_predictors))

write.csv(selected_data,
          file.path(output_dir, "MLT_selected_predictor_dataset.csv"),
          row.names = FALSE)

############################
# 18. Clustering at the env_year level
############################

cat("Running env_year PCA and clustering...\n")

cluster_input_env_year <- selected_data %>%
  select(all_of(final_predictors))

cluster_input_env_year <- cluster_input_env_year[, sapply(cluster_input_env_year, is.numeric), drop = FALSE]

keep_sd1 <- sapply(cluster_input_env_year, function(x) sd(x, na.rm = TRUE) > 0)
cluster_input_env_year <- cluster_input_env_year[, keep_sd1, drop = FALSE]

cluster_scaled_env_year <- scale(cluster_input_env_year)

pca_fit_env_year <- prcomp(cluster_scaled_env_year, center = TRUE, scale. = TRUE)

pca_scores_env_year <- as.data.frame(pca_fit_env_year$x)
pca_scores_env_year$env_year <- selected_data$env_year

write.csv(pca_scores_env_year,
          file.path(output_dir, "MLT_env_year_PCA_scores.csv"),
          row.names = FALSE)

png(file.path(output_dir, "MLT_env_year_PCA_plot.png"), width = 1800, height = 1400, res = 220)
fviz_pca_ind(
  pca_fit_env_year,
  geom.ind = "point",
  repel    = TRUE
) +
  ggtitle("PCA of selected environmental covariates (env_year)")
dev.off()

png(file.path(output_dir, "MLT_env_year_elbow_plot.png"), width = 1800, height = 1400, res = 220)
fviz_nbclust(as.data.frame(cluster_scaled_env_year), kmeans, method = "wss") +
  ggtitle("Elbow plot for K-means clustering (env_year)")
dev.off()

# Change k_target_env_year manually if needed after inspecting the elbow plot
k_target_env_year <- 3

set.seed(123)
km_fit_env_year <- kmeans(cluster_scaled_env_year, centers = k_target_env_year, nstart = 50)

cluster_assignments_env_year <- selected_data %>%
  select(env, YEAR, env_year, mean_yield) %>%
  mutate(cluster = factor(km_fit_env_year$cluster))

write.csv(cluster_assignments_env_year,
          file.path(output_dir, "MLT_env_year_cluster_assignments.csv"),
          row.names = FALSE)

############################
# 19. Clustering at the environment level
############################

cat("Running environment-level PCA and clustering...\n")

env_level_selected <- selected_data %>%
  group_by(env) %>%
  summarise(
    across(all_of(final_predictors), ~mean(.x, na.rm = TRUE)),
    .groups = "drop"
  )

write.csv(env_level_selected,
          file.path(output_dir, "MLT_environment_mean_selected_predictors.csv"),
          row.names = FALSE)

cluster_input_env <- env_level_selected %>%
  select(-env)

cluster_input_env <- cluster_input_env[, sapply(cluster_input_env, is.numeric), drop = FALSE]

keep_sd2 <- sapply(cluster_input_env, function(x) sd(x, na.rm = TRUE) > 0)
cluster_input_env <- cluster_input_env[, keep_sd2, drop = FALSE]

cluster_scaled_env <- scale(cluster_input_env)

pca_fit_env <- prcomp(cluster_scaled_env, center = TRUE, scale. = TRUE)

pca_scores_env <- as.data.frame(pca_fit_env$x)
pca_scores_env$env <- env_level_selected$env

write.csv(pca_scores_env,
          file.path(output_dir, "MLT_environment_PCA_scores.csv"),
          row.names = FALSE)

png(file.path(output_dir, "MLT_environment_PCA_plot.png"), width = 1800, height = 1400, res = 220)
fviz_pca_ind(
  pca_fit_env,
  geom.ind = "point",
  repel    = TRUE
) +
  ggtitle("PCA of selected environmental covariates (environment means)")
dev.off()

png(file.path(output_dir, "MLT_environment_elbow_plot.png"), width = 1800, height = 1400, res = 220)
fviz_nbclust(as.data.frame(cluster_scaled_env), kmeans, method = "wss") +
  ggtitle("Elbow plot for K-means clustering (environment means)")
dev.off()

# Change k_target_env manually if needed after inspecting the elbow plot
k_target_env <- 3

set.seed(123)
km_fit_env <- kmeans(cluster_scaled_env, centers = k_target_env, nstart = 50)

cluster_assignments_env <- env_level_selected %>%
  select(env) %>%
  mutate(cluster = factor(km_fit_env$cluster))

write.csv(cluster_assignments_env,
          file.path(output_dir, "MLT_environment_cluster_assignments.csv"),
          row.names = FALSE)

cluster_profiles_env <- env_level_selected %>%
  left_join(cluster_assignments_env, by = "env") %>%
  group_by(cluster) %>%
  summarise(
    across(-env, ~mean(.x, na.rm = TRUE)),
    .groups = "drop"
  )

write.csv(cluster_profiles_env,
          file.path(output_dir, "MLT_environment_cluster_profiles.csv"),
          row.names = FALSE)

cluster_plot_df_env <- pca_scores_env %>%
  left_join(cluster_assignments_env, by = "env")

png(file.path(output_dir, "MLT_environment_cluster_plot.png"), width = 1800, height = 1400, res = 220)
ggplot(cluster_plot_df_env, aes(x = PC1, y = PC2, color = cluster, label = env)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(size = 3.5, max.overlaps = 50) +
  theme_bw(base_size = 14) +
  labs(
    title = "K-means clustering of historical environments",
    x = "PC1",
    y = "PC2"
  )
dev.off()

############################
# 20. Save R objects
############################

cat("Saving R workspace objects...\n")

save(
  met,
  yld,
  env.data,
  aux2,
  df_clim,
  df_clim2,
  E_weather,
  E_weather_df,
  soil_raw,
  E_soil_df,
  E_combined,
  yield_env_year,
  analysis_df,
  predictor_df,
  model_df,
  step_model,
  stepwise_selected,
  rfe_fit,
  rfe_selected,
  final_predictors,
  selected_data,
  env_level_selected,
  pca_fit_env_year,
  pca_scores_env_year,
  km_fit_env_year,
  cluster_assignments_env_year,
  pca_fit_env,
  pca_scores_env,
  km_fit_env,
  cluster_assignments_env,
  cluster_profiles_env,
  file = file.path(output_dir, "MLT_historical_analysis_objects.RData")
)

############################
# 21. Final message
############################

cat("--------------------------------------------------\n")
cat("Multi-location workflow completed successfully.\n")
cat("Outputs saved in:", output_dir, "\n")
cat("--------------------------------------------------\n")
