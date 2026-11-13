#!/usr/bin/env node
/**
 * Seed hostels, the six individual challenge templates, the badge catalogue and adminSettings/global defaults.
 * Uses the SAME code as the `adminSeedDefaults` callable (functions/src/seed). Idempotent and non-destructive.
 *
 *   (cd functions && npm run build)          # compiles functions/lib
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/seed.js [--project demo-stepup]
 *
 * Against a real project use Application Default Credentials and `--project <id>`; no secrets are stored here.
 */
'use strict';

const path = require('path');
const fs = require('fs');

const fnDir = path.join(__dirname, '..', 'functions');
const seedModule = path.join(fnDir, 'lib', 'seed', 'index.js');
if (!fs.existsSync(seedModule)) {
  console.error('functions/lib is missing - run `npm run build` inside functions/ first');
  process.exit(1);
}

const admin = require(require.resolve('firebase-admin', { paths: [fnDir] }));
const { seedDefaults } = require(seedModule);

const i = process.argv.indexOf('--project');
const projectId = (i >= 0 && process.argv[i + 1]) || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'demo-stepup';
admin.initializeApp({ projectId });

seedDefaults(admin.firestore())
  .then((report) => {
    console.log(`seeded project ${projectId}:`, JSON.stringify(report));
  })
  .catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
