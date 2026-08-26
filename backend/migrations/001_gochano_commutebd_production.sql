-- Gochano CommuteBD production extension.
-- First run: backend/data/commutebd/core_dataset/supabase_schema.sql
-- Then run: backend/data/commutebd/db/supabase_schema_ml_extension.sql
-- Finally run this file.

alter table if exists user_fare_reports
  add column if not exists trip_minutes integer,
  add column if not exists dedupe_key text,
  add column if not exists source_type text default 'user_report';

create unique index if not exists idx_user_fare_reports_dedupe
  on user_fare_reports(dedupe_key)
  where dedupe_key is not null;

create index if not exists idx_user_fare_reports_approved_mode_created
  on user_fare_reports(transport_mode, created_at desc)
  where moderation_status = 'approved';

-- Rename-free compatibility view used in documentation.
create or replace view commute_approved_fare_reports as
select *
from user_fare_reports
where moderation_status = 'approved';

-- Keep public client access closed. Backend service-role access bypasses RLS.
alter table if exists user_fare_reports enable row level security;
alter table if exists crowd_fare_aggregates enable row level security;
alter table if exists fare_model_registry enable row level security;

-- Do not add permissive anon/authenticated policies here.
-- Fare reports are written by the Firebase-authenticated FastAPI backend.
