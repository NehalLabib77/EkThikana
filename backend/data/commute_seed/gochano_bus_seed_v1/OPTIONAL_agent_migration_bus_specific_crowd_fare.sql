-- OPTIONAL: coding-agent-reviewed migration.
-- Not part of the seed import. Do not run automatically.
-- Enables future crowd fare aggregates to remain bus-service-specific.

BEGIN;

ALTER TABLE crowd_fare_aggregates
    ADD COLUMN IF NOT EXISTS bus_service_id text;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'crowd_fare_aggregates_bus_service_id_fkey'
    ) THEN
        ALTER TABLE crowd_fare_aggregates
            ADD CONSTRAINT crowd_fare_aggregates_bus_service_id_fkey
            FOREIGN KEY (bus_service_id) REFERENCES bus_services(service_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_crowd_fare_bus_service_lookup
ON crowd_fare_aggregates (
    transport_mode, bus_service_id, origin_place_id, destination_place_id
);

COMMIT;
