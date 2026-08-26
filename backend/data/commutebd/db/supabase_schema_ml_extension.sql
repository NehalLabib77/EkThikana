-- CommuteBD v2 ML/crowd extension.
-- Apply after the existing supabase_schema.sql.

alter table user_fare_reports
  add column if not exists route_distance_km numeric,
  add column if not exists estimated_duration_min numeric,
  add column if not exists actual_duration_min numeric,
  add column if not exists source_type text default 'user_report';

create table if not exists crowd_fare_aggregates (
  aggregate_id bigserial primary key,
  transport_mode text not null,
  origin_place_id text,
  destination_place_id text,
  distance_bucket_km numeric,
  sample_count integer not null default 0,
  p25_fare_tk numeric,
  median_fare_tk numeric,
  p75_fare_tk numeric,
  confidence text,
  window_start timestamptz,
  window_end timestamptz,
  updated_at timestamptz default now()
);

create index if not exists idx_crowd_fare_lookup
  on crowd_fare_aggregates(
    transport_mode,
    origin_place_id,
    destination_place_id
  );

create table if not exists fare_model_registry (
  model_id text primary key,
  transport_mode text not null,
  model_version text not null,
  artifact_path text not null,
  training_row_count integer,
  train_window_start timestamptz,
  train_window_end timestamptz,
  mae numeric,
  rmse numeric,
  median_absolute_error numeric,
  r2 numeric,
  status text default 'candidate',
  created_at timestamptz default now()
);

-- Recommended rule:
-- never allow a model to replace official BRTA/DMTCL bus/metro fares.
