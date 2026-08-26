-- CommuteBD v3 - Extended tables for BRTA graph, alias matching,
-- fare segments, geocoding queue, source catalogue, and MRT network plan.
-- Add-only; references Phase-1 (commutebd_main_schema) tables.

-- 1. sources: catalogue of every upstream data origin referenced elsewhere.
create table if not exists sources (
  source_id        text primary key,
  title            text not null,
  source_type      text,
  url              text,
  source_date      text,
  reliability      text,
  recommended_use  text,
  notes            text
);

-- 2. stop_aliases: fuzzy/community stop names mapped to canonical places.
--    canonical_place_id is intentionally nullable because many rows are unmatched.
create table if not exists stop_aliases (
  alias_id              bigserial primary key,
  raw_stop_name         text not null,
  normalized_stop_name  text,
  canonical_place_id    text references places(place_id),
  canonical_name_en     text,
  match_score           numeric,
  match_method          text,
  needs_manual_review   boolean default false,
  source_id             text references sources(source_id)
);
create index if not exists idx_stop_aliases_canonical
  on stop_aliases(canonical_place_id);
create index if not exists idx_stop_aliases_normalized
  on stop_aliases(normalized_stop_name);

-- 3. service_route_matches: proposed mapping from a community bus service
--    to its best BRTA route candidate (manually verified = false initially).
create table if not exists service_route_matches (
  service_id             text references bus_services(service_id) on delete cascade,
  best_brta_route_id     text references brta_routes(route_id),
  operator_name_en       text,
  common_stop_count      integer,
  service_coverage       numeric,
  brta_route_coverage    numeric,
  match_score            numeric,
  match_quality          text,
  verified               boolean default false,
  warning                text,
  source_id              text references sources(source_id),
  primary key (service_id, best_brta_route_id)
);
create index if not exists idx_service_route_matches_route
  on service_route_matches(best_brta_route_id);

-- 4. brta_fare_segments: per-pair fare rules for a route, indexed by stops.
create table if not exists brta_fare_segments (
  route_id          text references brta_routes(route_id) on delete cascade,
  from_place_id     text references places(place_id),
  to_place_id       text references places(place_id),
  from_name_en      text,
  to_name_en        text,
  distance_km       numeric,
  fare_tk           numeric,
  fare_per_km_tk    numeric,
  minimum_fare_tk   numeric,
  calculation       text,
  source_id         text references sources(source_id),
  primary key (route_id, from_place_id, to_place_id)
);
create index if not exists idx_brta_fare_segments_route
  on brta_fare_segments(route_id);

-- 5. brta_graph_edges: directed adjacency of BRTA stops along a route.
--    Synthetic bigserial PK; direction (forward/reverse) is data, not part of key.
create table if not exists brta_graph_edges (
  edge_id                bigserial primary key,
  route_id               text references brta_routes(route_id) on delete cascade,
  from_place_id          text references places(place_id),
  to_place_id            text references places(place_id),
  from_name_en           text,
  to_name_en             text,
  segment_distance_km    numeric,
  direction              text,
  source_id              text references sources(source_id)
);
create index if not exists idx_brta_graph_edges_route_from_to
  on brta_graph_edges(route_id, from_place_id, to_place_id);

-- 6. geocoding_queue: pending lookups for places / stations / stops.
create table if not exists geocoding_queue (
  entity_type    text not null,
  entity_id      text not null,
  name_en        text,
  name_bn        text,
  search_text    text,
  latitude       double precision,
  longitude      double precision,
  provider       text,
  confidence     text,
  status         text default 'pending',
  primary key (entity_type, entity_id)
);
create index if not exists idx_geocoding_queue_status
  on geocoding_queue(status);

-- 7. transit_network_plan: planned MRT lines (live routing uses metro_stations).
create table if not exists transit_network_plan (
  line_name              text primary key,
  total_length_km        numeric,
  elevated_km            numeric,
  underground_km         numeric,
  total_stations         integer,
  elevated_stations      integer,
  underground_stations   integer,
  routing_status         text,
  source_id              text references sources(source_id)
);
