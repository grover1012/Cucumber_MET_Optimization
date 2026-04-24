"""
CMIP6 Future Climate Data Extraction for User-Defined Locations
================================================================

Overview
--------
This script downloads monthly CMIP6 climate projection data from the
Copernicus Climate Data Store (CDS) for user-defined locations, extracts the
requested variables, and combines them into one final CSV file.

The script is designed so that a user only needs to edit the USER SETTINGS
section near the top of the file:
    1. paste their CDS API key,
    2. define the output folder,
    3. enter location names and bounding-box coordinates,
    4. optionally change variables, years, months, model, or scenario.

After that, running the script will:
    1. create the CDS API configuration file (~/.cdsapirc),
    2. optionally mount Google Drive if running in Google Colab,
    3. download all requested CMIP6 variables for each location,
    4. extract ZIP files and convert NetCDF files to CSV,
    5. compute a location-level monthly mean,
    6. save one final combined CSV containing all variables.

CDS dataset reference
---------------------
Copernicus Climate Data Store (CDS) – Projections CMIP6
https://cds.climate.copernicus.eu/datasets/projections-cmip6?tab=download

Important before running
------------------------
1. Create a CDS account.
2. Make sure your CDS account has access to the CMIP6 dataset and that any
   required dataset terms have been accepted in the CDS portal.
3. Paste your CDS API key into API_KEY below.
4. Define your locations as bounding boxes in this format:
       [north, west, south, east]

Example location
----------------
LOCATIONS = {
    "NC_Wake": [36.30, -79.00, 35.30, -78.00],
    "WI_Waushara": [44.11, -89.24, 43.11, -90.24],
}

Output
------
The final output is a CSV file with one row per location x month and one column
per climate variable. The combined file is saved inside OUTPUT_DIR.

Notes
-----
- The script calculates monthly means across all grid cells inside each user-
  supplied bounding box.
- Longitude values are converted from 0..360 to -180..180 if needed.
- The final file is intended to be easy to use for downstream analysis in R,
  Python, or spreadsheet software.
"""

from __future__ import annotations

import os
import textwrap
import zipfile
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import pandas as pd
import xarray as xr

try:
    import cdsapi
except ImportError as exc:
    raise ImportError(
        "cdsapi is required. Install it first with: pip install cdsapi"
    ) from exc


# =============================================================================
# USER SETTINGS: EDIT ONLY THIS SECTION
# =============================================================================

# Paste your CDS API key here.
# Example format is commonly: "123456:abcdef12-3456-7890-abcd-ef1234567890"
API_KEY = "PASTE_YOUR_CDS_API_KEY_HERE"

# Set this to True only if you are running in Google Colab and want to save
# data to Google Drive.
MOUNT_GOOGLE_DRIVE = False
DRIVE_MOUNT_POINT = "/content/drive"

# Main output folder.
# Examples:
#   Local machine: "./CMIP6_Future_Data"
#   Colab + Drive: "/content/drive/MyDrive/CMIP6_Future_Data"
OUTPUT_DIR = "./CMIP6_Future_Data"

# Dataset and CMIP6 request settings.
DATASET = "projections-cmip6"
TEMPORAL_RESOLUTION = "monthly"
EXPERIMENT = "ssp5_8_5"
MODEL = "cesm2"
MONTHS = ["03", "04", "05", "06", "07"]
YEARS = [str(year) for year in range(2050, 2066)]

# Variables to download from the CMIP6 dataset.
VARIABLES = [
    "near_surface_air_temperature",
    "near_surface_specific_humidity",
    "surface_air_pressure",
    "near_surface_wind_speed",
    "surface_downwelling_longwave_radiation",
    "surface_downwelling_shortwave_radiation",
    "precipitation",
    "daily_maximum_near_surface_air_temperature",
    "daily_minimum_near_surface_air_temperature",
    "evaporation_including_sublimation_and_transpiration",
    "relative_humidity",
    "moisture_in_upper_portion_of_soil_column",
]

# User-defined locations.
# Format for each location: [north, west, south, east]
# Give each location a clean unique name. That name will appear in the final CSV.
LOCATIONS: Dict[str, List[float]] = {
    "Location_1": [44.11, -89.24, 43.11, -90.24],
    "Location_2": [37.0252, -78.9732, 35.0252, -76.9732],
}

# Optional: exclude soil moisture from the final combined CSV.
EXCLUDE_SOIL_MOISTURE_FROM_FINAL = False

# Optional: re-download and overwrite existing files.
OVERWRITE_EXISTING = False


# =============================================================================
# INTERNAL CODE: NO NEED TO EDIT BELOW
# =============================================================================

CDS_URL = "https://cds.climate.copernicus.eu/api"
KEY_COLUMNS = {"time", "lat", "lon", "env", "plev"}


def mount_google_drive_if_needed() -> None:
    """Mount Google Drive if requested and running in Google Colab."""
    if not MOUNT_GOOGLE_DRIVE:
        return

    try:
        from google.colab import drive  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "MOUNT_GOOGLE_DRIVE=True, but this environment does not appear to be Google Colab."
        ) from exc

    print(f"Mounting Google Drive at: {DRIVE_MOUNT_POINT}")
    drive.mount(DRIVE_MOUNT_POINT, force_remount=False)


def write_cds_config(api_key: str) -> Path:
    """Create the ~/.cdsapirc file required by cdsapi."""
    if not api_key or api_key == "PASTE_YOUR_CDS_API_KEY_HERE":
        raise ValueError(
            "Please paste your real CDS API key into API_KEY before running the script."
        )

    cfg = textwrap.dedent(
        f"""\
        url: {CDS_URL}
        key: {api_key}
        """
    )

    config_path = Path.home() / ".cdsapirc"
    config_path.write_text(cfg)
    os.chmod(config_path, 0o600)
    print(f"CDS config file written to: {config_path}")
    return config_path


def ensure_dir(path: Path) -> None:
    """Create a directory if it does not already exist."""
    path.mkdir(parents=True, exist_ok=True)


def convert_longitudes(df: pd.DataFrame) -> pd.DataFrame:
    """Convert longitude from 0..360 to -180..180 if needed."""
    if "lon" in df.columns:
        df = df.copy()
        df["lon"] = ((df["lon"] + 180) % 360) - 180
    return df


def select_primary_variable(ds: xr.Dataset) -> str:
    """Pick the main data variable from a NetCDF dataset."""
    candidates = [v for v in ds.data_vars if not v.endswith("_bnds") and "bnds" not in v]
    if candidates:
        return candidates[0]
    return list(ds.data_vars)[0]


def validate_locations(locations: Dict[str, List[float]]) -> None:
    """Check that all location bounding boxes are valid."""
    if not locations:
        raise ValueError("LOCATIONS is empty. Add at least one location before running the script.")

    for name, coords in locations.items():
        if len(coords) != 4:
            raise ValueError(
                f"Location '{name}' must have exactly four values: [north, west, south, east]."
            )

        north, west, south, east = coords

        if north < south:
            raise ValueError(
                f"Location '{name}' is invalid because north ({north}) is less than south ({south})."
            )

        if not (-90 <= north <= 90 and -90 <= south <= 90):
            raise ValueError(
                f"Location '{name}' has latitude outside the valid range [-90, 90]."
            )

        if not (-180 <= west <= 180 and -180 <= east <= 180):
            raise ValueError(
                f"Location '{name}' has longitude outside the valid range [-180, 180]."
            )


def build_request(variable_name: str, area: Sequence[float]) -> dict:
    """Build one CDS API request for one variable and one location."""
    return {
        "temporal_resolution": TEMPORAL_RESOLUTION,
        "experiment": EXPERIMENT,
        "variable": variable_name,
        "model": MODEL,
        "month": MONTHS,
        "year": YEARS,
        "area": list(area),
    }


def download_zip(
    client: cdsapi.Client,
    variable_name: str,
    area: Sequence[float],
    zip_path: Path,
) -> None:
    """Download one CMIP6 variable for one location as a ZIP file."""
    request = build_request(variable_name, area)
    print(f"Downloading: {zip_path.name}")
    client.retrieve(DATASET, request).download(str(zip_path))


def extract_zip(zip_path: Path, extract_dir: Path) -> List[Path]:
    """Extract a ZIP archive and return all NetCDF files inside it."""
    ensure_dir(extract_dir)

    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(extract_dir)

    nc_files = sorted(extract_dir.glob("**/*.nc"))
    if not nc_files:
        raise FileNotFoundError(f"No NetCDF files found after extracting: {zip_path}")

    return nc_files


def netcdf_to_csv(nc_path: Path, csv_path: Path) -> None:
    """Convert one NetCDF file to CSV."""
    print(f"Converting: {nc_path.name} -> {csv_path.name}")

    with xr.open_dataset(nc_path) as ds:
        data_var = select_primary_variable(ds)
        df = ds[data_var].to_dataframe(name=data_var).reset_index().dropna()

    df = convert_longitudes(df)
    df.to_csv(csv_path, index=False)


def process_location_variable(
    client: cdsapi.Client,
    location_name: str,
    area: Sequence[float],
    variable_name: str,
    root_dir: Path,
) -> List[Path]:
    """Download, extract, and convert one variable for one location."""
    location_dir = root_dir / f"cmip6_{location_name}"
    zip_dir = location_dir / "zip_files"
    extract_dir = location_dir / f"unzipped_{variable_name}"
    csv_dir = location_dir / "csv_all"

    ensure_dir(location_dir)
    ensure_dir(zip_dir)
    ensure_dir(extract_dir)
    ensure_dir(csv_dir)

    zip_path = zip_dir / f"{location_name}_{variable_name}.zip"

    if OVERWRITE_EXISTING or not zip_path.exists():
        download_zip(client, variable_name, area, zip_path)
    else:
        print(f"Skipping existing ZIP: {zip_path.name}")

    nc_files = extract_zip(zip_path, extract_dir)
    out_csvs: List[Path] = []

    for nc_path in nc_files:
        with xr.open_dataset(nc_path) as ds:
            netcdf_var = select_primary_variable(ds)

        csv_name = f"{location_name}_{variable_name}_{netcdf_var}.csv"
        csv_path = csv_dir / csv_name

        if OVERWRITE_EXISTING or not csv_path.exists():
            netcdf_to_csv(nc_path, csv_path)
        else:
            print(f"Skipping existing CSV: {csv_path.name}")

        out_csvs.append(csv_path)

    return out_csvs


def run_download_pipeline(root_dir: Path) -> None:
    """Run the full download pipeline for all locations and variables."""
    client = cdsapi.Client()

    for location_name, area in LOCATIONS.items():
        print(f"\nProcessing location: {location_name}")
        for variable_name in VARIABLES:
            process_location_variable(
                client=client,
                location_name=location_name,
                area=area,
                variable_name=variable_name,
                root_dir=root_dir,
            )


def parse_export_filename(filename: str) -> Optional[Tuple[str, str, str]]:
    """Parse file name in the form: location_requestedvar_netcdfvar.csv"""
    stem = Path(filename).stem
    parts = stem.split("_")
    netcdf_var = parts[-1]
    core = "_".join(parts[:-1])

    location_name = None
    remaining = None
    for loc in sorted(LOCATIONS.keys(), key=len, reverse=True):
        prefix = f"{loc}_"
        if core.startswith(prefix):
            location_name = loc
            remaining = core[len(prefix):]
            break

    if location_name is None or remaining is None:
        return None

    requested_var = None
    for variable in sorted(VARIABLES, key=len, reverse=True):
        if remaining == variable or remaining.startswith(f"{variable}_"):
            requested_var = variable
            break

    if requested_var is None:
        return None

    return location_name, requested_var, netcdf_var


def find_all_csvs(root_dir: Path) -> List[Path]:
    """Find all exported CSV files created by the script."""
    return sorted(root_dir.glob("cmip6_*/csv_all/*.csv"))


def build_final_location_mean_csv(root_dir: Path) -> pd.DataFrame:
    """Combine all variables into one final monthly mean CSV per location."""
    csv_files = find_all_csvs(root_dir)
    if not csv_files:
        raise FileNotFoundError("No CSV files found. Run the download pipeline first.")

    records: List[pd.DataFrame] = []
    excluded = set()
    if EXCLUDE_SOIL_MOISTURE_FROM_FINAL:
        excluded.add("moisture_in_upper_portion_of_soil_column")

    for csv_path in csv_files:
        parsed = parse_export_filename(csv_path.name)
        if parsed is None:
            print(f"Skipping unrecognized file name: {csv_path.name}")
            continue

        location_name, requested_var, netcdf_var = parsed
        if requested_var in excluded:
            continue

        df = pd.read_csv(csv_path)
        if "time" not in df.columns:
            print(f"Skipping file with no time column: {csv_path.name}")
            continue

        df["time"] = pd.to_datetime(df["time"])
        value_cols = [col for col in df.columns if col not in KEY_COLUMNS]
        if not value_cols:
            print(f"Skipping file with no data columns: {csv_path.name}")
            continue

        value_col = netcdf_var if netcdf_var in value_cols else value_cols[0]

        temp = df[["time", value_col]].copy()
        temp["location"] = location_name
        temp = temp.groupby(["location", "time"], as_index=False)[value_col].mean()
        temp["variable"] = requested_var
        temp = temp.rename(columns={value_col: "value"})
        records.append(temp)

    if not records:
        raise ValueError("No records were built from the exported CSV files.")

    long_df = pd.concat(records, ignore_index=True)
    long_df = long_df.groupby(["location", "time", "variable"], as_index=False)["value"].mean()

    final_df = (
        long_df.pivot(index=["location", "time"], columns="variable", values="value")
        .reset_index()
        .sort_values(["location", "time"])
        .reset_index(drop=True)
    )
    final_df.columns.name = None
    return final_df


def save_final_outputs(root_dir: Path) -> None:
    """Create and save the final combined CSV."""
    final_df = build_final_location_mean_csv(root_dir)

    output_name = "cmip6_future_weather_final_combined.csv"
    if EXCLUDE_SOIL_MOISTURE_FROM_FINAL:
        output_name = "cmip6_future_weather_final_combined_no_soil_moisture.csv"

    final_path = root_dir / output_name
    final_df.to_csv(final_path, index=False)

    print("\nFinished successfully.")
    print(f"Final combined CSV saved to: {final_path}")
    print(f"Final file shape: {final_df.shape}")
    print("Final columns:")
    print(list(final_df.columns))


def print_run_summary(root_dir: Path) -> None:
    """Print the main run settings."""
    print("Starting CMIP6 future climate extraction...")
    print(f"Output directory: {root_dir.resolve()}")
    print(f"Dataset: {DATASET}")
    print(f"Model: {MODEL}")
    print(f"Experiment: {EXPERIMENT}")
    print(f"Months: {MONTHS}")
    print(f"Years: {YEARS[0]} to {YEARS[-1]}")
    print(f"Number of variables: {len(VARIABLES)}")
    print(f"Number of locations: {len(LOCATIONS)}")


def main() -> None:
    validate_locations(LOCATIONS)
    mount_google_drive_if_needed()
    write_cds_config(API_KEY)

    root_dir = Path(OUTPUT_DIR)
    ensure_dir(root_dir)

    print_run_summary(root_dir)
    run_download_pipeline(root_dir)
    save_final_outputs(root_dir)


if __name__ == "__main__":
    main()
