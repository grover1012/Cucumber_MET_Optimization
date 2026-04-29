# Raw Data

This folder contains the raw metadata and phenotypic input files used in the cucumber MET optimization workflows.

## Current files

- `MYT_metadata.xlsx`
- `MYT_yield.xlsx`
- `MLT_metadata.xlsx`
- `MLT_yield.xlsx`
- `county_acerage.xlsx`
- `README.md`

## File roles

### `MYT_metadata.xlsx`
Raw metadata for the multi-year trial workflow.

Typically includes:
- `env`
- `Year`
- `lat`
- `lon`
- `Alt`
- `plantingDate`
- `harvestDate`

### `MYT_yield.xlsx`
Raw phenotypic data for the multi-year trial workflow.

Typically includes:
- `env`
- `Year`
- `genotype`
- `replicate`
- `yield`

### `MLT_metadata.xlsx`
Raw metadata for the historical multi-location workflow.

### `MLT_yield.xlsx`
Raw phenotypic data for the historical multi-location workflow.

### `county_acerage.xlsx`
County-level metadata and production-importance input file used in present county analyses and recommendation workflows.

Depending on the script, this file may need:
- `env`
- `lat`
- `lon`
- acreage or production importance
- planting and harvest dates, if required by weather extraction scripts

## Notes

- Keep the raw files unchanged once they are finalized for the project.
- If you need to clean or reformat data, save the derived version in `Data/processed/` rather than overwriting raw files.
