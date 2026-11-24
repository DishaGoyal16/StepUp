const express = require("express");
const { rateLimit } = require("express-rate-limit");

async function recordPublication(client, versionId) {
  await client.query(
    `INSERT INTO public_version_publications (version_id, first_published_at)
     VALUES ($1, now()) ON CONFLICT (version_id) DO NOTHING`,
    [versionId]
  );
}

async function withdrawPublication(executor, versionId) {
  const result = await executor.query(
    `UPDATE public_version_publications SET revoked_at = COALESCE(revoked_at, now())
     WHERE version_id = $1`,
    [versionId]
  );
  return result.rowCount === 1;
}

function validId(value) {
  return typeof value === "string" && /^[1-9][0-9]{0,9}$/.test(value) && Number(value) <= 2147483647;
}

function createPublicRouter({ pool, storage, enabled }) {
  const router = express.Router();
  const notFound = res => res.status(404).json({ message: "Not found" });
  const limiter = limit => rateLimit({ limit, windowMs: 60_000, standardHeaders: "draft-7", legacyHeaders: false });
  router.use((_req, res, next) => {
    res.setHeader("Cache-Control", "no-store");
    if (!enabled) return notFound(res);
    next();
  });
  router.use(limiter(90));

  router.get("/deliverables", async (req, res) => {
    const after = req.query.after;
    if (after !== undefined && !validId(after)) return notFound(res);
    const { rows } = await pool.query(
      `SELECT d.id, d.title,
         (SELECT v.id FROM versions v JOIN public_version_publications p ON p.version_id = v.id
          WHERE v.deliverable_id = d.id AND v.published AND p.revoked_at IS NULL) AS "currentVersionId"
       FROM deliverables d
       WHERE d.id > $1 AND EXISTS (
         SELECT 1 FROM versions v JOIN public_version_publications p ON p.version_id = v.id
         WHERE v.deliverable_id = d.id AND p.revoked_at IS NULL
       ) ORDER BY d.id LIMIT 26`, [after || 0]
    );
    const deliverables = rows.slice(0, 25);
    res.json({ deliverables, next: rows.length > 25 ? deliverables.at(-1).id : null });
  });

  router.get("/deliverables/:deliverableId/versions", async (req, res) => {
    const { deliverableId } = req.params;
    const before = req.query.before;
    if (!validId(deliverableId) || (before !== undefined && !validId(before))) return notFound(res);
    const { rows } = await pool.query(
      `SELECT v.id, v.version_number AS "versionNumber", p.first_published_at AS "publishedAt",
          v.presentation_date::text AS "presentationDate", v.authors,
          v.change_summary AS "changeSummary", v.published AS current,
          COALESCE((SELECT json_agg(json_build_object('id', f.id, 'name', f.original_filename, 'size', f.file_size)
                                    ORDER BY f.id)
                    FROM file_assets f WHERE f.version_id = v.id), '[]'::json) AS files
       FROM versions v JOIN public_version_publications p ON p.version_id = v.id
       WHERE v.deliverable_id = $1 AND p.revoked_at IS NULL
         AND ($2::integer IS NULL OR v.id < $2)
       ORDER BY v.id DESC LIMIT 26`, [deliverableId, before || null]
    );
    if (!rows.length && before === undefined) return notFound(res);
    const versions = rows.slice(0, 25);
    res.json({ versions, next: rows.length > 25 ? versions.at(-1).id : null });
  });

  let activeDownloads = 0;
  router.get("/deliverables/:deliverableId/versions/:versionId/files/:assetId", limiter(20), async (req, res) => {
    const { deliverableId, versionId, assetId } = req.params;
    if (![deliverableId, versionId, assetId].every(validId)) return notFound(res);
    const result = await pool.query(
      `SELECT f.original_filename, f.storage_key
       FROM file_assets f JOIN versions v ON v.id = f.version_id
       JOIN public_version_publications p ON p.version_id = v.id
       WHERE f.id = $1 AND v.id = $2 AND v.deliverable_id = $3 AND p.revoked_at IS NULL`,
      [assetId, versionId, deliverableId]
    );
    if (!result.rowCount) return notFound(res);
    if (activeDownloads >= 4) return res.status(503).json({ message: "Downloads are busy. Try again shortly." });
    if (req.method === "HEAD") return res.status(405).set("Allow", "GET").end();
    activeDownloads++;
    let file;
    try {
      const asset = result.rows[0];
      file = await storage.read(asset.storage_key);
      if (!file) return notFound(res);
      if (res.destroyed) return;
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.attachment(asset.original_filename).type("application/octet-stream");
      await new Promise((resolve, reject) => {
        // sendFile completes its callback on success, error, or aborted transfer.
        res.sendFile(file.path, { cacheControl: false }, error => error ? reject(error) : resolve());
      });
    } finally {
      activeDownloads--;
      if (file?.cleanup) await file.cleanup().catch(error => console.error("Public download cleanup:", error.name));
    }
  });

  router.use((error, _req, res, next) => {
    if (res.headersSent) return next(error);
    if (res.destroyed) return;
    if (error.status === 416) return res.status(416).end();
    console.error("Public deliverables error:", error.name);
    res.status(503).json({ message: "Published deliverables are temporarily unavailable." });
  });
  return router;
}

module.exports = { createPublicRouter, recordPublication, withdrawPublication, validId };
