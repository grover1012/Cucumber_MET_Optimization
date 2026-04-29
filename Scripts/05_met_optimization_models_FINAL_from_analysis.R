suppressPackageStartupMessages({
  library(sommer)
  library(dplyr)
  library(plyr)
  library(foreach)
  library(doParallel)
  library(ggplot2)
})

# =========================================================
# 0) USER INPUTS
# =========================================================
n_reps <- 10

# =========================================================
# 1) Build dat
# =========================================================
dat <- results.st2 %>%
  transmute(
    env       = as.character(env),
    genotype  = as.character(genotype),
    BLUE      = as.numeric(BLUE),
    SE_BLUE   = as.numeric(SE_BLUE),
    w         = ifelse(is.na(SE_BLUE) | SE_BLUE <= 0, 1, 1 / (SE_BLUE^2)),
    cluster   = as.character(cluster),
    H2_Cullis = as.numeric(H2_Cullis)
  ) %>%
  filter(env %in% rownames(W.clean2))

# metadata per environment
env_meta <- dat %>%
  distinct(env, cluster, H2_Cullis)

# EC matrix
W.ec.full <- as.data.frame(W.clean2)

# remove accidental env column if present
if ("env" %in% colnames(W.ec.full)) {
  W.ec.full <- W.ec.full[, colnames(W.ec.full) != "env", drop = FALSE]
}

# keep only numeric columns
W.ec.full <- W.ec.full[, sapply(W.ec.full, is.numeric), drop = FALSE]

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
  }, error = function(e) {
    message("fit_met error: ", e$message)
    NULL
  })
  
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
    
    if ("env" %in% colnames(W.ec)) {
      W.ec <- W.ec[, colnames(W.ec) != "env", drop = FALSE]
    }
    
    W.ec <- W.ec[, sapply(as.data.frame(W.ec), is.numeric), drop = FALSE]
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
  }, error = function(e) {
    message("fit_met_ec error: ", e$message)
    NULL
  })
  
  out
}

# =========================================================
# 5) Scenario 1: MET (deterministic full-data)
# =========================================================
MET <- fit_met(dat)

if (!is.null(MET)) {
  MET <- MET %>%
    mutate(
      Rep = "1",
      Scenario = "MET"
    )
}

print(MET)

# =========================================================
# 6) Scenario 2: MET_EC (deterministic full-data)
# =========================================================
env_levels <- unique(dat$env)

W.ec <- W.ec.full[match(env_levels, rownames(W.ec.full)), , drop = FALSE]

MET_EC_fit <- fit_met_ec(dat, W.ec)

if (is.null(MET_EC_fit)) {
  message("MET_EC fit returned NULL")
  MET_EC <- NULL
} else {
  MET_EC <- MET_EC_fit %>%
    mutate(
      Rep = "1",
      Scenario = "MET_EC"
    )
}

print(MET_EC)

# =========================================================
# 7) Scenario 3: WC_MET (deterministic)
# Fit within each cluster using the actual environments
# =========================================================
WC_MET_cluster <- lapply(split(dat, dat$cluster), function(sub) {
  sub <- droplevels(sub)
  fit_met(sub)
})

WC_MET_cluster <- WC_MET_cluster[!sapply(WC_MET_cluster, is.null)]

if (length(WC_MET_cluster) > 0) {
  WC_MET_cluster <- bind_rows(WC_MET_cluster)
  
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
} else {
  WC_MET <- NULL
}

print(WC_MET)

# =========================================================
# 8) Scenario 4: OPT_MET
# Randomly choose 1 env per cluster each replicate
# =========================================================
ncores <- max(1, parallel::detectCores() - 1)
cl <- makeCluster(ncores)
registerDoParallel(cl)

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

stopCluster(cl)

OPT_MET_list <- OPT_MET_list[!sapply(OPT_MET_list, is.null)]
OPT_MET <- if (length(OPT_MET_list) > 0) bind_rows(OPT_MET_list) else NULL

print(OPT_MET)

# =========================================================
# 9) Scenario 5: HT_MET
# Deterministic: choose the highest-H2 environment per cluster
# =========================================================
best_envs <- env_meta %>%
  group_by(cluster) %>%
  arrange(desc(H2_Cullis), env) %>%
  slice(1) %>%
  ungroup()

print(best_envs)

chosen_envs <- best_envs$env

sub_ht <- droplevels(
  dat[dat$env %in% chosen_envs, , drop = FALSE]
)

HT_MET <- fit_met(sub_ht)

if (!is.null(HT_MET)) {
  HT_MET <- HT_MET %>%
    mutate(
      Rep = "1",
      Scenario = "HT_MET"
    )
}

print(HT_MET)

# =========================================================
# 10) Final combined object
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

MET2     <- standardize_result(MET, "MET")
MET_EC2  <- standardize_result(MET_EC, "MET_EC")
WC_MET2  <- standardize_result(WC_MET, "WC_MET")
OPT_MET2 <- standardize_result(OPT_MET, "OPT_MET")
HT_MET2  <- standardize_result(HT_MET, "HT_MET")

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
# 11) Summary table
final_tab1 <- final_main %>%
  dplyr::group_by(Scenario) %>%
  dplyr::summarise(
    N           = dplyr::n(),
    Mean_H2     = mean(H.cullis, na.rm = TRUE),
    SD_H2       = sd(H.cullis, na.rm = TRUE),
    Mean_Vg     = mean(Vg, na.rm = TRUE),
    Mean_Vge    = mean(Vge, na.rm = TRUE),
    Mean_Vu     = mean(Vu, na.rm = TRUE),
    Mean_Trials = mean(Trials, na.rm = TRUE),
    .groups = "drop"
  )

print(final_tab1)

# =========================================================
# 12) Plot data
# Deterministic scenarios = single bars
# OPT_MET = mean bar + SD error bar + points
# =========================================================

det_plot <- final_main %>%
  filter(Scenario %in% c("MET", "MET_EC", "WC_MET", "HT_MET")) %>%
  distinct(Scenario, H.cullis)

opt_plot <- final_main %>%
  filter(Scenario == "OPT_MET")

opt_summary <- opt_plot %>%
  summarise(
    Scenario = "OPT_MET",
    Mean_H2 = mean(H.cullis, na.rm = TRUE),
    SD_H2   = sd(H.cullis, na.rm = TRUE)
  )

det_plot <- det_plot %>%
  dplyr::mutate(
    Mean_H2 = H.cullis,
    SD_H2 = NA_real_
  ) %>%
  dplyr::select(Scenario, Mean_H2, SD_H2)

plot_summary <- bind_rows(det_plot, opt_summary)

# =========================================================
# 13) Plot
# =========================================================
scenario_cols <- c(
  "MET"    = "#4C78A8",
  "MET_EC" = "#E45756",
  "WC_MET" = "#72B7B2",
  "OPT_MET"= "#F58518",
  "HT_MET" = "#54A24B"
)

p_compare <- ggplot(plot_summary, aes(x = Scenario, y = Mean_H2, fill = Scenario)) +
  geom_col(color = "black", width = 0.7) +
  geom_errorbar(
    data = opt_summary,
    aes(ymin = Mean_H2 - SD_H2, ymax = Mean_H2 + SD_H2),
    width = 0.15,
    size = 0.8
  ) +
  geom_text(
    aes(label = sprintf("%.3f", Mean_H2)),
    vjust = -0.8,
    size = 4
  ) +
  scale_fill_manual(values = scenario_cols, drop = FALSE) +
  labs(
    title = "Comparison of MET optimization strategies",
    subtitle = "OPT_MET shown with replicate points and SD; all other strategies are deterministic",
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

# =========================================================
# 14) Save
# =========================================================
ggsave(
  "Strategy_comparison_H2_barplot.png",
  p_compare,
  width = 10,
  height = 7.5,
  dpi = 600,
  bg = "white"
)

ggsave(
  "Strategy_comparison_H2_barplot.pdf",
  p_compare,
  width = 10,
  height = 7.5,
  device = cairo_pdf
)
