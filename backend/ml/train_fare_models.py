"""Train Gochano commute quantile fare models from approved real reports.

Usage:
    python ml/train_fare_models.py --input approved_reports.csv --mode rickshaw

The input must be an export of MODERATED, APPROVED real reports.
Synthetic fallback rows must never be mixed into this training file.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, median_absolute_error, r2_score

FEATURES = [
    "distance_km",
    "trip_minutes",
    "traffic_level_encoded",
    "hour",
    "weekday",
]


def clean(df: pd.DataFrame, mode: str) -> pd.DataFrame:
    data = df.copy()
    if "distance_km" not in data.columns and "route_distance_km" in data.columns:
        data["distance_km"] = data["route_distance_km"]
    if "trip_minutes" not in data.columns and "actual_duration_min" in data.columns:
        data["trip_minutes"] = data["actual_duration_min"]
    data = data[data["moderation_status"].astype(str).str.lower().eq("approved")]
    data = data[data["transport_mode"].astype(str).str.lower().eq(mode)]
    data = data[pd.to_numeric(data["fare_paid_tk"], errors="coerce").between(1, 10000)]
    data = data[pd.to_numeric(data["distance_km"], errors="coerce").between(0.05, 100)]
    data = data[pd.to_numeric(data["trip_minutes"], errors="coerce").between(1, 720)]
    if "synthetic" in data:
        data = data[~data["synthetic"].fillna(False).astype(bool)]
    if "is_duplicate" in data:
        data = data[~data["is_duplicate"].fillna(False).astype(bool)]

    # Conservative IQR outlier filter on fare per kilometre.
    ratio = pd.to_numeric(data["fare_paid_tk"]) / pd.to_numeric(data["distance_km"])
    q1, q3 = ratio.quantile([0.25, 0.75])
    iqr = max(float(q3 - q1), 1e-6)
    data = data[(ratio >= q1 - 2.5 * iqr) & (ratio <= q3 + 2.5 * iqr)]

    time = pd.to_datetime(data["created_at"], errors="coerce", utc=True)
    data = data.assign(
        hour=time.dt.hour.fillna(12),
        weekday=time.dt.weekday.fillna(0),
    )
    traffic = {"unknown": 0, "light": 1, "normal": 2, "heavy": 3}
    traffic_series = (
        data["traffic_level"]
        if "traffic_level" in data.columns
        else pd.Series("unknown", index=data.index)
    )
    data["traffic_level_encoded"] = (
        traffic_series.astype(str).str.lower().map(traffic).fillna(0)
    )
    for col in FEATURES:
        data[col] = pd.to_numeric(data[col], errors="coerce")
    return data.dropna(subset=FEATURES + ["fare_paid_tk"]).sort_values("created_at")


def train(data: pd.DataFrame) -> tuple[dict, dict]:
    split = max(1, int(len(data) * 0.8))
    split = min(split, len(data) - 1)
    train_df, test_df = data.iloc[:split], data.iloc[split:]

    X_train = train_df[FEATURES].to_numpy(float)
    y_train = train_df["fare_paid_tk"].to_numpy(float)
    X_test = test_df[FEATURES].to_numpy(float)
    y_test = test_df["fare_paid_tk"].to_numpy(float)

    models = {}
    for name, alpha in [("q25", 0.25), ("q50", 0.50), ("q75", 0.75)]:
        model = GradientBoostingRegressor(
            loss="quantile",
            alpha=alpha,
            n_estimators=180,
            max_depth=3,
            learning_rate=0.04,
            random_state=42,
        )
        model.fit(X_train, y_train)
        models[name] = model

    pred = models["q50"].predict(X_test)
    metrics = {
        "MAE": float(mean_absolute_error(y_test, pred)),
        "RMSE": float(mean_squared_error(y_test, pred) ** 0.5),
        "MedianAE": float(median_absolute_error(y_test, pred)),
        "R2": float(r2_score(y_test, pred)) if len(y_test) >= 2 else None,
        "trainRows": int(len(train_df)),
        "testRows": int(len(test_df)),
    }
    return {"features": FEATURES, **models}, metrics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--mode", choices=["rickshaw", "cng"], required=True)
    parser.add_argument("--out", default="ml/artifacts")
    args = parser.parse_args()

    raw = pd.read_csv(args.input)
    data = clean(raw, args.mode)
    if len(data) < 150:
        raise SystemExit(
            f"Refusing to train: only {len(data)} approved real {args.mode} reports; minimum is 150."
        )

    bundle, metrics = train(data)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    model_path = out / f"{args.mode}_quantiles.joblib"
    metrics_path = out / f"{args.mode}_metrics.json"
    joblib.dump(bundle, model_path)
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps({"model": str(model_path), "metrics": metrics}, indent=2))


if __name__ == "__main__":
    main()
