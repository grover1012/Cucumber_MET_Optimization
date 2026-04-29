# Processed Data

This folder contains processed environmental matrices and derived analysis-ready tables used by the cucumber MET optimization workflows.

## Current files

- `Wmatrix_MYT.csv`
- `Wmatrix_MLT.csv`
- `selected_EC_MYT.csv`
- `selected_EC_MLT.csv`
- `W_present.csv`
- `future_matrix_Mar_Jun.csv`
- `future_matrix_Apr_Jul.csv`
- `Scenarios_summary.csv`
- `future_env_data.numbers`

## File roles

### `Wmatrix_MYT.csv`
Processed environmental matrix for the multi-year trial workflow.

### `Wmatrix_MLT.csv`
Processed environmental matrix for the historical multi-location workflow.

### `selected_EC_MYT.csv`
Selected environmental covariates from the multi-year workflow.

### `selected_EC_MLT.csv`
Selected environmental covariates from the multi-location workflow.

### `W_present.csv`
Processed present environmental matrix used for present clustering.

### `future_matrix_Mar_Jun.csv`
Processed future environmental matrix for the Mar_Jun window.

### `future_matrix_Apr_Jul.csv`
Processed future environmental matrix for the Apr_Jul window.

### `Scenarios_summary.csv`
Summary output related to MET optimization scenario comparison.

### `future_env_data.numbers`
Working file from future climate data processing.

Note:
- this file is not ideal as a final reproducible input
- export to `.csv` if it is needed by the repository workflows

## Notes

- These files are typically created from raw metadata, yield, or climate source data.
- Keep file names stable so the scripts remain reproducible.
- When possible, save final workflow inputs as `.csv` rather than app-specific formats such as `.numbers`.
