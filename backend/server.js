require("dotenv").config();

const crypto = require("crypto");
const express = require("express");
const cors = require("cors");
const multer = require("multer");
const { rateLimit } = require("express-rate-limit");
const path = require("path");
const pool = require("./db");
const storage = require("./storage");

const app = express();
app.set("trust proxy", "loopback");
const PORT = process.env.PORT || 4000;
const SESSION_MAX_AGE_MS = 8 * 60 * 60 * 1000;
const SESSION_SECRET = process.env.SESSION_SECRET || crypto.randomBytes(48).toString("hex");
const isProduction = process.env.NODE_ENV === "production";
const revokedSessions = new Map();
const allowedExtensions = new Set([".pdf", ".ppt", ".pptx", ".doc", ".docx", ".xls", ".xlsx", ".zip"]);
const upload = multer({
  storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, callback) => callback(null, allowedExtensions.has(path.extname(file.originalname).toLowerCase())),
});

if (isProduction && !process.env.SESSION_SECRET) throw new Error("SESSION_SECRET must be set in production.");
if (!process.env.SESSION_SECRET) console.warn("SESSION_SECRET is not set; generated sessions expire after a server restart.");
if (!isProduction) {
  app.use(cors());
}
app.use(express.json());
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: {
    message: "Too many login attempts. Please try again after 15 minutes."
  }
});

function parseCookies(header = "") {
  return header.split(";").reduce((cookies, part) => {
    const separator = part.indexOf("=");
    if (separator > 0) cookies[part.slice(0, separator).trim()] = decodeURIComponent(part.slice(separator + 1));
    return cookies;
  }, {});
}
function sign(value) { return crypto.createHmac("sha256", SESSION_SECRET).update(value).digest("base64url"); }
function makeSession(user) {
  const payload = Buffer.from(JSON.stringify({ id: user.id, name: user.name, email: user.email, role: user.role, exp: Date.now() + SESSION_MAX_AGE_MS })).toString("base64url");
  return `${payload}.${sign(payload)}`;
}
function readSession(req) {
  const token = parseCookies(req.headers.cookie).stepup_admin_session;
  if (!token || !token.includes(".")) return null;
  const tokenId = crypto.createHash("sha256").update(token).digest("hex");
  if (revokedSessions.has(tokenId)) return null;
  const [payload, signature] = token.split("."); const expected = sign(payload);
  if (signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  try {
    const user = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    return user.exp > Date.now() && ["admin", "instructor"].includes(user.role) ? user : null;
  } catch { return null; }
}
function sessionCookie(value, maxAge = SESSION_MAX_AGE_MS) {
  return [`stepup_admin_session=${encodeURIComponent(value)}`, "Path=/", "HttpOnly", "SameSite=Strict", `Max-Age=${Math.floor(maxAge / 1000)}`, ...(isProduction ? ["Secure"] : [])].join("; ");
}
function requireAdmin(req, res, next) {
  const user = readSession(req);
  if (!user) return res.status(401).json({ message: "Please sign in as an instructor or administrator." });
  req.user = user; next();
}
function parseAuthors(raw) {
  const authors = (Array.isArray(raw) ? raw : String(raw || "").split(",")).map((author) => String(author).trim()).filter(Boolean);
  if (!authors.length) throw new Error("At least one author is required.");
  return authors;
}
function isPublished(value) { return value === true || ["true", "on", "1"].includes(value); }

// Existing health checks remain available.
app.get("/", (_req, res) => res.json({ message: "StepUp Backend is running" }));
app.get("/api/db-test", async (_req, res) => {
  try { const result = await pool.query("SELECT NOW()"); res.json({ message: "Database connected successfully", time: result.rows[0].now }); }
  catch (error) { console.error("Database connection error:", error.message); res.status(500).json({ message: "Database connection failed" }); }
});

// Existing endpoint and credential verification, extended with an HttpOnly signed session cookie.
app.post("/api/auth/login", loginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ message: "Email and password are required" });
    const result = await pool.query("SELECT id, name, email, password_hash, role FROM users WHERE email = $1", [String(email).trim().toLowerCase()]);
    if (!result.rows.length) return res.status(401).json({ message: "Invalid email or password" });
    const user = result.rows[0]; const [salt, storedHash] = String(user.password_hash).split(":");
    if (!salt || !storedHash) return res.status(401).json({ message: "Invalid email or password" });
    const suppliedHash = crypto.scryptSync(password, salt, 64).toString("hex");
    const valid = storedHash.length === suppliedHash.length && crypto.timingSafeEqual(Buffer.from(storedHash, "hex"), Buffer.from(suppliedHash, "hex"));
    if (!valid) return res.status(401).json({ message: "Invalid email or password" });
    if (!["admin", "instructor"].includes(user.role)) return res.status(403).json({ message: "Access denied" });
    const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
    res.setHeader("Set-Cookie", sessionCookie(makeSession(safeUser)));
    res.json({ message: "Login successful", user: safeUser });
  } catch (error) { console.error("Login error:", error.message); res.status(500).json({ message: "Server error during login" }); }
});
app.get("/api/auth/me", requireAdmin, (req, res) => res.json({ user: req.user }));
app.post("/api/auth/logout", (req, res) => {
  const token = parseCookies(req.headers.cookie).stepup_admin_session;
  if (token) {
    revokedSessions.set(crypto.createHash("sha256").update(token).digest("hex"), Date.now() + SESSION_MAX_AGE_MS);
    for (const [tokenId, expiresAt] of revokedSessions) if (expiresAt < Date.now()) revokedSessions.delete(tokenId);
  }
  res.setHeader("Set-Cookie", sessionCookie("", 0));
  res.json({ message: "Logged out" });
});

// The dashboard route is protected; its distinct login route contains no administrative data.
app.get("/admin/login", (_req, res) => res.sendFile(path.join(__dirname, "public", "admin.html")));
app.get(["/admin", "/admin/"], (req, res) => {
  if (!readSession(req)) return res.redirect("/admin/login");
  return res.sendFile(path.join(__dirname, "public", "admin.html"));
});

app.get("/api/admin/deliverables", requireAdmin, async (_req, res) => {
  try {
    const result = await pool.query(`SELECT d.id, d.title, d.description, d.created_at, v.id AS version_id, v.version_number, v.presentation_date, v.authors, v.change_summary, v.published, v.created_at AS version_created_at, (SELECT COUNT(*)::int FROM versions all_versions WHERE all_versions.deliverable_id = d.id) AS version_count FROM deliverables d LEFT JOIN LATERAL (SELECT * FROM versions WHERE deliverable_id = d.id ORDER BY published DESC, created_at DESC, id DESC LIMIT 1) v ON TRUE ORDER BY COALESCE(v.created_at, d.created_at) DESC, d.id DESC`);
    res.json({ deliverables: result.rows });
  } catch (error) { console.error("List deliverables error:", error.message); res.status(500).json({ message: "Could not load deliverables" }); }
});

app.get("/api/admin/deliverables/:deliverableId/versions", requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(`SELECT v.id, v.version_number, v.presentation_date, v.authors, v.change_summary, v.published, v.created_at, creator.name AS created_by_name, COALESCE(json_agg(json_build_object('id', f.id, 'originalFilename', f.original_filename, 'mimeType', f.mime_type, 'fileSize', f.file_size, 'url', '/api/admin/files/' || f.id) ORDER BY f.id) FILTER (WHERE f.id IS NOT NULL), '[]') AS files FROM versions v LEFT JOIN users creator ON creator.id = v.created_by LEFT JOIN file_assets f ON f.version_id = v.id WHERE v.deliverable_id = $1 GROUP BY v.id, creator.name ORDER BY v.published DESC, v.created_at DESC, v.id DESC`, [req.params.deliverableId]);
    res.json({ versions: result.rows });
  } catch (error) { console.error("Version history error:", error.message); res.status(500).json({ message: "Could not load version history" }); }
});

app.post("/api/admin/deliverables/upload", requireAdmin, upload.single("file"), async (req, res) => {
  let savedFile; const client = await pool.connect();
  try {
    const { deliverableId, deliverableName, versionNumber, presentationDate, changeSummary } = req.body;
    if (!req.file) return res.status(400).json({ message: "A supported deliverable file is required." });
    if (!versionNumber || !presentationDate || !changeSummary) return res.status(400).json({ message: "Version number, presentation date, and change summary are required." });
    const authors = parseAuthors(req.body.authors); let targetId = Number(deliverableId) || null;
    await client.query("BEGIN");
    if (targetId) {
      const existing = await client.query("SELECT id FROM deliverables WHERE id = $1", [targetId]);
      if (!existing.rows.length) throw new Error("Selected deliverable does not exist.");
    } else {
      const title = String(deliverableName || "").trim(); if (!title) throw new Error("Enter a deliverable name or select an existing deliverable.");
      const created = await client.query("INSERT INTO deliverables (title, created_by) VALUES ($1, $2) RETURNING id", [title, req.user.id]); targetId = created.rows[0].id;
    }
    savedFile = await storage.save({ buffer: req.file.buffer, originalFilename: req.file.originalname });
    const publish = isPublished(req.body.published);
    if (publish) await client.query("UPDATE versions SET published = FALSE WHERE deliverable_id = $1 AND published = TRUE", [targetId]);
    const version = await client.query("INSERT INTO versions (deliverable_id, version_number, presentation_date, authors, change_summary, published, published_by, created_by) VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, $7) RETURNING id, version_number, published", [targetId, String(versionNumber).trim(), presentationDate, JSON.stringify(authors), changeSummary.trim(), publish, publish ? req.user.id : null]);
    await client.query("INSERT INTO file_assets (version_id, original_filename, storage_key, storage_url, mime_type, file_size) VALUES ($1, $2, $3, $4, $5, $6)", [version.rows[0].id, req.file.originalname, savedFile.storageKey, savedFile.storageUrl, req.file.mimetype, req.file.size]);
    if (publish) await client.query("UPDATE deliverables SET presentation_date = $2, version = $3, authors = $4::jsonb, change_summary = $5 WHERE id = $1", [targetId, presentationDate, version.rows[0].version_number, JSON.stringify(authors), changeSummary.trim()]);
    await client.query("COMMIT"); res.status(201).json({ message: "Version uploaded", deliverableId: targetId, version: version.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK");
    if (savedFile) {
      await storage.remove(savedFile.storageKey).catch(error => console.error("Storage cleanup failed:", error.name));
    }
    const conflict = error.code === "23505"; console.error("Upload version error:", error.message);
    res.status(conflict ? 409 : 400).json({ message: conflict ? "That version number already exists for this deliverable." : error.message || "Could not upload version" });
  } finally { client.release(); }
});

app.patch("/api/admin/versions/:versionId/publish", requireAdmin, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN"); const result = await client.query("SELECT * FROM versions WHERE id = $1 FOR UPDATE", [req.params.versionId]);
    if (!result.rows.length) throw new Error("Version not found."); const version = result.rows[0];
    await client.query("UPDATE versions SET published = FALSE WHERE deliverable_id = $1 AND published = TRUE", [version.deliverable_id]);
    await client.query("UPDATE versions SET published = TRUE, published_by = $2 WHERE id = $1", [version.id, req.user.id]);
    await client.query("UPDATE deliverables SET presentation_date = $2, version = $3, authors = $4::jsonb, change_summary = $5 WHERE id = $1", [version.deliverable_id, version.presentation_date, version.version_number, JSON.stringify(version.authors), version.change_summary]);
    await client.query("COMMIT"); res.json({ message: "Version published" });
  } catch (error) { await client.query("ROLLBACK"); console.error("Publish version error:", error.message); res.status(400).json({ message: error.message || "Could not publish version" }); }
  finally { client.release(); }
});

app.get("/api/admin/files/:assetId", requireAdmin, async (req, res) => {
  try {
    const result = await pool.query("SELECT original_filename, storage_key, mime_type FROM file_assets WHERE id = $1", [req.params.assetId]);
    if (!result.rows.length) return res.status(404).json({ message: "File not found" });
    const asset = result.rows[0]; const file = await storage.read(asset.storage_key);
    if (!file) return res.status(404).json({ message: "Stored file is unavailable" });
    const inlinePdf = path.extname(asset.original_filename).toLowerCase() === ".pdf" && asset.mime_type === "application/pdf";
    res.type(inlinePdf ? "application/pdf" : "application/octet-stream");
    res.setHeader("Cache-Control", "private, no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Content-Disposition", `${req.query.download === "1" || !inlinePdf ? "attachment" : "inline"}; filename*=UTF-8''${encodeURIComponent(asset.original_filename)}`); res.sendFile(file.path, (error) => {
      if (file.cleanup) file.cleanup().catch(error => console.error("Download cleanup failed:", error.name));
      if (error && !res.headersSent) res.status(error.statusCode || 500).json({ message: "Could not retrieve file" });
    });
  } catch (error) { console.error("Serve file error:", error.message); res.status(500).json({ message: "Could not retrieve file" }); }
});

app.use((error, _req, res, _next) => {
  if (error instanceof multer.MulterError) return res.status(400).json({ message: error.code === "LIMIT_FILE_SIZE" ? "Files must be 25 MB or smaller." : error.message });
  return res.status(400).json({ message: "Only PDF, Office, and ZIP deliverable files are accepted." });
});
const HOST = "127.0.0.1";

app.listen(PORT, HOST, (error) => {
  if (error) {
    console.error("Failed to start StepUp backend:", error);
    process.exit(1);
  }

  console.log(`StepUp Backend running on http://${HOST}:${PORT}`);
});
