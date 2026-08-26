-- CommuteBD v3 - fix: deduplicate stop_aliases and brta_graph_edges,
-- then add NULLS NOT DISTINCT unique indexes on the natural key so future
-- upserts are idempotent. Migration is safe to run repeatedly.

-- 1. stop_aliases: dedupe on (raw_stop_name, normalized_stop_name,
--    canonical_place_id). canonical_place_id is NULL for unmatched rows;
--    NULLS NOT DISTINCT treats NULLs as equal, so two rows that differ
--    only in their other two columns but both have NULL canonical_place_id
--    will collapse.
WITH ranked AS (
    SELECT
        alias_id,
        ROW_NUMBER() OVER (
            PARTITION BY
                raw_stop_name,
                normalized_stop_name,
                canonical_place_id
            ORDER BY alias_id
        ) AS rn
    FROM public.stop_aliases
)
DELETE FROM public.stop_aliases
WHERE alias_id IN (
    SELECT alias_id FROM ranked WHERE rn > 1
);

-- 2. brta_graph_edges: dedupe on (route_id, from_place_id, to_place_id,
--    direction). None of these columns is null per the source CSV, but
--    we still use NULLS NOT DISTINCT for defensive consistency.
WITH ranked AS (
    SELECT
        edge_id,
        ROW_NUMBER() OVER (
            PARTITION BY
                route_id,
                from_place_id,
                to_place_id,
                direction
            ORDER BY edge_id
        ) AS rn
    FROM public.brta_graph_edges
)
DELETE FROM public.brta_graph_edges
WHERE edge_id IN (
    SELECT edge_id FROM ranked WHERE rn > 1
);

-- 3. Add unique indexes that allow the upsert importer to use the natural
--    key as the conflict target. NULLS NOT DISTINCT requires PG 15+, which
--    Supabase ships by default (verified PostgREST 14.x on PG 15+).
CREATE UNIQUE INDEX IF NOT EXISTS
    uq_stop_aliases_natural_key
ON public.stop_aliases (
    raw_stop_name,
    normalized_stop_name,
    canonical_place_id
) NULLS NOT DISTINCT;

CREATE UNIQUE INDEX IF NOT EXISTS
    uq_brta_graph_edges_natural_key
ON public.brta_graph_edges (
    route_id,
    from_place_id,
    to_place_id,
    direction
) NULLS NOT DISTINCT;
