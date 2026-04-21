# Raw data

Place raw input data here. This folder is ignored by git except for this README.

Expected files:

- `mlt_yield.csv`
- `myt_yield.csv`
- `environmental_covariates_raw.csv`
- `soil_covariates.csv`
- `usda_pickling_cucumber_county_area.csv`
- `future_data/` containing CMIP6 county CSV folders

Recommended phenotype columns:

## `mlt_yield.csv`
- genotype
- location
- year
- yield or GY

## `myt_yield.csv`
- genotype
- year
- harvest1 ... harvest6, or total yield/GY

## `usda_pickling_cucumber_county_area.csv`
- state
- county
- harvested_area_acres
