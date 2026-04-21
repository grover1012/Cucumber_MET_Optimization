# 06_production_importance_and_recommendations.R
# USDA production importance and cluster-based trial recommendations

source("R/functions.R")
library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)

usda <- read_csv("Data/raw/usda_pickling_cucumber_county_area.csv", show_col_types = FALSE)

usda_clean <- usda %>%
  rename_with(tolower) %>%
  mutate(
    state_county = std_county_name(paste(state, county, sep = "_")),
    harvested_area_acres = as.numeric(harvested_area_acres)
  ) %>%
  filter(!is.na(harvested_area_acres), harvested_area_acres > 0) %>%
  arrange(desc(harvested_area_acres)) %>%
  mutate(
    cum_area = cumsum(harvested_area_acres),
    cum_pct = 100 * cum_area / sum(harvested_area_acres),
    keep_95 = cum_pct <= 95 | row_number() == which(cum_pct >= 95)[1]
  )

major11 <- usda_clean %>%
  filter(keep_95) %>%
  mutate(PI = 100 * harvested_area_acres / sum(harvested_area_acres))

write_csv(major11, "Output/tables/major_counties_production_importance.csv")

present_clusters <- read_csv("Output/tables/Present_counties_k3_clusters.csv", show_col_types = FALSE) %>%
  mutate(state_county = std_county_name(env))

hist_trials <- tibble::tibble(
  state_county = std_county_name(c(
    "Florida_Lake", "North_Carolina_Wake", "Oklahoma_Wagoner", "Ohio_Henry",
    "Michigan_Ingham", "Wisconsin_Waushara", "Oregon_Marion"
  )),
  historical_trial = TRUE
)

county_frame <- present_clusters %>%
  left_join(major11 %>% select(state_county, harvested_area_acres, PI), by = "state_county") %>%
  left_join(hist_trials, by = "state_county") %>%
  mutate(
    historical_trial = ifelse(is.na(historical_trial), FALSE, historical_trial),
    PI = ifelse(is.na(PI), 0, PI)
  )

cluster_summary <- county_frame %>%
  group_by(cluster) %>%
  summarise(
    production_importance = sum(PI, na.rm = TRUE),
    trial_allocation = 100 * sum(historical_trial) / sum(county_frame$historical_trial),
    n_counties = n(),
    .groups = "drop"
  )

write_csv(county_frame, "Output/tables/county_recommendation_frame.csv")
write_csv(cluster_summary, "Output/tables/cluster_PI_TA_summary.csv")

message("Production importance and recommendation summaries complete.")
