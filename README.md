# StepUp — Fitness Web Dashboard

A light, green, modern fitness dashboard (React + Vite + TypeScript + Tailwind) with an optional Express API.

> **Demo data notice.** Every step count, distance, calorie, streak, leaderboard entry and buddy in this build is **sample data**.
> Nothing is read from a real step counter or health platform. The UI labels this everywhere (`DEMO DATA` chips and banners).
> Real activity records can be plugged in later through `frontend/src/services/activityService.ts`.

## Role of this branch

The Git branch is named `steup-website`. It contains the interactive StepUp web dashboard and its optional demonstration API. It is separate from the production-style Flutter Android application in [`Complete_Flutter_App`](https://github.com/DishaGoyal16/StepUp/tree/Complete_Flutter_App), which contains the Kotlin genuine-step engine and Firebase backend. It is also separate from [`Team_Website`](https://github.com/DishaGoyal16/StepUp/tree/Team_Website), which contains the earlier static project website, presentations, and UML diagrams.

## What this branch contains

| Path | Contents and purpose |
|---|---|
| `frontend/` | React, Vite and TypeScript dashboard with responsive pages for overview, activity, challenges, step battles, leaderboard, buddy discovery, rewards, profile, and authentication. |
| `frontend/src/data/demo.ts` | Central sample dataset used by the browser demonstration. |
| `frontend/src/services/` | Data-access boundary that selects local demo behavior or the optional API. This is the integration point for a future real activity service. |
| `backend/` | Express and TypeScript demonstration API with authentication, activity, challenge, leaderboard, user, validation, error-handling, and rate-limit routes. Its store is currently in memory. |
| `backend/prisma/schema.prisma` | Proposed PostgreSQL data model. The running API does not yet persist through Prisma. |
| `backend/Dockerfile` | Container definition for the optional API. |
| `AWS_DEPLOYMENT.md` | Deployment guide for a static frontend and optional API infrastructure. It is documentation only; no AWS resources are created by the repository. |
| `docs/` | Final project report and Gantt chart. |
| `.env.example`, `frontend/.env.example`, `backend/.env.example` | Environment-variable templates without private credentials. |

This branch is suitable for a browser-based demonstration and continued web development. It does not receive verified step records from the Android genuine-step engine, and its demo accounts, activity, battles, buddies, and rankings should not be presented as real student data.

## Run it

For setup, manual checks, and the commit workflow, see [Contributing](CONTRIBUTING.md).

Requires Node.js 20.19+ (tested on Node 24).

```bash
npm run install:all
```

```bash
npm run dev
```

Open **http://localhost:5173**

**Demo login:** `demo@stepup.app` / `demo1234` (or use the "Sign in as demo user" button).
You can also register a new account (stored only in your browser in demo mode).

The dashboard runs fully on its own — **no backend or database needed**.

### Optional: run with the Express API

```bash
npm run dev:api
```

API listens on http://localhost:4000. Then point the frontend at it:

```bash
# frontend/.env
VITE_API_URL=http://localhost:4000
```

Restart `npm run dev`. Login, activity, sessions, challenges and leaderboard now come from the API (still demo data on the server side).

## Production build

```bash
npm run build
```

- Frontend output: `frontend/dist/` (static files; deploy to S3 + CloudFront)
- Backend output: `backend/dist/` (run with `npm start --prefix backend`, or build the Docker image)

## Project structure

```
frontend/src/
  components/   reusable UI (ProgressRing, StatCard, charts, ui primitives)
  layouts/      AppLayout (sidebar, header, drawer, toasts)
  pages/        Overview, ActivityPage, ChallengesPage, BattlesPage, LeaderboardPage, BuddyPage, RewardsPage, ProfilePage, Auth
  data/demo.ts  ALL sample data lives here
  services/     data access layer (demo or API) — swap point for real data
  hooks/        useApp (state + persistence), useAsync, useStats
  lib/          formatting + stats helpers
backend/src/
  routes/ controllers/ middleware/ data/store.ts (in-memory demo store)
backend/prisma/schema.prisma   target PostgreSQL schema (not wired in yet)
```

## What works

| Area | Status |
|---|---|
| Login / register / logout, route protection | Working (local demo auth, or API when `VITE_API_URL` set) |
| Overview: progress ring, stats, weekly chart, recent activity, challenges, goal tracker, achievements | Working (demo data) |
| My Activity: week / month / 3-month ranges, average, best day, history with "goal days only" filter | Working |
| Challenges: filter, join, leave, progress | Working (saved in browser) |
| Step Battles: create, compare, rank, simulate a demo day, delete | Working (opponents/steps are simulated) |
| Leaderboard: weekly/monthly, podium, your live rank | Working |
| Sport Buddy: search, activity filter, "near me", connect/cancel | Working (requests are local only) |
| Rewards: points, streak claims, badges that react to your actions, milestones | Working |
| Profile & settings: edit profile, daily goal, units, notification toggles, reset demo data, logout | Working |
| Loading skeletons, empty and error states, responsive layout (drawer on mobile) | Working |
| Express API: health, auth, users, activity, challenges, leaderboard, validation, rate limit, error handling | Working (in-memory demo store) |

## What is NOT done (by design, for now)

- **No real activity source.** Steps are demo values. A web app cannot read Health Connect / HealthKit directly; real data must arrive via an API or an integration you add later.
- **No database.** The API uses an in-memory store (resets on restart). A Prisma/PostgreSQL schema is provided but not wired in.
- **No social backend.** Battles, buddy requests and joins are stored in the browser (localStorage); other users are sample profiles.
- Demo-mode auth is **not secure** (browser-only accounts). Use the API for anything beyond a demo.
- No automated tests yet.

## Backend API

Base path `/api`. Auth is a Bearer JWT.

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | no | Health check |
| POST | `/auth/register` | no | `{ name, email, password(8+) }` |
| POST | `/auth/login` | no | `{ email, password }` → `{ token, user }` |
| GET / PATCH | `/users/me` | yes | PATCH accepts `name, city, bio, dailyGoal, units` |
| GET | `/activity/history?days=` | yes | 1–365 days |
| GET | `/activity/sessions` | yes | |
| GET | `/challenges` | yes | |
| GET | `/leaderboard` | yes | |

Configuration is in `backend/.env.example` (`JWT_SECRET` is required in production).

## Deploying to AWS

See [AWS_DEPLOYMENT.md](AWS_DEPLOYMENT.md). Nothing has been created in AWS and nothing will be without your approval.
