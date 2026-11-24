const { Pool } = require("pg");

const databaseUrl = new URL(process.env.DATABASE_URL);

// Prevent URL SSL parameters from overriding TLS settings.
for (const param of [
  "sslmode",
  "sslcert",
  "sslkey",
  "sslrootcert",
  "ssl",
]) {
  databaseUrl.searchParams.delete(param);
}

const pool = new Pool({
  connectionString: databaseUrl.toString(),
  ssl: {
    rejectUnauthorized: true,
  },
});

module.exports = pool;