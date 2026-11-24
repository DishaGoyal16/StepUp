-- ============================================
-- STEPUP DATABASE SCHEMA
-- PostgreSQL
-- ============================================

-- 1. USERS
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'admin'
        CHECK (role IN ('admin', 'instructor')),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- 2. DELIVERABLES
CREATE TABLE IF NOT EXISTS deliverables (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    presentation_date DATE,
    version VARCHAR(50),
    authors JSONB,
    change_summary TEXT,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- 3. VERSIONS
CREATE TABLE IF NOT EXISTS versions (
    id SERIAL PRIMARY KEY,
    deliverable_id INTEGER NOT NULL
        REFERENCES deliverables(id) ON DELETE CASCADE,
    version_number VARCHAR(50) NOT NULL,
    presentation_date DATE,
    authors JSONB NOT NULL DEFAULT '[]'::jsonb,
    change_summary TEXT,
    published BOOLEAN NOT NULL DEFAULT FALSE,
    published_by INTEGER REFERENCES users(id),
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- 4. FILE ASSETS
CREATE TABLE IF NOT EXISTS file_assets (
    id SERIAL PRIMARY KEY,
    version_id INTEGER NOT NULL
        REFERENCES versions(id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    storage_key TEXT NOT NULL,
    storage_url TEXT,
    mime_type VARCHAR(100),
    file_size BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_deliverables_created_by
    ON deliverables(created_by);

CREATE INDEX IF NOT EXISTS idx_versions_deliverable_id
    ON versions(deliverable_id);

CREATE INDEX IF NOT EXISTS idx_file_assets_version_id
    ON file_assets(version_id);

-- A deliverable can have one current published version, while every
-- prior version remains in the versions and file_assets tables.
CREATE UNIQUE INDEX IF NOT EXISTS idx_versions_one_published_per_deliverable
    ON versions(deliverable_id)
    WHERE published;

CREATE UNIQUE INDEX IF NOT EXISTS idx_versions_unique_number_per_deliverable
    ON versions(deliverable_id, version_number);

-- Backwards-compatible upgrades for databases created by an older schema.
ALTER TABLE versions ADD COLUMN IF NOT EXISTS presentation_date DATE;
ALTER TABLE versions ADD COLUMN IF NOT EXISTS authors JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE versions ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id);
