# Cucumber_MET_OPT

This repository contains the analysis pipeline for the manuscript:

**Optimizing pickling cucumber multi-environment trial networks using environmental covariates, production importance, and future climate projections**

The repository structure follows the MET optimization project style used by Prado et al. for rice MET optimization, with separate `Data`, `Scripts`, and `Output` folders, but is adapted for pickling cucumber and includes future climate comparison.

## Project structure

```text
Cucumber_MET_OPT/
├── Cucumber_MET_OPT.Rproj
├── README.md
├── .gitignore
├── Data/
│   ├── raw/          # raw input files; not tracked by git
│   └── processed/    # cleaned and derived datasets
├── Scripts/          # analysis scripts, run in numeric order
├── R/                # helper functions
├── Output/
│   ├── tables/       # result tables
│   ├── models/       # model objects
│   └── intermediate/ # intermediate files
├── Figures/          # final manuscript figures
└── Manuscript/       # manuscript files or LaTeX notes
```

## Analysis workflow

Run the scripts in this order:

1. `Scripts/00_setup.R`  
   Loads packages and sources helper functions.

2. `Scripts/01_prepare_phenotypes.R`  
   Cleans multi-location and multi-year phenotype datasets.

3. `Scripts/02_prepare_environmental_covariates.R`  
   Processes weather and soil ECs and creates the phenology-stage table.

4. `Scripts/02b_combine_cmip6_csvs.py`  
   Combines county-level CMIP6 CSV files into one monthly future climate dataset.

5. `Scripts/03_feature_selection.R`  
   Performs EC filtering, stepwise regression for MLT, and repeated RFE for MYT.

6. `Scripts/04_tpe_clustering.R`  
   Performs PCA, elbow/WSS diagnostics, and k-means clustering for MLT, MYT, current counties, and future windows.

7. `Scripts/05_met_optimization_models.R`  
   Fits MET, MET_EC, WC_MET, OPT_MET, and HT_MET models and calculates Cullis heritability and trial-efficiency metrics.

8. `Scripts/06_production_importance_and_recommendations.R`  
   Calculates USDA harvested-area based production importance and cluster-level trial recommendation summaries.

9. `Scripts/07_future_cluster_transitions.R`  
   Creates present vs future cluster transition/alluvial data and plot.

10. `Scripts/08_export_publication_figures.R`  
   Exports final manuscript-ready figures.

## Data inputs

Raw data are not tracked in this repository by default. Place them in `Data/raw/`.

Expected files:

```text
Data/raw/mlt_yield.csv
Data/raw/myt_yield.csv
Data/raw/environmental_covariates_raw.csv
Data/raw/soil_covariates.csv
Data/raw/usda_pickling_cucumber_county_area.csv
Data/raw/future_data/
```

## Notes

- The multi-location trial contains 7 locations × 3 years = 21 location-year environments.
- The multi-year trial yield is calculated as the sum of six harvests.
- Present climate period: 2010–2025.
- Future climate period: 2050–2065.
- Future climate model/scenario: CESM2, SSP5-8.5.
- Future planting windows: March–June and April–July.
- Production importance is based on USDA 2022 Census harvested area for pickling cucumbers.

## Contact

Kashish Grover  
Department of Horticultural Science, North Carolina State University


## Important script update

The repository now includes the uploaded working optimization script:

```text
Scripts/05_met_optimization_models_FINAL_from_analysis.R
```

This is the latest optimization workflow from the analysis and includes:

- environment-level BLUE/BLUP extraction from `yld_env.xlsx`
- true environment-level Cullis heritability calculation
- construction of `results.st1`
- MET, MET_EC, WC_MET, OPT_MET, and HT_MET scenario comparison
- 50 replicated runs for OPT_MET and HT_MET
- final scenario summary tables
- heritability comparison plot export

The earlier `Scripts/05_met_optimization_models.R` remains a cleaned template. For reproducing the manuscript analysis, use the FINAL script after preparing the required input objects/files:

- `yld_env.xlsx`
- `clusters`
- `W.clean2`
