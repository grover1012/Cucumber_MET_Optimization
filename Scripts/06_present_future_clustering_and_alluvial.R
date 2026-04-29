###############################################
# Present and future environmental clustering
# and alluvial-ready comparison
#
# This script:
# 1. Reads the present environmental matrix
# 2. Reads the future environmental matrices
# 3. Clusters present environments
# 4. Clusters future environments separately
#    for Mar_Jun and Apr_Jul
# 5. Creates PCA plots and cluster assignments
# 6. Creates alluvial-ready tables by joining
#    present and future cluster assignments
###############################################

############################
# 0. Clean environment
############################
rm(list = ls())
gc()

############################
# 1. Load packages
############################
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tibble)
  library(ggplot2)
  library(ggrepel)
  library(factoextra)
})

############################
# 2. File paths
############################

# setwd("/Users/kgrover2/Documents/Cucumber_MET_OPT")

present_file <- "Data/processed/W_present.csv"
future_file_marjun <- "Data/processed/future_matrix_Mar_Jun.csv"
future_file_aprjul <- "Data/processed/future_matrix_Apr_Jul.csv"

output_dir <- "Outputs/Present_future_clustering"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

############################
# 3. Read files
############################

cat("Reading files...\n")

present_raw <- read.csv(present_file, stringsAsFactors = FALSE, check.names = FALSE)
future_marjun_raw <- read.csv(future_file_marjun, stringsAsFactors = FALSE, check.names = FALSE)
future_aprjul_raw <- read.csv(future_file_aprjul, stringsAsFactors = FALSE, check.names = FALSE)

############################
# 4. Check env column
############################

if (!"env" %in% names(present_raw)) {
  stop("Column 'env' not found in present file.")
}

if (!"env" %in% names(future_marjun_raw)) {
  stop("Column 'env' not found in future Mar_Jun file.")
}

if (!"env" %in% names(future_aprjul_raw)) {
  stop("Column 'env' not found in future Apr_Jul file.")
}

############################
# 5. Prepare present data
############################

cat("Preparing present data...\n")

present_df <- present_raw %>%
  mutate(env = as.character(env))

present_vars <- setdiff(
  names(present_df)[sapply(present_df, is.numeric)],
  "env"
)

present_df <- present_df %>%
  select(env, all_of(present_vars))

# remove zero-variance variables
keep_present <- sapply(
  present_df[, present_vars, drop = FALSE],
  function(x) all(is.finite(x)) && sd(x, na.rm = TRUE) > 0
)

present_vars <- names(keep_present)[keep_present]

present_df <- present_df %>%
  select(env, all_of(present_vars))

write.csv(
  present_df,
  file.path(output_dir, "present_data_used_for_clustering.csv"),
  row.names = FALSE
)

############################
# 6. Prepare future data
############################

cat("Preparing future Mar_Jun data...\n")

future_marjun_df <- future_marjun_raw %>%
  mutate(env = as.character(env))

future_marjun_vars <- setdiff(
  names(future_marjun_df)[sapply(future_marjun_df, is.numeric)],
  "env"
)

future_marjun_df <- future_marjun_df %>%
  select(env, all_of(future_marjun_vars))

keep_future_marjun <- sapply(
  future_marjun_df[, future_marjun_vars, drop = FALSE],
  function(x) all(is.finite(x)) && sd(x, na.rm = TRUE) > 0
)

future_marjun_vars <- names(keep_future_marjun)[keep_future_marjun]

future_marjun_df <- future_marjun_df %>%
  select(env, all_of(future_marjun_vars))

write.csv(
  future_marjun_df,
  file.path(output_dir, "future_Mar_Jun_data_used_for_clustering.csv"),
  row.names = FALSE
)

cat("Preparing future Apr_Jul data...\n")

future_aprjul_df <- future_aprjul_raw %>%
  mutate(env = as.character(env))

future_aprjul_vars <- setdiff(
  names(future_aprjul_df)[sapply(future_aprjul_df, is.numeric)],
  "env"
)

future_aprjul_df <- future_aprjul_df %>%
  select(env, all_of(future_aprjul_vars))

keep_future_aprjul <- sapply(
  future_aprjul_df[, future_aprjul_vars, drop = FALSE],
  function(x) all(is.finite(x)) && sd(x, na.rm = TRUE) > 0
)

future_aprjul_vars <- names(keep_future_aprjul)[keep_future_aprjul]

future_aprjul_df <- future_aprjul_df %>%
  select(env, all_of(future_aprjul_vars))

write.csv(
  future_aprjul_df,
  file.path(output_dir, "future_Apr_Jul_data_used_for_clustering.csv"),
  row.names = FALSE
)

############################
# 7. Keep only common environments
############################

cat("Filtering to common environments...\n")

common_envs_marjun <- intersect(
  present_df$env,
  future_marjun_df$env
)

common_envs_aprjul <- intersect(
  present_df$env,
  future_aprjul_df$env
)

present_marjun <- present_df %>%
  filter(env %in% common_envs_marjun)

future_marjun_df <- future_marjun_df %>%
  filter(env %in% common_envs_marjun)

present_aprjul <- present_df %>%
  filter(env %in% common_envs_aprjul)

future_aprjul_df <- future_aprjul_df %>%
  filter(env %in% common_envs_aprjul)

write.csv(
  data.frame(env = sort(common_envs_marjun)),
  file.path(output_dir, "common_envs_present_future_Mar_Jun.csv"),
  row.names = FALSE
)

write.csv(
  data.frame(env = sort(common_envs_aprjul)),
  file.path(output_dir, "common_envs_present_future_Apr_Jul.csv"),
  row.names = FALSE
)

############################
# 8. Scale matrices
############################

cat("Scaling matrices...\n")

X_present_marjun <- scale(present_marjun %>% select(-env))
X_future_marjun  <- scale(future_marjun_df %>% select(-env))

X_present_aprjul <- scale(present_aprjul %>% select(-env))
X_future_aprjul  <- scale(future_aprjul_df %>% select(-env))

############################
# 9. Choose cluster numbers
############################

# Set these manually based on your elbow plots / final paper choice
k_present <- 4
k_future_marjun <- 4
k_future_aprjul <- 4

############################
# 10. PCA and clustering: present
############################

cat("Running PCA and clustering for present...\n")

pca_present <- prcomp(X_present_marjun, center = TRUE, scale. = TRUE)

pca_present_scores <- as.data.frame(pca_present$x)
pca_present_scores$env <- present_marjun$env

set.seed(123)
km_present <- kmeans(X_present_marjun, centers = k_present, nstart = 50)

present_clusters <- present_marjun %>%
  select(env) %>%
  mutate(cluster_present = factor(km_present$cluster))

write.csv(
  present_clusters,
  file.path(output_dir, "present_clusters.csv"),
  row.names = FALSE
)

write.csv(
  pca_present_scores,
  file.path(output_dir, "present_PCA_scores.csv"),
  row.names = FALSE
)

p_present <- pca_present_scores %>%
  left_join(present_clusters, by = "env") %>%
  ggplot(aes(x = PC1, y = PC2, color = cluster_present, label = env)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(size = 3.5, max.overlaps = 50) +
  theme_bw(base_size = 14) +
  labs(
    title = "PCA of present environments",
    x = "PC1",
    y = "PC2"
  )

ggsave(
  file.path(output_dir, "present_cluster_plot.png"),
  p_present,
  width = 10,
  height = 7,
  dpi = 300
)

############################
# 11. PCA and clustering: future Mar_Jun
############################

cat("Running PCA and clustering for future Mar_Jun...\n")

pca_future_marjun <- prcomp(X_future_marjun, center = TRUE, scale. = TRUE)

pca_future_marjun_scores <- as.data.frame(pca_future_marjun$x)
pca_future_marjun_scores$env <- future_marjun_df$env

set.seed(123)
km_future_marjun <- kmeans(X_future_marjun, centers = k_future_marjun, nstart = 50)

future_marjun_clusters <- future_marjun_df %>%
  select(env) %>%
  mutate(cluster_future_marjun = factor(km_future_marjun$cluster))

write.csv(
  future_marjun_clusters,
  file.path(output_dir, "future_Mar_Jun_clusters.csv"),
  row.names = FALSE
)

write.csv(
  pca_future_marjun_scores,
  file.path(output_dir, "future_Mar_Jun_PCA_scores.csv"),
  row.names = FALSE
)

p_future_marjun <- pca_future_marjun_scores %>%
  left_join(future_marjun_clusters, by = "env") %>%
  ggplot(aes(x = PC1, y = PC2, color = cluster_future_marjun, label = env)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(size = 3.5, max.overlaps = 50) +
  theme_bw(base_size = 14) +
  labs(
    title = "PCA of future environments (Mar_Jun)",
    x = "PC1",
    y = "PC2"
  )

ggsave(
  file.path(output_dir, "future_Mar_Jun_cluster_plot.png"),
  p_future_marjun,
  width = 10,
  height = 7,
  dpi = 300
)

############################
# 12. PCA and clustering: future Apr_Jul
############################

cat("Running PCA and clustering for future Apr_Jul...\n")

pca_future_aprjul <- prcomp(X_future_aprjul, center = TRUE, scale. = TRUE)

pca_future_aprjul_scores <- as.data.frame(pca_future_aprjul$x)
pca_future_aprjul_scores$env <- future_aprjul_df$env

set.seed(123)
km_future_aprjul <- kmeans(X_future_aprjul, centers = k_future_aprjul, nstart = 50)

future_aprjul_clusters <- future_aprjul_df %>%
  select(env) %>%
  mutate(cluster_future_aprjul = factor(km_future_aprjul$cluster))

write.csv(
  future_aprjul_clusters,
  file.path(output_dir, "future_Apr_Jul_clusters.csv"),
  row.names = FALSE
)

write.csv(
  pca_future_aprjul_scores,
  file.path(output_dir, "future_Apr_Jul_PCA_scores.csv"),
  row.names = FALSE
)

p_future_aprjul <- pca_future_aprjul_scores %>%
  left_join(future_aprjul_clusters, by = "env") %>%
  ggplot(aes(x = PC1, y = PC2, color = cluster_future_aprjul, label = env)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(size = 3.5, max.overlaps = 50) +
  theme_bw(base_size = 14) +
  labs(
    title = "PCA of future environments (Apr_Jul)",
    x = "PC1",
    y = "PC2"
  )

ggsave(
  file.path(output_dir, "future_Apr_Jul_cluster_plot.png"),
  p_future_aprjul,
  width = 10,
  height = 7,
  dpi = 300
)

############################
# 13. Alluvial-ready tables
############################

cat("Creating alluvial-ready tables...\n")

alluvial_marjun <- present_clusters %>%
  inner_join(future_marjun_clusters, by = "env") %>%
  count(cluster_present, cluster_future_marjun, name = "Freq") %>%
  arrange(cluster_present, cluster_future_marjun)

write.csv(
  alluvial_marjun,
  file.path(output_dir, "alluvial_present_to_future_Mar_Jun.csv"),
  row.names = FALSE
)

alluvial_aprjul <- present_clusters %>%
  inner_join(future_aprjul_clusters, by = "env") %>%
  count(cluster_present, cluster_future_aprjul, name = "Freq") %>%
  arrange(cluster_present, cluster_future_aprjul)

write.csv(
  alluvial_aprjul,
  file.path(output_dir, "alluvial_present_to_future_Apr_Jul.csv"),
  row.names = FALSE
)

comparison_marjun <- present_clusters %>%
  inner_join(future_marjun_clusters, by = "env")

comparison_aprjul <- present_clusters %>%
  inner_join(future_aprjul_clusters, by = "env")

write.csv(
  comparison_marjun,
  file.path(output_dir, "present_future_cluster_comparison_Mar_Jun.csv"),
  row.names = FALSE
)

write.csv(
  comparison_aprjul,
  file.path(output_dir, "present_future_cluster_comparison_Apr_Jul.csv"),
  row.names = FALSE
)

############################
# 14. Save objects
############################

cat("Saving R objects...\n")

save(
  present_raw,
  future_marjun_raw,
  future_aprjul_raw,
  present_df,
  future_marjun_df,
  future_aprjul_df,
  present_marjun,
  present_aprjul,
  X_present_marjun,
  X_future_marjun,
  X_present_aprjul,
  X_future_aprjul,
  pca_present,
  pca_future_marjun,
  pca_future_aprjul,
  pca_present_scores,
  pca_future_marjun_scores,
  pca_future_aprjul_scores,
  km_present,
  km_future_marjun,
  km_future_aprjul,
  present_clusters,
  future_marjun_clusters,
  future_aprjul_clusters,
  comparison_marjun,
  comparison_aprjul,
  alluvial_marjun,
  alluvial_aprjul,
  file = file.path(output_dir, "present_future_clustering_objects.RData")
)

############################
# 15. Final message
############################

cat("--------------------------------------------------\n")
cat("Present and future clustering workflow completed successfully.\n")
cat("Outputs saved in:", output_dir, "\n")
cat("--------------------------------------------------\n")