# StepUp — AWS Deployment Guide (preparation only)

> **Nothing has been created in AWS.** This is a plan and a set of copy-paste templates for when you decide to deploy.
> Several steps below create billable resources — each is flagged **💰**. Do the local testing first.

## Target architecture

```
Browser ──► CloudFront ──► S3 (private bucket, static frontend)
   │
   └──────► HTTPS API ──► AWS App Runner (backend container from ECR)
                              │
                              └──► RDS PostgreSQL (private subnets)
```

| Layer | Service | Why |
|---|---|---|
| Frontend | S3 + CloudFront | Static SPA hosting, HTTPS, caching |
| Backend | App Runner | Runs the Docker image with minimal ops |
| Database | RDS PostgreSQL | Managed Postgres (needed once the API leaves demo mode) |
| Secrets | Secrets Manager (or SSM Parameter Store) | `JWT_SECRET`, `DATABASE_URL` |
| Images | ECR | Stores the backend image |

> **Check availability first.** AWS adjusts which services accept new customers. Before building on App Runner, confirm it is
> available for your account in the AWS console. Alternatives that use the same Docker image: ECS on Fargate, or Lightsail containers.

## 0. Before you deploy — readiness checklist

The app is currently a **demo build**. For anything beyond a showcase:

- [ ] The API runs on an **in-memory store** (resets on restart, and breaks with more than one instance). Implement the data layer in
      `backend/src/data/store.ts` with Prisma against RDS (schema: `backend/prisma/schema.prisma`).
- [ ] Activity data is **sample data**. Decide the real source (mobile app upload, partner API, etc.) and implement it in the
      activity endpoints + `frontend/src/services/activityService.ts`. Set `IS_DEMO_DATA = false` in `frontend/src/services/http.ts` only when real.
- [ ] Set a strong `JWT_SECRET` (the server refuses to start in production without one).
- [ ] Decide on a domain name and HTTPS certificate (ACM, `us-east-1` for CloudFront).
- [ ] Set an **AWS Budget alert** before creating anything.

## 1. Prerequisites

- AWS account + an IAM user/role with least-privilege permissions (avoid using the root user).
- AWS CLI v2 configured: `aws configure --profile stepup`
- Docker Desktop (to build the backend image).
- Pick one region (examples use `ap-south-1`; replace as needed). CloudFront certificates must be in `us-east-1`.

Set shell variables used below:

```bash
export AWS_PROFILE=stepup
export AWS_REGION=ap-south-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export BUCKET=stepup-frontend-$ACCOUNT_ID
```

## 2. Frontend → S3 + CloudFront

### 2.1 Build

Set the API URL (known after step 3; you can build a first time with it empty to run in demo mode):

```bash
echo "VITE_API_URL=https://YOUR-APP-RUNNER-URL" > frontend/.env.production
npm run build --prefix frontend
```

### 2.2 Create a private S3 bucket 💰 (pennies/month)

```bash
aws s3api create-bucket --bucket $BUCKET --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION
aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

(For `us-east-1` omit `--create-bucket-configuration`.)

### 2.3 CloudFront distribution 💰 (free tier available; usage-based)

Easiest through the console: **CloudFront → Create distribution**

- Origin: the S3 bucket, **Origin access: Origin Access Control (OAC)** → let AWS update the bucket policy.
- Default root object: `index.html`
- Viewer protocol: Redirect HTTP to HTTPS
- **Custom error responses (required for React Router):** map `403` and `404` → response page `/index.html`, HTTP `200`, TTL 0.
- Compression: on.

### 2.4 Upload

```bash
# Hashed assets: long cache
aws s3 sync frontend/dist s3://$BUCKET --delete \
  --exclude index.html --cache-control "public,max-age=31536000,immutable"
# HTML: always revalidate
aws s3 cp frontend/dist/index.html s3://$BUCKET/index.html --cache-control "no-cache"
```

After each release, invalidate: `aws cloudfront create-invalidation --distribution-id <ID> --paths "/index.html"`

## 3. Backend → ECR + App Runner

### 3.1 Build & push the image

```bash
aws ecr create-repository --repository-name stepup-api
aws ecr get-login-password | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker build -t stepup-api backend
docker tag stepup-api:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/stepup-api:latest
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/stepup-api:latest
```

### 3.2 Store secrets

```bash
aws secretsmanager create-secret --name stepup/jwt-secret \
  --secret-string "$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"
```

### 3.3 Create the App Runner service 💰 (billed while running, even when idle for provisioned memory)

Console: **App Runner → Create service → Container registry (ECR)** → image `stepup-api:latest`.

- Port: `4000`
- Health check: protocol **HTTP**, path **`/health`**
- Environment variables: `NODE_ENV=production`, `CORS_ORIGIN=https://<your-cloudfront-domain>`
- Secrets (from Secrets Manager): `JWT_SECRET`
- Instance: smallest size to start (0.25 vCPU / 0.5 GB); min instances 1.

Copy the service URL into `frontend/.env.production`, rebuild the frontend, and re-upload (step 2.4).

> Run **one instance** until the data layer is moved to PostgreSQL — the in-memory demo store is per-instance.

## 4. Database → RDS PostgreSQL 💰 (the most expensive piece; billed hourly)

Only needed after you implement the Prisma data layer.

- Engine: PostgreSQL, **smallest instance class** for testing (e.g. `db.t4g.micro`), Single-AZ for dev.
- **Not publicly accessible.** Place in private subnets; security group allows port 5432 only from the App Runner VPC connector's security group.
- App Runner needs a **VPC connector** to reach RDS.
- Store the connection string in Secrets Manager as `DATABASE_URL` and expose it to the service.
- Enable automated backups; use `npx prisma migrate deploy` from a CI step or a one-off task, not on app start.

## 5. Security checklist

- [ ] S3 bucket stays private (CloudFront OAC only).
- [ ] `JWT_SECRET` / `DATABASE_URL` only in Secrets Manager, never in the repo or image.
- [ ] `CORS_ORIGIN` set to the exact CloudFront (or custom) domain — no `*`.
- [ ] RDS not public; security groups scoped tightly.
- [ ] CloudWatch alarms on App Runner 5xx and RDS CPU/storage.
- [ ] AWS Budget alert in place.
- [ ] Consider AWS WAF on CloudFront if public (adds cost). The built-in rate limiter is per-instance only.

## 6. Cost awareness

Approximate cost drivers (check the AWS pricing pages for current numbers): RDS instance hours and storage, App Runner
provisioned memory and requests, CloudFront data transfer, a small amount for S3/ECR/Secrets Manager. Resources left running
accrue charges even with no traffic.

## 7. Teardown (to stop all charges)

Delete in this order: App Runner service → RDS instance (take a final snapshot only if needed) → CloudFront distribution
(disable, wait, delete) → S3 bucket (empty first) → ECR repository → Secrets Manager secrets.

## 8. Suggested order

1. Test everything locally (done: `npm run dev`, `npm run build`).
2. Decide the real activity data source and implement the Prisma data layer.
3. Create a budget alert.
4. Deploy frontend (S3 + CloudFront) in demo mode first — cheapest, lowest risk.
5. Deploy the API, then RDS.
