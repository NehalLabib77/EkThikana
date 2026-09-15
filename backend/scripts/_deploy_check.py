"""Pre-deployment check: verify schema and apply migration 002."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database.connection import get_sessionmaker
from sqlalchemy import text

TABLE_CHECK = "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = :name)"
COL_CHECK = "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = :tbl AND column_name = :col)"
IDX_CHECK = "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = :tbl AND indexname = :idx)"
FK_CHECK = "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = :fk)"

with get_sessionmaker()() as session:
    # Check bus_services table
    r = session.execute(text(TABLE_CHECK), {"name": "bus_services"})
    print("bus_services table exists:", r.scalar())

    # Check crowd_fare_aggregates
    r = session.execute(text(TABLE_CHECK), {"name": "crowd_fare_aggregates"})
    print("crowd_fare_aggregates table exists:", r.scalar())

    # Check bus_service_id column
    r = session.execute(text(COL_CHECK), {"tbl": "crowd_fare_aggregates", "col": "bus_service_id"})
    has_col = r.scalar()
    print("bus_service_id column exists:", has_col)

    # Check FK
    r = session.execute(text(FK_CHECK), {"fk": "crowd_fare_aggregates_bus_service_id_fkey"})
    has_fk = r.scalar()
    print("FK constraint exists:", has_fk)

    # Check index
    r = session.execute(text(IDX_CHECK), {"tbl": "crowd_fare_aggregates", "idx": "idx_crowd_fare_bus_service_lookup"})
    has_idx = r.scalar()
    print("Composite index exists:", has_idx)

    if not has_col or not has_fk or not has_idx:
        print("\nApplying migration 002...")
        migration_sql = open("migrations/002_add_bus_service_id_to_crowd_fare_aggregates.sql").read()
        session.execute(text(migration_sql))
        session.commit()
        print("Migration 002 applied successfully.")

        # Re-verify
        r = session.execute(text(COL_CHECK), {"tbl": "crowd_fare_aggregates", "col": "bus_service_id"})
        print("bus_service_id column exists:", r.scalar())
        r = session.execute(text(FK_CHECK), {"fk": "crowd_fare_aggregates_bus_service_id_fkey"})
        print("FK constraint exists:", r.scalar())
        r = session.execute(text(IDX_CHECK), {"tbl": "crowd_fare_aggregates", "idx": "idx_crowd_fare_bus_service_lookup"})
        print("Composite index exists:", r.scalar())
    else:
        print("\nMigration 002 already applied. No changes needed.")
