# Optimization script inputs

Use `05_met_optimization_models_FINAL_from_analysis.R` for the final manuscript optimization analysis.

Required inputs/objects:

1. `yld_env.xlsx`
   - columns: `genotype`, `replicate`, `env`, `yield`
   - should contain the MLT phenotype data arranged by environment.

2. `clusters`
   - data frame with columns: `env`, `cluster`
   - cluster assignment for each environment.

3. `W.clean2`
   - environment-by-EC matrix/data frame
   - rownames must be environment IDs matching `env`
   - columns should be the final selected ECs used for MET_EC.

Output generated:
- environment-level BLUEs
- environment-level BLUPs
- environment-level Cullis H2
- `results.st1`
- scenario-level comparison objects: `MET`, `MET_EC`, `WC_MET`, `OPT_MET`, `HT_MET`
- final scenario summary table
- strategy comparison plots

Note:
This script is for the historical MLT optimization only. MYT is used in the repository workflow for feature selection and temporal environmental clustering, not for the final MET optimization scenario comparison.
