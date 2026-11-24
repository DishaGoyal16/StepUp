# StepUp deployment

This source baseline includes the S3-backed upload and download provider and the PostgreSQL draft-publishing fix. Install dependencies from the checked-in lockfile using Node.js 22 and `npm ci --omit=dev` in `backend/`.

## Services and configuration

- Serve the homepage and tracked public presentation files through Nginx. Keep backend code and credentials outside the web root.
- Run the backend with PM2 as an unprivileged user on a loopback port. Enable PM2 startup under systemd and run `pm2 save` after verifying the active process.
- Fill the environment template locally on the server. Use a private directory and mode 0600 for the real file. Use the existing Neon database over certificate-verified TLS. Review migrations separately and do not apply the sample schema automatically.
- For EC2, use an instance role with the required object permissions on a private S3 bucket. Keep public access blocked and leave the bucket name and region in server configuration. Use role credentials instead of access keys. Preserve existing storage keys when moving files.
- Terminate TLS in Nginx and keep the certificate and keys on the server. Configure the ACME webroot, renewal timer and reload hook. Validate with `nginx -t` and `certbot renew --dry-run`. Use a real site name or supported IP certificate in place of the example name.
- Protect admin downloads. The public presentation archive uses GitHub content. The admin publish button updates the administrative current-version record and does not expose uploads publicly.

## Release and recovery

1. Prepare a separate release directory. Install pinned dependencies, link the private environment file and start the candidate on an unused loopback port.
2. Verify the local Neon health endpoint, admin login, protected downloads and S3-backed uploads with an isolated test fixture. Check draft, publish and history behavior. Keep database changes in a separately reviewed migration.
3. Validate and reload Nginx when switching the upstream. Confirm HTTPS, the public site and protected paths again. Save the verified PM2 process list and retain the previous compatible S3-backed release for rollback.
4. Maintain encrypted database backups and private object backups with matching keys and checksums. Verify restore in an approved isolated target before relying on a backup. For an app regression, roll back the code and proxy configuration first.
5. Monitor EC2, EBS, public IPv4, S3, transfer, credits, certificate expiry and application logs. Keep backups, secrets and user uploads outside Git. Obtain approval before changing plan or adding paid resources.

## Public deliverables rollout

Apply the additive migration before running the candidate against the production
database. Rehearse restoring an encrypted backup first. Keep public access
disabled until private integration and authorization checks pass. Backfill only
separately approved legacy version IDs. No legacy records are enrolled by the
schema migration.

Both publishing paths record publication, while an administrator can withdraw
anonymous access without deleting the record or private S3 object. Previously
public versions remain listed when superseded. Drafts and withdrawn versions
are excluded from every public route.

After validating a proxy change, reload Nginx and allow its old workers to
drain. Use fresh HTTPS connections and require two consecutive expected catalog
responses within a bounded interval before replacing the homepage. If critical
checks fail, restore the prior proxy config and homepage. Keep the previous
compatible PM2 release available. Disable public reads using the environment flag
and restart the affected process if public exposure must be stopped.
