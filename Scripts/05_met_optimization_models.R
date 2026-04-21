# 05_met_optimization_models.R
# Fit MET, MET_EC, WC_MET, OPT_MET, and HT_MET models

source("R/functions.R")
library(dplyr)
library(readr)
library(sommer)

mlt <- read_csv("Data/processed/mlt_clean.csv", show_col_types = FALSE)
clusters <- read_csv("Output/tables/MLT_k3_clusters.csv", show_col_types = FALSE)

mlt <- mlt %>%
  left_join(clusters, by = "env") %>%
  mutate(genotype = factor(genotype), env = factor(env), cluster = factor(cluster))

# Baseline MET
fit_met <- mmes(
  fixed = GY ~ env,
  random = ~ vsm(ism(genotype)) + vsm(ism(genotype:env)),
  rcov = ~ units,
  data = mlt,
  verbose = FALSE
)
saveRDS(fit_met, "Output/models/fit_MET.rds")
write.csv(summary(fit_met)$varcomp, "Output/tables/varcomp_MET.csv")

# WC_MET
wc_results <- list()
for (cl in levels(mlt$cluster)) {
  dat_cl <- filter(mlt, cluster == cl)
  if (n_distinct(dat_cl$env) < 2) next
  wc_results[[cl]] <- mmes(
    fixed = GY ~ env,
    random = ~ vsm(ism(genotype)) + vsm(ism(genotype:env)),
    rcov = ~ units,
    data = dat_cl,
    verbose = FALSE
  )
}
saveRDS(wc_results, "Output/models/fits_WC_MET.rds")

# MET_EC:
# Add final working code here using the 14 selected ECs and a location-level Gaussian environmental kernel.
# The exact sommer syntax depends on the final Gu object and row ordering used in the analysis.

# OPT_MET and HT_MET require environment-level Cullis H2 table:
# Output/tables/environment_level_H2.csv with columns: env,H2_Cullis
if (file.exists("Output/tables/environment_level_H2.csv")) {
  env_h2 <- read_csv("Output/tables/environment_level_H2.csv", show_col_types = FALSE)
  cl_h2 <- clusters %>% left_join(env_h2, by = "env")

  set.seed(123)
  nrep <- 100

  fit_reduced <- function(selected_envs) {
    dat <- filter(mlt, env %in% selected_envs) %>% droplevels()
    mmes(
      fixed = GY ~ env,
      random = ~ vsm(ism(genotype)) + vsm(ism(genotype:env)),
      rcov = ~ units,
      data = dat,
      verbose = FALSE
    )
  }

  opt_fits <- vector("list", nrep)
  for (r in seq_len(nrep)) {
    selected <- clusters %>%
      group_by(cluster) %>%
      slice_sample(n = 1) %>%
      pull(env)
    opt_fits[[r]] <- fit_reduced(selected)
  }
  saveRDS(opt_fits, "Output/models/fits_OPT_MET.rds")

  ht_selected <- cl_h2 %>%
    group_by(cluster) %>%
    arrange(desc(H2_Cullis)) %>%
    slice(1) %>%
    pull(env)

  fit_ht <- fit_reduced(ht_selected)
  saveRDS(fit_ht, "Output/models/fit_HT_MET.rds")
  write_csv(data.frame(env = ht_selected), "Output/tables/HT_MET_selected_envs.csv")
}

message("MET optimization model script complete.")
