# CommuteBD Dataset — ML Ready v2

This archive preserves every dataset/file uploaded for CommuteBD and adds a
production-oriented hybrid fare-prediction plan.

## Most important rule

Do not train one ML model to predict every transport fare.

- Bus: use official BRTA stop-pair fare data/rules.
- Metro: use official DMTCL station-pair fare matrix.
- CNG: keep legal meter calculation separate from observed market estimates.
- Rickshaw: estimate from verified crowd reports; ML becomes useful only after
  enough real observations exist.

`rickshaw_auto_estimated_fares.csv` currently contains a synthetic
distance-times-rate baseline. It is preserved for fallback/testing, but should
not be treated as real observed training truth.

## Folder structure

- `core_dataset/` — extracted current CommuteBD v1.1 dataset pack.
- `uploaded_originals/` — every original uploaded file, unchanged.
- `ml/` — ML training template, model policy and prediction contract.
- `db/` — optional Supabase/PostgreSQL ML/crowd extension.
- `docs/` — production build prompt for the CommuteBD feature.
- `manifest_sha256.csv` — inventory + SHA-256 checksum for future integrity checks.

## Recommended ML launch sequence

1. Launch deterministic bus/metro fare lookup.
2. Collect and moderate real rickshaw/CNG fare reports.
3. Publish robust crowd quantile ranges first.
4. Train a model only after the release gate is reached.
5. Compare model MAE with simple crowd-median and distance-only baselines.
6. Deploy only if the model actually improves useful prediction quality.

## Suggested model

Use three `GradientBoostingRegressor` quantile models:
- q25
- median
- q75

This lets the UI return a fare range rather than a misleading single number.

## Important future data work

The biggest remaining practical jobs are:
- complete latitude/longitude geocoding,
- manually validate old community bus-service routes,
- collect enough verified real fare reports,
- periodically re-check legal/official fare rules.
