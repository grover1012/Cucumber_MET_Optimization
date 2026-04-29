# Future Climate Projections Workflow

This folder contains the workflow for extracting future climate data from Copernicus Climate Data Store (CDS) CMIP6 projections.

## Folder contents

```text
future_climate_projections/
├── cmip6_future_weather_colab.ipynb
├── cmip6_future_weather.py
└── README_future_climate_projections.md
```

## Files

### `cmip6_future_weather_colab.ipynb`
Google Colab notebook version of the workflow.

### `cmip6_future_weather.py`
Python script version of the same workflow.

## Purpose

The workflow is used to:
- access future CMIP6 climate projections through CDS
- extract variables for selected environments or counties
- save processed future climate tables for downstream clustering and comparison

## Notes

- You must provide a valid CDS API key.
- Variable names in the request can be changed as long as they are valid CDS variable names.
- If working in Colab, create the `.cdsapirc` file before running requests.
- Export final outputs to `.csv` for downstream use in the R scripts.

## Recommended outputs

For the current repository workflow, future climate data should be processed into environment-level matrices such as:
- `future_matrix_Mar_Jun.csv`
- `future_matrix_Apr_Jul.csv`

These processed files should then be placed in `Data/processed/` for use by the clustering workflow.
