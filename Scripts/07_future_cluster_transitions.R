# 07_future_cluster_transitions.R
# Present vs future cluster transitions and alluvial plot

source("R/functions.R")
library(dplyr)
library(readr)
library(ggplot2)
library(ggalluvial)

present <- read_csv("Output/tables/Present_counties_k3_clusters.csv", show_col_types = FALSE) %>%
  transmute(env_std = std_county_name(env), Present_AJ = as.character(cluster))

future_mj <- read_csv("Output/tables/Future_Mar_Jun_k3_clusters.csv", show_col_types = FALSE) %>%
  transmute(env_std = std_county_name(env), Future_MJ = as.character(cluster))

future_aj <- read_csv("Output/tables/Future_Apr_Jul_k3_clusters.csv", show_col_types = FALSE) %>%
  transmute(env_std = std_county_name(env), Future_AJ = as.character(cluster))

alluvial_df <- present %>%
  inner_join(future_mj, by = "env_std") %>%
  inner_join(future_aj, by = "env_std")

write_csv(alluvial_df, "Output/tables/alluvial_present_future_clusters.csv")

p <- ggplot(alluvial_df,
            aes(axis1 = Future_MJ, axis2 = Present_AJ, axis3 = Future_AJ)) +
  geom_alluvium(aes(fill = Present_AJ), width = 1/12, alpha = 0.8) +
  geom_stratum(width = 1/12, color = "black", fill = "grey95") +
  geom_text(stat = "stratum", aes(label = after_stat(stratum)), size = 4) +
  scale_x_discrete(
    limits = c("Future_MJ", "Present_AJ", "Future_AJ"),
    labels = c("Future: Mar-Jun\\n(2050-2065)",
               "Present: Apr-Jul\\n(2010-2025)",
               "Future: Apr-Jul\\n(2050-2065)"),
    expand = c(.05, .05)
  ) +
  theme_bw(base_size = 14) +
  labs(x = NULL, y = "Counties", fill = "Present cluster",
       title = "Cluster transitions between present and future scenarios")

ggsave("Figures/alluvial_present_future_clusters.png", p, width = 10, height = 6, dpi = 600)
ggsave("Figures/alluvial_present_future_clusters.pdf", p, width = 10, height = 6, device = cairo_pdf)

message("Alluvial plot complete.")
