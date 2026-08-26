-- CommuteBD v1 - Supabase/PostgreSQL starter schema
-- Import order: places -> fare_rules -> brta_routes -> brta_route_stops
-- -> bus_services -> bus_service_stops -> metro_stations -> metro_fares

-- Safe on Supabase Cloud: pgcrypto is already installed in the extensions schema,
-- but we declare it explicitly so gen_random_uuid() resolves on any Postgres target.
create extension if not exists pgcrypto;

create table if not exists places (
  place_id text primary key,
  name_en text not null,
  name_bn text,
  normalized_name text,
  latitude double precision,
  longitude double precision,
  geocode_status text default 'pending',
  source_id text
);

create table if not exists fare_rules (
  fare_rule_id text primary key,
  mode text not null,
  coverage text,
  effective_from text,
  base_or_minimum_fare_tk numeric,
  included_distance_km numeric,
  per_km_tk numeric,
  waiting_rule text,
  other_rule text,
  production_status text,
  source_id text
);

create table if not exists brta_routes (
  route_id text primary key,
  route_code_en text,
  route_code_bn text,
  route_name_en text,
  route_name_bn text,
  origin_name_en text,
  destination_name_en text,
  total_distance_km numeric,
  stop_count integer,
  fare_per_km_tk numeric,
  minimum_fare_tk numeric,
  live_use boolean default true,
  source_id text
);

create table if not exists brta_route_stops (
  route_id text references brta_routes(route_id) on delete cascade,
  stop_sequence integer not null,
  place_id text references places(place_id),
  stop_name_en text,
  stop_name_bn text,
  cumulative_distance_km numeric,
  segment_distance_from_previous_km numeric,
  source_id text,
  primary key(route_id, stop_sequence)
);

create table if not exists bus_services (
  service_id text primary key,
  operator_name_en text,
  operator_name_bn text,
  variant_no_for_operator integer,
  start_stop_raw text,
  end_stop_raw text,
  stop_count integer,
  service_type text,
  time_text text,
  image_url text,
  current_status text,
  source_id text
);

create table if not exists bus_service_stops (
  service_id text references bus_services(service_id) on delete cascade,
  stop_sequence integer not null,
  stop_name_raw text,
  normalized_stop_name text,
  canonical_place_id text references places(place_id),
  canonical_name_en text,
  source_id text,
  primary key(service_id, stop_sequence)
);

create table if not exists metro_stations (
  station_id text primary key,
  line_id text not null,
  station_order integer not null,
  name_en text not null,
  name_bn text,
  operational_status text,
  live_routing_enabled boolean default true,
  latitude double precision,
  longitude double precision,
  geocode_status text,
  source_id text
);

create table if not exists metro_fares (
  line_id text not null,
  from_station_id text references metro_stations(station_id),
  to_station_id text references metro_stations(station_id),
  single_journey_fare_tk numeric not null,
  mrt_rapid_pass_fare_tk numeric,
  live_usable boolean default true,
  source_id text,
  primary key(line_id, from_station_id, to_station_id)
);

create table if not exists user_fare_reports (
  report_id uuid primary key default gen_random_uuid(),
  user_id_hash text,
  trip_started_at timestamptz,
  trip_ended_at timestamptz,
  origin_place_id text references places(place_id),
  origin_text text,
  origin_latitude double precision,
  origin_longitude double precision,
  destination_place_id text references places(place_id),
  destination_text text,
  destination_latitude double precision,
  destination_longitude double precision,
  transport_mode text not null,
  bus_service_id text references bus_services(service_id),
  bus_name_user_entered text,
  route_id_if_known text references brta_routes(route_id),
  fare_paid_tk numeric check (fare_paid_tk >= 0),
  passenger_count integer default 1 check (passenger_count > 0),
  payment_type text,
  traffic_level text,
  user_confidence text,
  receipt_or_photo_url text,
  device_location_verified boolean default false,
  moderation_status text default 'pending',
  created_at timestamptz default now()
);

create index if not exists idx_places_name on places(normalized_name);
create index if not exists idx_brta_route_stops_place on brta_route_stops(place_id);
create index if not exists idx_bus_service_stops_place on bus_service_stops(canonical_place_id);
create index if not exists idx_user_fare_origin_dest on user_fare_reports(origin_place_id, destination_place_id, transport_mode);
