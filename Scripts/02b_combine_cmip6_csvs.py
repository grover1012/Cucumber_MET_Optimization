# 02b_combine_cmip6_csvs.py
# Combine county-level CMIP6 CSVs into one monthly wide table

import os, glob
import pandas as pd

ROOT = "Data/raw/future_data"

OUTTAGS = {
  "CA_SJ","FL_Jackson","MI_Arenac","MI_Berrien","MI_Sanilac","MI_Tuscola",
  "NC_Johnston","NC_Nash","NC_Sampson","OH_Sandusky","W_Waushara",
  "Florida_Lake", "Michigan_Ingham", "Oregon_Marion",
  "North_Carolina_Wake", "Ohio_Henry", "Oklahoma_Wagoner"
}

ALLOWED_VARS = {
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
}

csv_files = glob.glob(os.path.join(ROOT, "cmip6_*", "csv_all", "*.csv"))
print("Found CSVs:", len(csv_files))

def parse_meta_by_lists(path):
    fn = os.path.basename(path).replace(".csv", "")
    parts = fn.split("_")
    ncvar = parts[-1]
    core = "_".join(parts[:-1])

    outtag = None
    for tag in sorted(OUTTAGS, key=len, reverse=True):
        if core.startswith(tag + "_"):
            outtag = tag
            rest = core[len(tag)+1:]
            break
    if outtag is None:
        raise ValueError(f"Could not detect outtag in filename: {fn}")

    reqvar = None
    for v in sorted(ALLOWED_VARS, key=len, reverse=True):
        if rest.startswith(v + "_") or rest == v:
            reqvar = v
            break
    if reqvar is None:
        raise ValueError(f"Could not detect requested variable in filename: {fn}")

    return outtag, reqvar, ncvar

county_tables = {}

for f in csv_files:
    outtag, reqvar, ncvar = parse_meta_by_lists(f)
    df = pd.read_csv(f)
    if "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"], errors="coerce")

    value_cols = [c for c in df.columns if c not in ("time","lat","lon","env","plev")]
    val = ncvar if ncvar in value_cols else value_cols[0]

    df = df[["time","lat","lon", val]].rename(columns={val: reqvar})
    df["env"] = outtag

    if outtag not in county_tables:
        county_tables[outtag] = df
    else:
        county_tables[outtag] = county_tables[outtag].merge(
            df, on=["env","time","lat","lon"], how="outer"
        )

combined = pd.concat(county_tables.values(), ignore_index=True)
if "lon" in combined.columns:
    combined["lon"] = ((combined["lon"] + 180) % 360) - 180

os.makedirs("Data/processed", exist_ok=True)
combined.to_csv("Data/processed/cmip6_all_counties_monthly_combined.csv", index=False)
print("Saved: Data/processed/cmip6_all_counties_monthly_combined.csv")
