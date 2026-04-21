suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(sommer)
})

# -----------------------------
# 1) Read data
# -----------------------------
data <- read_excel("yld_env.xlsx")

# ensure proper types
data$genotype  <- as.factor(data$genotype)
data$replicate <- as.factor(data$replicate)
data$env       <- as.factor(data$env)

# -----------------------------
# 2) Cullis heritability function
# -----------------------------
cullis_h2 <- function(C22_g, Vg) {
  ng <- nrow(C22_g)
  
  pev_diff <- matrix(NA_real_, ng, ng)
  for (i in 1:ng) {
    for (j in 1:ng) {
      pev_diff[i, j] <- C22_g[i, i] + C22_g[j, j] - 2 * C22_g[i, j]
    }
  }
  
  av2 <- mean(pev_diff[lower.tri(pev_diff)], na.rm = TRUE)
  H2  <- 1 - (av2 / (2 * Vg))
  H2  <- min(max(H2, 0), 0.999)
  
  list(H2 = H2, av2 = av2)
}

# -----------------------------
# 3) Container
# -----------------------------
results_list <- list()

# -----------------------------
# 4) Loop over environments
# -----------------------------
for (e in levels(droplevels(data$env))) {
  
  df <- droplevels(data[data$env == e, , drop = FALSE])
  
  cat("\nProcessing env:", e, "\n")
  cat("Genotypes:", n_distinct(df$genotype), " | Rows:", nrow(df), "\n")
  
  if (n_distinct(df$genotype) < 2 || nrow(df) < 3) {
    cat("Skipping due to insufficient data.\n")
    next
  }
  
  # =====================================================
  # A) BLUE model
  # genotype fixed, replicate random
  # =====================================================
  fit_blue <- tryCatch({
    mmes(
      fixed       = yield ~ genotype,
      random      = ~ vsm(ism(replicate)),
      rcov        = ~ units,
      data        = df,
      verbose     = FALSE,
      dateWarning = FALSE
    )
  }, error = function(err) {
    cat("BLUE model error:", err$message, "\n")
    NULL
  })
  
  if (!is.null(fit_blue)) {
    # obtain predicted BLUEs for genotype fixed effects
    blue_pred <- tryCatch({
      predict.mmes(fit_blue, D = "genotype")
    }, error = function(err) NULL)
    
    if (!is.null(blue_pred) && !is.null(blue_pred$pvals)) {
      blue_df <- blue_pred$pvals %>%
        dplyr::select(genotype, predicted.value, std.error) %>%
        dplyr::rename(
          BLUE = predicted.value,
          SE_BLUE = std.error
        ) %>%
        mutate(
          genotype = as.character(genotype),
          env = as.character(e)
        )
    } else {
      blue_df <- NULL
    }
  } else {
    blue_df <- NULL
  }
  
  # =====================================================
  # B) BLUP model for true Cullis H2
  # genotype random, replicate random
  # =====================================================
  fit_blup <- tryCatch({
    mmes(
      fixed       = yield ~ 1,
      random      = ~ vsm(ism(genotype)) + vsm(ism(replicate)),
      rcov        = ~ units,
      data        = df,
      verbose     = FALSE,
      dateWarning = FALSE
    )
  }, error = function(err) {
    cat("BLUP model error:", err$message, "\n")
    NULL
  })
  
  if (!is.null(fit_blup)) {
    
    # genotype BLUPs + PEV matrix
    pred_blup <- tryCatch({
      predict.mmes(fit_blup, D = "genotype", compute.pev = TRUE)
    }, error = function(err) {
      cat("Prediction/PEV error:", err$message, "\n")
      NULL
    })
    
    if (!is.null(pred_blup) && !is.null(pred_blup$vcov)) {
      
      C22 <- pred_blup$vcov
      
      # extract genotype variance
      theta_names <- names(fit_blup$theta)
      vg_idx <- grep("^vsm\\(ism\\(genotype\\)\\)$", theta_names)
      
      if (length(vg_idx) == 0) {
        cat("Could not find genotype variance component.\n")
        blup_df <- NULL
      } else {
        Vg <- as.numeric(fit_blup$theta[[vg_idx[1]]])
        
        if (!is.finite(Vg) || Vg <= 0) {
          cat("Invalid genotype variance.\n")
          blup_df <- NULL
        } else {
          H2o <- cullis_h2(C22, Vg)
          
          # predicted BLUPs
          if (!is.null(pred_blup$pvals)) {
            blup_df <- pred_blup$pvals %>%
              dplyr::select(genotype, predicted.value) %>%
              dplyr::rename(BLUP = predicted.value) %>%
              mutate(
                genotype = as.character(genotype),
                env = as.character(e),
                H2_Cullis = H2o$H2
              )
          } else {
            blup_df <- NULL
          }
        }
      }
      
    } else {
      blup_df <- NULL
    }
    
  } else {
    blup_df <- NULL
  }
  
  # =====================================================
  # C) Merge BLUE + BLUP + H2
  # =====================================================
  if (!is.null(blue_df) && !is.null(blup_df)) {
    result <- merge(blue_df, blup_df, by = c("genotype", "env"))
    results_list[[as.character(e)]] <- result
    cat("Merged results for env:", e, "\n")
  } else {
    cat("Missing BLUE or BLUP for env:", e, "\n")
  }
}

# -----------------------------
# 5) Final combined results
# -----------------------------
results_df <- bind_rows(results_list)

# inspect
print(head(results_df))
str(results_df)

library(dplyr)

results.st1 <- results_df %>%
  left_join(
    clusters %>% select(env, cluster),
    by = "env"
  )
# optional save
# write.csv(results_df, "results_with_true_Cullis_H2.csv", row.names = FALSE)

###########################################################
# MET optimization scenarios
# Deterministic:
#   1) MET
#   2) MET_EC
# Replicated (50 reps):
#   3) WC_MET
#   4) OPT_MET
#   5) HT_MET
###########################################################


suppressPackageStartupMessages({
  library(sommer)
  library(dplyr)
  library(plyr)
  library(foreach)
  library(doParallel)
})

# =========================================================
# 0) USER INPUTS
# =========================================================
# Required objects:
# - results.st1 : columns env, genotype, BLUE, SE_BLUE, H2_Cullis, cluster
# - W.clean2    : env x EC matrix/data.frame, rownames = env
#
# replicated scenarios:
n_reps <- 50

# =========================================================
# 1) Build dat
# =========================================================
dat <- results.st1 %>%
  transmute(
    env       = as.character(env),
    genotype  = as.character(genotype),
    BLUE      = BLUE,
    SE_BLUE   = SE_BLUE,
    w         = ifelse(is.na(SE_BLUE) | SE_BLUE <= 0, 1, 1 / (SE_BLUE^2)),
    cluster   = as.character(cluster),
    H2_Cullis = H2_Cullis
  ) %>%
  filter(env %in% rownames(W.clean2))

# metadata per environment
env_meta <- dat %>%
  distinct(env, cluster, H2_Cullis)

# EC matrix
W.ec.full <- as.matrix(W.clean2)
storage.mode(W.ec.full) <- "numeric"

# keep only envs in dat
W.ec.full <- W.ec.full[rownames(W.ec.full) %in% unique(dat$env), , drop = FALSE]

# =========================================================
# 2) Cullis heritability helper
# =========================================================
cullis_h2 <- function(C22_g, Vg) {
  ng <- nrow(C22_g)
  pev_diff <- matrix(NA_real_, ng, ng)
  
  for (i in 1:ng) {
    for (j in 1:ng) {
      pev_diff[i, j] <- C22_g[i, i] + C22_g[j, j] - 2 * C22_g[i, j]
    }
  }
  
  av2 <- mean(pev_diff[lower.tri(pev_diff)], na.rm = TRUE)
  H2  <- 1 - (av2 / (2 * Vg))
  H2  <- min(max(H2, 0), 0.999)
  
  list(H2 = H2, av2 = av2)
}

# =========================================================
# 3) Utility: baseline MET fit
# =========================================================
fit_met <- function(df) {
  out <- tryCatch({
    df <- df %>%
      mutate(
        genotype = as.factor(genotype),
        env      = as.factor(env)
      )
    
    fit <- mmes(
      fixed       = BLUE ~ env,
      random      = ~ vsm(ism(genotype)) + vsm(ism(genotype:env)),
      rcov        = ~ units,
      W           = diag(df$w),
      data        = df,
      verbose     = FALSE,
      dateWarning = FALSE
    )
    
    pred <- predict.mmes(fit, D = "genotype", compute.pev = TRUE)
    C22  <- pred$vcov
    if (is.null(C22)) return(NULL)
    
    Vg  <- as.numeric(fit$theta[["vsm(ism(genotype))"]])
    Vge <- as.numeric(fit$theta[["vsm(ism(genotype:env))"]])
    Vu  <- as.numeric(fit$theta[["units"]])
    
    if (!all(is.finite(c(Vg, Vge, Vu))) || Vg <= 0) return(NULL)
    
    H2o <- cullis_h2(C22, Vg)
    totalVar <- Vg + Vge + Vu
    
    data.frame(
      Trials    = length(unique(df$env)),
      Vg        = Vg,
      Vge       = Vge,
      Vu        = Vu,
      VgScaled  = Vg / totalVar,
      VgeScaled = Vge / totalVar,
      VuScaled  = Vu / totalVar,
      H.cullis  = H2o$H2
    )
  }, error = function(e) NULL)
  
  out
}

# =========================================================
# 4) Utility: deterministic MET_EC fit
# =========================================================
fit_met_ec <- function(df, W.ec) {
  out <- tryCatch({
    df <- df %>%
      mutate(
        env      = as.character(env),
        genotype = as.character(genotype)
      )
    
    env_levels <- unique(df$env)
    g_levels   <- sort(unique(df$genotype))
    
    W.ec <- as.matrix(W.ec)
    storage.mode(W.ec) <- "numeric"
    W.ec <- W.ec[match(env_levels, rownames(W.ec)), , drop = FALSE]
    
    if (any(is.na(rownames(W.ec)))) return(NULL)
    if (!all(rownames(W.ec) == env_levels)) return(NULL)
    
    keep_cols <- apply(W.ec, 2, function(x) {
      all(is.finite(x)) && sd(x, na.rm = TRUE) > 0
    })
    W.ec <- W.ec[, keep_cols, drop = FALSE]
    
    if (nrow(W.ec) < 2 || ncol(W.ec) < 1) return(NULL)
    
    Ekinship <- env_kernel(
      env.data  = W.ec,
      is.scaled = TRUE,
      gaussian  = TRUE,
      sd.tol    = 5
    )[[2]]
    
    if (is.null(Ekinship) || any(!is.finite(Ekinship))) return(NULL)
    
    rownames(Ekinship) <- env_levels
    colnames(Ekinship) <- env_levels
    
    GxE_levels <- paste0(
      rep(env_levels, times = length(g_levels)),
      "__",
      rep(g_levels, each = length(env_levels))
    )
    
    df <- df %>%
      mutate(
        GxE = paste0(env, "__", genotype),
        genotype = factor(genotype, levels = g_levels),
        env      = factor(env, levels = env_levels),
        GxE      = factor(GxE, levels = GxE_levels)
      )
    
    Gi <- diag(length(g_levels))
    rownames(Gi) <- colnames(Gi) <- g_levels
    
    Kgxe <- kronecker(Gi, Ekinship)
    rownames(Kgxe) <- colnames(Kgxe) <- GxE_levels
    
    fit <- mmes(
      fixed       = BLUE ~ env,
      random      = ~ vsm(ism(genotype)) + vsm(ism(GxE), Gu = Kgxe),
      rcov        = ~ units,
      W           = diag(df$w),
      data        = df,
      verbose     = FALSE,
      dateWarning = FALSE
    )
    
    pred <- predict.mmes(fit, D = "genotype", compute.pev = TRUE)
    C22  <- pred$vcov
    if (is.null(C22)) return(NULL)
    
    theta_names <- names(fit$theta)
    vg_idx  <- grep("^vsm\\(ism\\(genotype\\)\\)$", theta_names)
    vge_idx <- grep("GxE", theta_names)
    vu_idx  <- grep("^units$", theta_names)
    
    if (length(vg_idx) == 0 || length(vge_idx) == 0 || length(vu_idx) == 0) return(NULL)
    
    Vg  <- as.numeric(fit$theta[[vg_idx[1]]])
    Vge <- as.numeric(fit$theta[[vge_idx[1]]])
    Vu  <- as.numeric(fit$theta[[vu_idx[1]]])
    
    if (!all(is.finite(c(Vg, Vge, Vu))) || Vg <= 0) return(NULL)
    
    H2o <- cullis_h2(C22, Vg)
    totalVar <- Vg + Vge + Vu
    
    data.frame(
      Trials    = length(unique(df$env)),
      Vg        = Vg,
      Vge       = Vge,
      Vu        = Vu,
      VgScaled  = Vg / totalVar,
      VgeScaled = Vge / totalVar,
      VuScaled  = Vu / totalVar,
      H.cullis  = H2o$H2
    )
  }, error = function(e) NULL)
  
  out
}

# =========================================================
# 5) Helpers for replicated scenarios
# =========================================================
make_boot_map <- function(envs, prefix = "boot") {
  sampled <- sample(envs, length(envs), replace = TRUE)
  data.frame(
    env_orig = sampled,
    env_boot = paste0(sampled, "__", prefix, "_", seq_along(sampled)),
    stringsAsFactors = FALSE
  )
}

apply_boot_map <- function(df, boot_map) {
  out <- lapply(seq_len(nrow(boot_map)), function(i) {
    sub <- df[df$env == boot_map$env_orig[i], , drop = FALSE]
    sub$env <- boot_map$env_boot[i]
    sub
  })
  bind_rows(out)
}

# =========================================================
# 6) Scenario 1: MET (deterministic full-data)
# =========================================================
MET <- fit_met(dat) %>%
  mutate(
    Rep = "1",
    Scenario = "MET"
  )

print(MET)

# =========================================================
# 7) Scenario 2: MET_EC (deterministic full-data)
# =========================================================
env_levels <- unique(dat$env)
W.ec <- W.ec.full[match(env_levels, rownames(W.ec.full)), , drop = FALSE]

MET_EC <- fit_met_ec(dat, W.ec) %>%
  mutate(
    Rep = "1",
    Scenario = "MET_EC"
  )

print(MET_EC)

# =========================================================
# 8) Parallel setup for replicated scenarios
# =========================================================
ncores <- max(1, parallel::detectCores() - 1)
cl <- makeCluster(ncores)
registerDoParallel(cl)

# =========================================================
# =========================================================
# Scenario 3: WC_MET (deterministic)
# Fit within each cluster using the actual environments
# =========================================================
WC_MET_cluster <- lapply(split(dat, dat$cluster), function(sub) {
  sub <- droplevels(sub)
  fit_met(sub)
})

WC_MET_cluster <- WC_MET_cluster[!sapply(WC_MET_cluster, is.null)]
WC_MET_cluster <- bind_rows(WC_MET_cluster)

# average cluster-level metrics into one scenario summary
WC_MET <- data.frame(
  Trials    = mean(WC_MET_cluster$Trials, na.rm = TRUE),
  Vg        = mean(WC_MET_cluster$Vg, na.rm = TRUE),
  Vge       = mean(WC_MET_cluster$Vge, na.rm = TRUE),
  Vu        = mean(WC_MET_cluster$Vu, na.rm = TRUE),
  VgScaled  = mean(WC_MET_cluster$VgScaled, na.rm = TRUE),
  VgeScaled = mean(WC_MET_cluster$VgeScaled, na.rm = TRUE),
  VuScaled  = mean(WC_MET_cluster$VuScaled, na.rm = TRUE),
  H.cullis  = mean(WC_MET_cluster$H.cullis, na.rm = TRUE),
  Rep       = "1",
  Scenario  = "WC_MET"
)

print(WC_MET)
print(WC_MET_cluster)

# =========================================================
# 10) Scenario 4: OPT_MET
# Randomly choose 1 env per cluster each replicate
# =========================================================
OPT_MET_list <- foreach(
  i = 1:n_reps,
  .packages = c("sommer", "dplyr"),
  .errorhandling = "pass"
) %dopar% {
  
  chosen_envs <- env_meta %>%
    group_by(cluster) %>%
    summarise(env = sample(env, 1), .groups = "drop") %>%
    pull(env)
  
  sub <- droplevels(dat[dat$env %in% chosen_envs, , drop = FALSE])
  
  out <- fit_met(sub)
  if (is.null(out)) return(NULL)
  
  out$Rep <- as.character(i)
  out$Scenario <- "OPT_MET"
  out
}

OPT_MET_list <- OPT_MET_list[!sapply(OPT_MET_list, is.null)]
OPT_MET <- if (length(OPT_MET_list) > 0) bind_rows(OPT_MET_list) else data.frame()

# =========================================================
# 11) Scenario 5: HT_MET
# Use existing H2_Cullis values, bootstrap candidates within each
# cluster, then choose the highest-H2 environment among sampled candidates
# =========================================================
HT_MET_list <- foreach(
  i = 1:n_reps,
  .packages = c("sommer", "dplyr"),
  .errorhandling = "pass"
) %dopar% {
  
  chosen_envs <- lapply(split(env_meta, env_meta$cluster), function(x) {
    sampled <- sample(x$env, nrow(x), replace = TRUE)
    x %>%
      filter(env %in% sampled) %>%
      arrange(desc(H2_Cullis), env) %>%
      slice(1) %>%
      pull(env)
  }) %>%
    unlist(use.names = FALSE)
  
  sub <- droplevels(dat[dat$env %in% chosen_envs, , drop = FALSE])
  
  out <- fit_met(sub)
  if (is.null(out)) return(NULL)
  
  out$Rep <- as.character(i)
  out$Scenario <- "HT_MET"
  out
}

HT_MET_list <- HT_MET_list[!sapply(HT_MET_list, is.null)]
HT_MET <- if (length(HT_MET_list) > 0) bind_rows(HT_MET_list) else data.frame()

stopCluster(cl)

# =========================================================
# 12) Check successful runs
# =========================================================
cat("\nSuccessful runs:\n")
cat("MET    :", ifelse(is.null(MET), 0, nrow(MET)), "\n")
cat("MET_EC :", ifelse(is.null(MET_EC), 0, nrow(MET_EC)), "\n")
cat("WC_MET :", ifelse(is.null(WC_MET), 0, nrow(WC_MET)), "\n")
cat("OPT_MET:", ifelse(is.null(OPT_MET), 0, nrow(OPT_MET)), "\n")
cat("HT_MET :", ifelse(is.null(HT_MET), 0, nrow(HT_MET)), "\n")

# =========================================================
# 13) Final combined object
# =========================================================
standardize_result <- function(x, scenario_name = NULL) {
  if (is.null(x) || nrow(as.data.frame(x)) == 0) return(NULL)
  
  x <- as.data.frame(x)
  
  if (!"Rep" %in% names(x)) {
    x$Rep <- "1"
  } else {
    x$Rep <- as.character(x$Rep)
  }
  
  if (!"Scenario" %in% names(x)) {
    x$Scenario <- scenario_name
  } else {
    x$Scenario <- as.character(x$Scenario)
  }
  
  x
}

MET2    <- standardize_result(MET, "MET")
MET_EC2 <- standardize_result(MET_EC, "MET_EC")
WC_MET2 <- standardize_result(WC_MET, "WC_MET")
OPT_MET2 <- standardize_result(OPT_MET, "OPT_MET")
HT_MET2 <- standardize_result(HT_MET, "HT_MET")

final_main <- dplyr::bind_rows(
  MET2,
  MET_EC2,
  WC_MET2,
  OPT_MET2,
  HT_MET2
)

final_main$Scenario <- factor(
  final_main$Scenario,
  levels = c("MET", "MET_EC", "WC_MET", "OPT_MET", "HT_MET")
)

print(final_main %>% dplyr::count(Scenario))

# =========================================================
# 14) Summary table
# =========================================================
final_tab <- final_main %>%
  group_by(Scenario) %>%
  summarise(
    N         = n(),
    Mean_H2   = mean(H.cullis, na.rm = TRUE),
    SD_H2     = sd(H.cullis, na.rm = TRUE),
    Mean_Vg   = mean(Vg, na.rm = TRUE),
    Mean_Vge  = mean(Vge, na.rm = TRUE),
    Mean_Vu   = mean(Vu, na.rm = TRUE),
    Mean_Trials = mean(Trials, na.rm = TRUE),
    .groups = "drop"
  )

print(final_tab)

# =========================================================
# 15) Optional save
# =========================================================
# write.csv(final_main, "MET_strategy_comparison_full.csv", row.names = FALSE)
# write.csv(final_tab, "MET_strategy_comparison_summary.csv", row.names = FALSE)

# -----------------------------
# 2) Separate replicated vs deterministic
# -----------------------------
rep_dat <- final_main %>%
  filter(Scenario %in% c("HT_MET", "OPT_MET"))

ref_dat <- final_main %>%
  filter(Scenario %in% c("MET", "MET_EC", "WC_MET")) %>%
  distinct(Scenario, H.cullis, Trials)

# -----------------------------
# 3) Significance testing among replicated strategies only
# -----------------------------
kw_res <- kruskal_test(rep_dat, H.cullis ~ Scenario)
print(kw_res)

dunn_res <- dunn_test(
  rep_dat,
  H.cullis ~ Scenario,
  p.adjust.method = "bonferroni"
)

print(dunn_res)

y_max <- max(rep_dat$H.cullis, na.rm = TRUE)

dunn_res <- dunn_res %>%
  mutate(
    y.position = seq(y_max + 0.02, y_max + 0.02 + 0.03 * (n() - 1), by = 0.03),
    p.label = paste0("p = ", signif(p.adj, 3))
  )

# -----------------------------
# 4) Colors
# -----------------------------
scenario_cols <- c(
  "MET"    = "#4C78A8",
  "MET_EC" = "#E45756",
  "WC_MET" = "#72B7B2",
  "OPT_MET"= "#F58518",
  "HT_MET" = "#54A24B"
)

# -----------------------------
# 5) Plot
# -----------------------------
p_compare <- ggplot() +
  
  # violin for replicated strategies
  geom_violin(
    data = rep_dat,
    aes(x = Scenario, y = H.cullis, fill = Scenario),
    trim = FALSE,
    alpha = 0.35,
    color = "black"
  ) +
  
  # boxplot
  geom_boxplot(
    data = rep_dat,
    aes(x = Scenario, y = H.cullis, fill = Scenario),
    width = 0.14,
    outlier.shape = NA,
    alpha = 0.65,
    color = "black"
  ) +
  
  # jittered points
  geom_jitter(
    data = rep_dat,
    aes(x = Scenario, y = H.cullis),
    width = 0.08,
    size = 2.0,
    alpha = 0.55,
    color = "black"
  ) +
  
  # mean points for replicated strategies
  stat_summary(
    data = rep_dat,
    aes(x = Scenario, y = H.cullis),
    fun = mean,
    geom = "point",
    size = 4,
    color = "darkred"
  ) +
  
  # deterministic reference points
  geom_point(
    data = ref_dat,
    aes(x = Scenario, y = H.cullis, fill = Scenario),
    shape = 23,
    size = 5.5,
    color = "black",
    stroke = 1.2
  ) +
  
  # labels for deterministic strategies
  geom_text(
    data = ref_dat,
    aes(x = Scenario, y = H.cullis, label = sprintf("%.3f", H.cullis)),
    vjust = -1.0,
    size = 4
  ) +
  
  # significance
  stat_pvalue_manual(
    dunn_res,
    label = "p.label",
    xmin = "group1",
    xmax = "group2",
    y.position = "y.position",
    tip.length = 0.01,
    size = 3.5
  ) +
  
  scale_fill_manual(values = scenario_cols, drop = FALSE) +
  
  labs(
    title = "Comparison of MET optimization strategies",
    subtitle = paste0(
      "Replicated strategies compared by Kruskal-Wallis (p = ",
      signif(kw_res$p, 3),
      "); MET and MET_EC shown as deterministic benchmarks"
    ),
    x = "Strategy",
    y = "Cullis heritability"
  ) +
  
  theme_bw(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    axis.title = element_text(face = "bold"),
    legend.position = "none",
    panel.grid.minor = element_blank()
  )

print(p_compare)

# -----------------------------
# 6) Save
# -----------------------------
ggsave(
  "Strategy_comparison_H2.png",
  p_compare,
  width = 11,
  height = 8.5,
  dpi = 600,
  bg = "white"
)

ggsave(
  "Strategy_comparison_H2.pdf",
  p_compare,
  width = 11,
  height = 8.5,
  device = cairo_pdf
)