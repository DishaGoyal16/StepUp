BEGIN;
CREATE TABLE IF NOT EXISTS public_version_publications (
    version_id INTEGER PRIMARY KEY REFERENCES versions(id) ON DELETE CASCADE,
    first_published_at TIMESTAMPTZ,
    public_since TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);
COMMIT;
