"""Repository layer for the PostgreSQL-backed CommuteDB data.

Repositories in this package accept a SQLAlchemy ``Session`` and expose the
same dictionary shapes that the existing Supabase repository returns. Routers
are not supposed to import the ORM models directly — that keeps the migration
contained and keeps the routers' response format untouched.
"""