-- Gochano Bus Seed v1
-- Safe default: only inserts missing stable IDs/rows.
-- Review and back up the target database before production use.

BEGIN;

CREATE TEMP TABLE staging_bus_services (
    service_id text,
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
) ON COMMIT DROP;

CREATE TEMP TABLE staging_bus_service_stops (
    service_id text,
    stop_sequence integer,
    stop_name_raw text,
    normalized_stop_name text,
    canonical_place_id text,
    canonical_name_en text,
    source_id text
) ON COMMIT DROP;

\copy staging_bus_services FROM 'bus_services_seed.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy staging_bus_service_stops FROM 'bus_service_stops_seed.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

INSERT INTO bus_services (
    service_id, operator_name_en, operator_name_bn, variant_no_for_operator,
    start_stop_raw, end_stop_raw, stop_count, service_type, time_text,
    image_url, current_status, source_id
)
SELECT
    service_id, operator_name_en, NULLIF(operator_name_bn, ''), variant_no_for_operator,
    start_stop_raw, end_stop_raw, stop_count, NULLIF(service_type, ''), NULLIF(time_text, ''),
    NULLIF(image_url, ''), COALESCE(NULLIF(current_status, ''), 'needs_validation'), source_id
FROM staging_bus_services
ON CONFLICT (service_id) DO NOTHING;

INSERT INTO bus_service_stops (
    service_id, stop_sequence, stop_name_raw, normalized_stop_name,
    canonical_place_id, canonical_name_en, source_id
)
SELECT
    s.service_id, s.stop_sequence, s.stop_name_raw, s.normalized_stop_name,
    NULLIF(s.canonical_place_id, ''), NULLIF(s.canonical_name_en, ''), s.source_id
FROM staging_bus_service_stops s
JOIN bus_services b ON b.service_id = s.service_id
LEFT JOIN places p ON p.place_id = NULLIF(s.canonical_place_id, '')
WHERE NULLIF(s.canonical_place_id, '') IS NULL OR p.place_id IS NOT NULL
ON CONFLICT (service_id, stop_sequence) DO NOTHING;

COMMIT;
