# Future Climate Projections Extraction Pipeline (CMIP6)

This workflow downloads future climate projection data from the **Copernicus Climate Data Store (CDS)** CMIP6 dataset for user-defined locations, extracts climate variables, and produces:

1. **individual CSV files** for each variable  
2. **one final combined CSV file** containing all extracted variables for each location and time step

This workflow is provided in two formats:

- **Python script**: `cmip6_future_weather_repo_ready.py`
- **Colab notebook**: `cmip6_future_weather_colab_easy.ipynb`

---
## Variable selection

The script includes a default list of climate variables for convenience, but
users are not restricted to only those variables.

Users may modify the `VARIABLES` section to request other variables available
in the Copernicus Climate Data Store (CDS) CMIP6 dataset, as long as the
variable name matches the CDS dataset naming exactly and is valid for the
selected request settings.

Dataset page:
https://cds.climate.copernicus.eu/datasets/projections-cmip6?tab=download

Before changing variables, users should verify:
- the variable is available in the selected CDS CMIP6 dataset
- the variable name matches the CDS naming exactly
- the variable is compatible with the selected model, experiment, and temporal settings

## Dataset source

This workflow uses the **Copernicus Climate Data Store (CDS) – Projections CMIP6** dataset:

`https://cds.climate.copernicus.eu/datasets/projections-cmip6?tab=download`

Before running the workflow, users should:

- create a CDS account
- generate their CDS API key
- make sure they have accepted any required dataset terms on the CDS website

---

## What this workflow does

The pipeline is designed to be simple for end users. The user only needs to:

- provide their **CDS API key**
- define an **output folder**
- provide **location names**
- provide **location coordinates as bounding boxes**
- choose variables, years, model, and scenario if needed

After that, the workflow will:

1. create the CDS API configuration file
2. optionally mount Google Drive in Colab
3. download CMIP6 future climate data for all requested locations and variables
4. extract the downloaded ZIP files
5. read the NetCDF files
6. convert each variable to CSV
7. merge all variable CSV files into one **final combined CSV**

---

## Files included

This folder should contain:

- `cmip6_future_weather_repo_ready.py`  
  Main repo-ready Python pipeline.

- `cmip6_future_weather_colab_easy.ipynb`  
  Colab-friendly notebook version.

- `README.md`  
  This file.

- `requirements.txt`  
  Python package requirements.

---

## Recommended folder structure

```text
future_climate_projections/
├── README.md
├── requirements.txt
├── cmip6_future_weather_repo_ready.py
└── cmip6_future_weather_colab_easy.ipynb
```

If this is part of a larger project, a common structure is:

```text
project-root/
├── scripts/
│   └── future_climate_projections/
│       ├── README.md
│       ├── requirements.txt
│       ├── cmip6_future_weather_repo_ready.py
│       └── cmip6_future_weather_colab_easy.ipynb
```

---

## Required Python packages

Typical required packages include:

- `cdsapi`
- `xarray`
- `netCDF4`
- `pandas`
- `numpy`

If needed, install with:

```bash
pip install cdsapi xarray netCDF4 pandas numpy
```

---

## Input requirements

### 1. CDS API key
Users must obtain their API key from their CDS account profile.

In the workflow, the user should paste their key into:

```python
API_KEY = "PASTE_YOUR_CDS_API_KEY_HERE"
```

Do **not** commit a real API key to GitHub.

---

### 2. Output directory
This is the folder where downloaded files, extracted files, intermediate CSVs, and final combined CSVs will be stored.

Example:

```python
OUTPUT_DIR = "/content/drive/MyDrive/future_climate_data"
```

or for local use:

```python
OUTPUT_DIR = "data/future_climate_data"
```

---

### 3. Location definitions
Locations must be provided as **bounding boxes**, not single latitude-longitude points.

Format:

```python
LOCATIONS = {
    "Location_Name_1": [north, west, south, east],
    "Location_Name_2": [north, west, south, east]
}
```

Example:

```python
LOCATIONS = {
    "CA_San_Joaquin": [38.5, -122.0, 36.5, -120.0],
    "NC_Wake": [36.2, -79.5, 35.3, -78.2]
}
```

### Bounding box format
The order must be:

```text
[north, west, south, east]
```

This is important. If the order is wrong, the download may fail or extract incorrect values.

---

## Main user-edit section

The workflow is designed so that users mainly edit only the top section.

Typical fields include:

- `API_KEY`
- `OUTPUT_DIR`
- `LOCATIONS`
- `VARIABLES`
- `YEARS`
- `MONTHS`
- `MODEL`
- `EXPERIMENT`

---

## Outputs

The workflow creates:

### 1. Individual variable CSV files
Each climate variable is exported separately.

Examples:
- `tas.csv`
- `pr.csv`
- `rsds.csv`

### 2. Final combined CSV
At the end, all variables are merged into one final dataset.

Typical output name:

- `cmip6_future_weather_final_combined.csv`

If soil moisture is excluded, the output name may be:

- `cmip6_future_weather_final_combined_no_soil_moisture.csv`

The final file contains all variables joined by location and time.

---

## Running the workflow in Google Colab

The notebook version is the easiest option for most users.

### Steps

1. Upload or open `cmip6_future_weather_colab_easy.ipynb` in Colab.
2. Install required packages if prompted.
3. Paste your CDS API key in the user settings cell.
4. Set your output directory.
5. Define your locations and bounding boxes.
6. Run all cells.
7. The notebook will generate:
   - individual variable CSV files
   - one final combined CSV
8. Preview or download the final CSV file.

### Google Drive
If using Colab, you may save outputs directly to Google Drive by setting:

```python
OUTPUT_DIR = "/content/drive/MyDrive/future_climate_data"
```

If the notebook includes Google Drive mounting, run that cell first.

---

## Running the workflow locally with Python

You can also run the Python script locally.

### Steps

1. Clone or download the repository.
2. Install required packages.
3. Open `cmip6_future_weather_repo_ready.py`.
4. Edit the user settings section:
   - API key
   - output directory
   - locations
   - variables / years / model / scenario
5. Run the script:

```bash
python cmip6_future_weather_repo_ready.py
```

6. Check the output folder for:
   - downloaded files
   - extracted NetCDF files
   - intermediate CSV files
   - final combined CSV

---

## Typical workflow logic

The workflow generally follows this sequence:

1. **Create CDS config**
   - generates `.cdsapirc` using the provided API key

2. **Download data**
   - requests CMIP6 climate data for each variable and location

3. **Unzip files**
   - extracts compressed files

4. **Read NetCDF**
   - loads climate data into Python

5. **Convert to CSV**
   - writes variable-specific CSV outputs

6. **Combine all CSVs**
   - merges all variable files into one final dataset

---

## Notes for users

- This workflow is intended for **future climate projection extraction** from CMIP6.
- Location inputs are **bounding boxes**, not point coordinates.
- Output values depend on the variable, model, experiment, time range, and spatial extent selected.
- The final combined CSV is intended to simplify downstream analysis by placing all extracted variables in one file.

---

## Good GitHub practice

Before pushing to GitHub:

- remove any real API key
- keep:
  ```python
  API_KEY = "PASTE_YOUR_CDS_API_KEY_HERE"
  ```
- do not upload:
  - `.cdsapirc`
  - downloaded `.zip` files
  - extracted `.nc` files
  - generated output `.csv` files unless they are intended example outputs

---

## Suggested `.gitignore`

```gitignore
# Secrets
.cdsapirc
.env

# Outputs
data/*
!data/.gitkeep

*.zip
*.nc
*.csv

# Python
__pycache__/
*.pyc

# Notebook checkpoints
.ipynb_checkpoints/
```

If your repository already contains other CSV files that should be version controlled, then do **not** ignore all `*.csv` globally. In that case, ignore only the output directory.

Example:

```gitignore
future_climate_projections/output/*
```

---

## Common issues

### 1. Invalid API key
If authentication fails:
- check that the CDS API key is correct
- verify that your CDS account is active
- confirm that any required dataset terms have been accepted

### 2. Wrong coordinate order
If downloads or outputs look incorrect, confirm that each location is defined as:

```text
[north, west, south, east]
```

### 3. Missing packages
Install required Python packages before running the script or notebook.

### 4. Large downloads
Some variable, model, and year combinations may create large files. Make sure enough storage is available in Colab or on your local machine.

### 5. Notebook runs but no final combined CSV appears
Check that:
- variable-level CSVs were generated successfully
- all CSVs have the expected key columns
- output paths are correct

---

## Recommended citation / acknowledgment

If this workflow is used in a project or publication, users should cite or acknowledge the **Copernicus Climate Data Store** and the **CMIP6** data source appropriately according to CDS data-use guidance.

---

## Contact / project note

This workflow was developed as part of a larger project for extracting and organizing future climate projections for downstream environmental and breeding analyses.

If you extend this workflow, it is recommended to:
- keep the Python script as the canonical version
- keep the Colab notebook as a user-friendly interface
- update both together to avoid divergence

---

## Summary

This workflow provides an end-to-end pipeline to:

- define future climate extraction settings
- download CMIP6 projections for user-defined locations
- extract and convert variable-level outputs
- generate one final combined CSV for all requested variables and locations

For most users, the **Colab notebook** is the easiest way to run the workflow.  
For long-term maintenance and version control, the **Python script** should be treated as the main reference implementation.
