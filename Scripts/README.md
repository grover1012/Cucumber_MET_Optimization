# Environmental Data Processing Workflow

This folder contains the main R scripts used for environmental data extraction, processing, predictor selection, scenario comparison, and present-versus-future environmental analysis in the cucumber MET optimization project.

## Folder contents

```text
Extracting env data/
├── 01_multiyear_env_data_and_predictor_selection_simple.R
├── 02_multilocation_env_data_and_predictor_selection_simple.R
├── 03_combine_final_predictors_simple.R
├── 04_present_counties_env_processing_simple.R
├── 05_met_optimization_models_FINAL_from_analysis.R
├── 06_present_future_clustering_and_alluvial.R
└── README_env_data_processing.md
```

## Script overview

### 1. `01_multiyear_env_data_and_predictor_selection_simple.R`
Uses:
- `Data/raw/MYT_metadata.xlsx`
- `Data/raw/MYT_yield.xlsx`

Main tasks:
- weather extraction with `EnvRtype`
- environmental processing
- soil covariate extraction
- environmental matrix creation
- predictor selection
- clustering of multi-year environments

### 2. `02_multilocation_env_data_and_predictor_selection_simple.R`
Uses:
- `Data/raw/MLT_metadata.xlsx`
- `Data/raw/MLT_yield.xlsx`

Main tasks:
- weather extraction with `EnvRtype`
- environmental processing
- soil covariate extraction
- environmental matrix creation
- predictor selection
- clustering of historical environments

### 3. `03_combine_final_predictors_simple.R`
Uses:
- `Data/processed/selected_EC_MYT.csv`
- `Data/processed/selected_EC_MLT.csv`

Main tasks:
- compare MYT and MLT selected predictors
- create shared and union predictor sets
- generate final predictor lists for downstream analyses

### 4. `04_present_counties_env_processing_simple.R`
Uses:
- `Data/raw/county_acerage.xlsx`

Main tasks:
- process present county-level environmental data
- build present environmental matrix or summary tables used for downstream clustering

### 5. `05_met_optimization_models_FINAL_from_analysis.R`
Uses:
- single-environment results derived from historical data
- cluster assignments
- processed environmental matrix, typically from historical multi-location analysis

Main tasks:
- calculate BLUEs, BLUPs, and Cullis heritability
- compare MET optimization scenarios
- summarize strategy performance
- generate scenario comparison plots

Current intended interpretation:
- `OPT_MET` is replicated
- all other strategies are deterministic

### 6. `06_present_future_clustering_and_alluvial.R`
Uses:
- `Data/processed/W_present.csv`
- `Data/processed/future_matrix_Mar_Jun.csv`
- `Data/processed/future_matrix_Apr_Jul.csv`

Main tasks:
- cluster present environments
- cluster future environments separately
- create alluvial-ready comparison tables

Important:
- present and future are clustered separately
- variable names do not need to match between present and future
- environment names must be standardized before comparison

## Recommended order to run

1. `01_multiyear_env_data_and_predictor_selection_simple.R`
2. `02_multilocation_env_data_and_predictor_selection_simple.R`
3. `03_combine_final_predictors_simple.R`
4. `04_present_counties_env_processing_simple.R`
5. future climate extraction workflow
6. `06_present_future_clustering_and_alluvial.R`
7. `05_met_optimization_models_FINAL_from_analysis.R`

## General notes

- Keep file names consistent with the actual files in `Data/raw/` and `Data/processed/`.
- If input file names differ, edit only the file-path section at the top of each script.
- Standardize environment names before joining files across workflows.
- Archive rough or exploratory scripts outside this folder if they were not part of the final workflow used in the paper.
