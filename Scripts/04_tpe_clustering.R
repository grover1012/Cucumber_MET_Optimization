# 04_tpe_clustering.R
# PCA and k-means clustering for MLT, MYT, present counties, and future windows

source("R/functions.R")
library(dplyr)
library(readr)
library(tibble)

selected_ecs <- read_csv("Output/tables/final_14_selected_ECs.csv", show_col_types = FALSE)$EC
ec_all <- read_csv("Data/processed/ec_all_stage_aggregated.csv", show_col_types = FALSE)

cluster_envs <- function(df, id_col, k, prefix) {
  W <- df %>%
    select(all_of(id_col), all_of(selected_ecs)) %>%
    distinct() %>%
    column_to_rownames(id_col)

  W <- W[, colSums(is.na(W)) == 0, drop = FALSE]
  W_scaled <- scale(W)

  p_elbow <- make_elbow_plot(W_scaled, max_k = min(10, nrow(W_scaled)-1),
                             title = paste(prefix, "WSS elbow"))
  ggsave(paste0("Figures/", prefix, "_elbow.png"), p_elbow,
         width = 7, height = 5, dpi = 600)

  set.seed(123)
  km <- kmeans(W_scaled, centers = k, nstart = 50)
  clusters <- setNames(as.character(km$cluster), rownames(W_scaled))

  pca_out <- make_pca_cluster_plot(W_scaled, clusters, title = prefix)
  ggsave(paste0("Figures/", prefix, "_PCA_clusters.png"), pca_out$plot,
         width = 8, height = 6, dpi = 600)

  out <- data.frame(env = rownames(W_scaled), cluster = clusters)
  write_csv(out, paste0("Output/tables/", prefix, "_clusters.csv"))
  saveRDS(list(W_scaled = W_scaled, km = km, pca = pca_out$pca, clusters = out),
          paste0("Output/intermediate/", prefix, "_cluster_object.rds"))
}

mlt <- read_csv("Data/processed/mlt_clean.csv", show_col_types = FALSE)
mlt_envs <- mlt %>%
  distinct(env, state_county, year) %>%
  left_join(ec_all, by = c("state_county", "year"))
cluster_envs(mlt_envs, "env", 3, "MLT_k3")

myt <- read_csv("Data/processed/myt_clean.csv", show_col_types = FALSE)
myt_envs <- myt %>%
  distinct(env, state_county, year) %>%
  left_join(ec_all, by = c("state_county", "year"))
cluster_envs(myt_envs, "env", 5, "MYT_k5")

if (file.exists("Data/processed/present_county_ec_2010_2025.csv")) {
  present <- read_csv("Data/processed/present_county_ec_2010_2025.csv", show_col_types = FALSE)
  cluster_envs(present, "env", 3, "Present_counties_k3")
}

if (file.exists("Data/processed/future_county_ec_Mar_Jun_2050_2065.csv")) {
  fut_mj <- read_csv("Data/processed/future_county_ec_Mar_Jun_2050_2065.csv", show_col_types = FALSE)
  cluster_envs(fut_mj, "env", 3, "Future_Mar_Jun_k3")
}

if (file.exists("Data/processed/future_county_ec_Apr_Jul_2050_2065.csv")) {
  fut_aj <- read_csv("Data/processed/future_county_ec_Apr_Jul_2050_2065.csv", show_col_types = FALSE)
  cluster_envs(fut_aj, "env", 3, "Future_Apr_Jul_k3")
}

message("TPE clustering complete.")
