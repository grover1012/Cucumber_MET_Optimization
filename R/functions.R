# Helper functions for Cucumber MET optimization

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

std_county_name <- function(x) {
  x <- as.character(x)
  x <- gsub(" ", "_", x)
  x <- gsub("-", "_", x)
  x <- gsub("__+", "_", x)
  x <- gsub("^California_", "CA_", x)
  x <- gsub("^Florida_", "FL_", x)
  x <- gsub("^Michigan_", "MI_", x)
  x <- gsub("^North_Carolina_", "NC_", x)
  x <- gsub("^Ohio_", "OH_", x)
  x <- gsub("^Oklahoma_", "OK_", x)
  x <- gsub("^Oregon_", "OR_", x)
  x <- gsub("^Wisconsin_", "WI_", x)
  x <- gsub("San_Joaquin", "SanJoaquin", x)
  x
}

drop_bad_ecs <- function(W, cor_cutoff = 0.95) {
  W <- as.data.frame(W)
  W <- W[, sapply(W, is.numeric), drop = FALSE]
  nzv <- caret::nearZeroVar(W)
  if (length(nzv) > 0) W <- W[, -nzv, drop = FALSE]
  cm <- cor(W, use = "pairwise.complete.obs")
  high <- caret::findCorrelation(cm, cutoff = cor_cutoff, names = FALSE, exact = TRUE)
  if (length(high) > 0) W <- W[, -high, drop = FALSE]
  W
}

calc_cullis_h2 <- function(C, Vg) {
  if (is.null(C) || is.na(Vg) || Vg <= 0) return(NA_real_)
  n <- nrow(C)
  if (n < 2) return(NA_real_)
  pairs <- utils::combn(seq_len(n), 2)
  vdelta <- apply(pairs, 2, function(idx) {
    i <- idx[1]; j <- idx[2]
    C[i, i] + C[j, j] - 2 * C[i, j]
  })
  1 - mean(vdelta, na.rm = TRUE) / (2 * Vg)
}

trial_efficiency_index <- function(H2_s, E_s, H2_met, E_met = 21) {
  (H2_s / E_s) / (H2_met / E_met)
}

make_elbow_plot <- function(W_scaled, max_k = 10, title = "Elbow plot") {
  wss <- sapply(1:max_k, function(k) {
    set.seed(123)
    kmeans(W_scaled, centers = k, nstart = 50)$tot.withinss
  })
  df <- data.frame(k = 1:max_k, WSS = wss)
  ggplot(df, aes(k, WSS)) +
    geom_line() +
    geom_point(size = 2) +
    theme_bw(base_size = 13) +
    labs(title = title, x = "Number of clusters (k)", y = "Total within-cluster sum of squares")
}

make_pca_cluster_plot <- function(W_scaled, clusters, title = NULL) {
  pca <- prcomp(W_scaled, center = FALSE, scale. = FALSE)
  ve <- 100 * (pca$sdev^2 / sum(pca$sdev^2))
  scores <- as.data.frame(pca$x[, 1:2])
  colnames(scores) <- c("PC1", "PC2")
  scores$env <- rownames(W_scaled)
  scores$cluster <- factor(clusters[rownames(W_scaled)])
  p <- ggplot(scores, aes(PC1, PC2, color = cluster)) +
    geom_point(size = 3) +
    theme_bw(base_size = 14) +
    labs(title = title,
         x = sprintf("PC1 (%.1f%%)", ve[1]),
         y = sprintf("PC2 (%.1f%%)", ve[2]),
         color = "Cluster")
  list(plot = p, pca = pca, scores = scores, var_explained = ve)
}
