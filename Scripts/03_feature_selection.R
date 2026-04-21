# 03_feature_selection.R
# Identify yield-associated ECs using stepwise regression and repeated RFE

source("R/functions.R")
library(dplyr)
library(readr)
library(caret)
library(olsrr)
library(MASS)
library(car)

mlt <- read_csv("Data/processed/mlt_clean.csv", show_col_types = FALSE)
myt <- read_csv("Data/processed/myt_clean.csv", show_col_types = FALSE)
ec_all <- read_csv("Data/processed/ec_all_stage_aggregated.csv", show_col_types = FALSE)

mlt_env_yield <- mlt %>%
  group_by(env, state_county, year) %>%
  summarise(GY = mean(GY, na.rm = TRUE), .groups = "drop")

myt_env_yield <- myt %>%
  group_by(env, state_county, year) %>%
  summarise(GY = mean(GY, na.rm = TRUE), .groups = "drop")

mlt_dat <- mlt_env_yield %>% left_join(ec_all, by = c("state_county", "year"))
myt_dat <- myt_env_yield %>% left_join(ec_all, by = c("state_county", "year"))

id_cols <- c("env", "state_county", "year", "GY")
W_mlt_clean <- drop_bad_ecs(mlt_dat %>% select(-any_of(id_cols)), 0.95)
W_myt_clean <- drop_bad_ecs(myt_dat %>% select(-any_of(id_cols)), 0.95)

mlt_rfe <- bind_cols(W_mlt_clean, GY = mlt_dat$GY) %>% na.omit()
myt_rfe <- bind_cols(W_myt_clean, GY = myt_dat$GY) %>% na.omit()

# MLT: stepwise linear regression
full.model <- lm(GY ~ ., data = mlt_rfe)
step.model <- ols_step_both_p(full.model)
final_model <- step.model$model
final_predictors_mlt <- attr(terms(final_model), "term.labels")

set.seed(123)
train_control <- trainControl(method = "cv", number = 10)
cv_model <- train(formula(final_model), data = mlt_rfe,
                  method = "lm", trControl = train_control, metric = "RMSE")

trimmed <- stepAIC(final_model, direction = "backward", trace = FALSE)

write_csv(data.frame(Predictor = final_predictors_mlt),
          "Output/tables/final_predictors_stepwise_MLT.csv")

sink("Output/tables/cv_results_stepwise_MLT.txt")
print(cv_model)
print(summary(final_model))
print(car::vif(trimmed))
sink()

# MYT: repeated RFE
control <- rfeControl(functions = lmFuncs, method = "cv",
                      number = 10, verbose = FALSE, allowParallel = FALSE)
predictor_list <- list()
set.seed(123)

for (i in 1:50) {
  opt.reg <- rfe(
    x = myt_rfe[, 1:(ncol(myt_rfe)-1)],
    y = myt_rfe$GY,
    sizes = c(1:10),
    metric = "Rsquared",
    maximize = TRUE,
    rfeControl = control
  )
  predictor_list[[i]] <- predictors(opt.reg)
}

predictor_freq <- sort(table(unlist(predictor_list)), decreasing = TRUE)
predictor_freq_df <- as.data.frame(predictor_freq)
colnames(predictor_freq_df) <- c("Predictor", "Frequency")
write_csv(predictor_freq_df, "Output/tables/predictor_frequencies_RFE_MYT.csv")

final_predictors_myt <- head(predictor_freq_df$Predictor, 5)
write_csv(data.frame(Predictor = final_predictors_myt),
          "Output/tables/final_predictors_RFE_MYT.csv")

selected_ecs <- unique(c(final_predictors_mlt, final_predictors_myt))
write_csv(data.frame(EC = selected_ecs), "Output/tables/final_14_selected_ECs.csv")

message("Feature selection complete.")
