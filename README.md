# Cucumber MET Optimization

This repository contains the analysis workflows used for the cucumber multi-environment trial (MET) optimization project. The project integrates envirotyping, environmental covariate selection, environmental clustering, optimization scenario comparison, present-versus-future environmental comparison, and trial recommendation.

<p align="center">
  <img src="Figures/Abstract_figure.png" alt="Cucumber MET Optimization graphical abstract" width="1100">
</p>

## Repository structure

```text
Cucumber_MET_OPT/
├── Data/
│   ├── raw/
│   └── processed/
├── Outputs/
├── Extracting env data/
│   ├── 01_multiyear_env_data_and_predictor_selection_simple.R
│   ├── 02_multilocation_env_data_and_predictor_selection_simple.R
│   ├── 03_combine_final_predictors_simple.R
│   ├── 04_present_counties_env_processing_simple.R
│   ├── 05_met_optimization_models_FINAL_from_analysis.R
│   ├── 06_present_future_clustering_and_alluvial.R
│   └── README_env_data_processing.md
├── future_climate_projections/
│   ├── cmip6_future_weather_colab.ipynb
│   ├── cmip6_future_weather.py
│   └── README_future_climate_projections.md
└── README.md
```

## Main workflow

The main environmental analysis workflow is in `Extracting env data/`:

1. `01_multiyear_env_data_and_predictor_selection_simple.R`
2. `02_multilocation_env_data_and_predictor_selection_simple.R`
3. `03_combine_final_predictors_simple.R`
4. `04_present_counties_env_processing_simple.R`
5. `05_met_optimization_models_FINAL_from_analysis.R`
6. `06_present_future_clustering_and_alluvial.R`

The future climate extraction workflow is in `future_climate_projections/`.

## Data folders

### `Data/raw/`
Contains raw metadata and phenotypic input files:
- `MYT_metadata.xlsx`
- `MYT_yield.xlsx`
- `MLT_metadata.xlsx`
- `MLT_yield.xlsx`
- `county_acerage.xlsx`

### `Data/processed/`
Contains processed matrices and analysis-ready files:
- `Wmatrix_MYT.csv`
- `Wmatrix_MLT.csv`
- `selected_EC_MYT.csv`
- `selected_EC_MLT.csv`
- `W_present.csv`
- `future_matrix_Mar_Jun.csv`
- `future_matrix_Apr_Jul.csv`
- `Scenarios_summary.csv`

## Recommended run order

1. `01_multiyear_env_data_and_predictor_selection_simple.R`
2. `02_multilocation_env_data_and_predictor_selection_simple.R`
3. `03_combine_final_predictors_simple.R`
4. `04_present_counties_env_processing_simple.R`
5. future climate extraction workflow
6. `06_present_future_clustering_and_alluvial.R`
7. `05_met_optimization_models_FINAL_from_analysis.R`

## Notes

- Some scripts require you to edit file names or paths at the top of the script.
- Environment names must be standardized before joining present and future files.
- The detailed workflow notes are in:
  - `Extracting env data/README_env_data_processing.md`
  - `future_climate_projections/README_future_climate_projections.md`
  - `Data/raw/README.md`
  - `Data/processed/README.md`
