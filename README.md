# StepUp

StepUp is a campus fitness and community application for students of Thapar Institute of Engineering and Technology. It combines verified step tracking with buddy discovery, fitness challenges, hostel and campus competitions, leaderboards, achievements, notifications, and friendly step competitions using virtual points.

The project gives special attention to activity integrity. Android's hardware step counter supplies raw steps, while a Kotlin sensor pipeline classifies supporting motion evidence. Steps move through raw, pending, verified, rejected, and suspicious states. Only verified steps are eligible for rankings, rewards, challenges, and competitions.

Project lead: **Disha**

See [Contributing to StepUp](CONTRIBUTING.md) for branch selection, validation expectations and deployment checks before publishing changes.

## Repository branches

The branches contain different stages and deliverables of the project. Branch names are case-sensitive.

| Branch | Purpose and contents | What the branch does | When to use it |
|---|---|---|---|
| [`main`](https://github.com/DishaGoyal16/StepUp/tree/main) | Repository guide and final academic documents in `docs/`, including the final project report and Gantt chart. | Acts as the landing page and explains how the repository is organized. | Start here when reviewing the complete project or its reports. |
| [`Complete_Flutter_App`](https://github.com/DishaGoyal16/StepUp/tree/Complete_Flutter_App) | Integrated Flutter Android application, native Kotlin genuine-step engine, Firebase Cloud Functions, Firestore and Storage rules, emulator setup, automated tests, demo scripts, and technical documentation. | Runs the current end-to-end StepUp application. It provides authentication, onboarding, verified steps, buddies, challenges, virtual-point bets, leaderboards, profiles, notifications, achievements, and administration features. | Use this branch for development, testing, demonstrations, and future deployment. This is the primary application branch. |
| [`steup-website`](https://github.com/DishaGoyal16/StepUp/tree/steup-website) | React, Vite and TypeScript fitness dashboard with a responsive UI, browser demo mode, optional Express API, in-memory server data, a target Prisma/PostgreSQL schema, Docker setup, and AWS deployment guidance. | Runs an interactive web demonstration of StepUp features such as activity history, challenges, step battles, leaderboards, buddy discovery, rewards, profile settings, and authentication flows. All activity and social data are currently demonstrations. | Use it to present or develop the StepUp web dashboard. Real verified steps and the production backend remain in the Android/Firebase architecture on `Complete_Flutter_App`. |
| [`App`](https://github.com/DishaGoyal16/StepUp/tree/App) | Earlier Flutter prototype built with Riverpod, Hive, Health APIs, motion sensors, and local repositories. | Demonstrates the original application screens, local demo user, activity integrity baseline, gamification, sessions, sport matching, challenges, bets, wallet, and settings. Its data is primarily local to the device. | Use it to study the earlier prototype and UI direction. It is not the current integrated application. |
| [`Backend`](https://github.com/DishaGoyal16/StepUp/tree/Backend) | An early Node.js backend scaffold with Express, PostgreSQL, file-upload and environment packages, together with website and presentation files. | Establishes backend dependencies, but the branch currently has no server entry point, routes, database schema, or deployed API implementation. | Keep it as historical backend setup work. The implemented backend used by the current app is in `Complete_Flutter_App/functions`. |
| [`Frontend`](https://github.com/DishaGoyal16/StepUp/tree/Frontend) | Initial placeholder branch containing the original short README. | Records the beginning of the frontend work and does not contain the Flutter application source. | Use only for repository history. Current frontend work is in `Complete_Flutter_App`, and the older prototype is in `App`. |
| [`Team_Website`](https://github.com/DishaGoyal16/StepUp/tree/Team_Website) | Static StepUp project website, combined presentation, planning presentations, UML diagrams, class diagram, and sequence diagrams. | Presents the project concept, architecture, planning, team material, and visual design in a browser-friendly format. | Use it for presentations, project explanation, and architecture visuals. |

## Current application architecture

The `Complete_Flutter_App` branch contains the current integrated architecture.

| Layer | Main location | Responsibility |
|---|---|---|
| Flutter application | `lib/` | Material 3 interface, routing, state, domain models, feature screens, repositories, and Firebase adapters. |
| Android step verification | `android/stepup_core/` and `android/app/` | Hardware step-counter ingestion, accelerometer and gyroscope analysis, activity classification, verified-step ledger, foreground service, reboot recovery, and Flutter platform channels. |
| Backend | `functions/` | TypeScript callable functions, validation, idempotent step synchronization, buddy and challenge operations, virtual-points transactions, rewards, rankings, notifications, and administrative operations. |
| Firebase configuration | `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json` | Authorization rules, protected verified-step data, indexes, and local emulator configuration. |
| Verification | `test/`, `integration_test/`, `android/stepup_core/src/test/`, `functions/test/` | Flutter tests, device integration flows, native step-engine regression tests, backend tests, and security-rule tests. |

The backend treats the mobile client as untrusted for reward-bearing data. Clients cannot directly assign verified steps, points, winners, rewards, or administrator privileges. Step synchronization uses deterministic records and server-side validation to prevent duplicate credit.

## Main application features

- Thapar email registration, email verification, onboarding, hostel selection, privacy settings, and role-based administration.
- Raw, verified, pending, rejected, and suspicious step totals with a separate verified-step ledger.
- Buddy discovery, filters, requests, accepted connections, and buddy challenges.
- Individual, buddy, inter-hostel, and campus-wide fitness challenges.
- Friendly step competitions using virtual points only.
- Daily, weekly, monthly, campus, hostel, buddy, and challenge leaderboards.
- Achievements, streaks, notifications, profile editing, and profile photos.
- Light fitness design with Home, Buddies, Challenges, Leaderboard, and Profile navigation.

## Running the current application

Switch to the integrated branch and follow its setup guide:

```bash
git clone --branch Complete_Flutter_App https://github.com/DishaGoyal16/StepUp.git
cd StepUp
```

Read these files before running it:

- [`README.md`](https://github.com/DishaGoyal16/StepUp/blob/Complete_Flutter_App/README.md) for source layout and basic commands.
- [`DEMO_GUIDE.md`](https://github.com/DishaGoyal16/StepUp/blob/Complete_Flutter_App/DEMO_GUIDE.md) for a live phone demonstration using a laptop hotspot and local Firebase emulators.
- [`FIREBASE_SETUP.md`](https://github.com/DishaGoyal16/StepUp/blob/Complete_Flutter_App/FIREBASE_SETUP.md) for connecting a real Firebase project.
- [`TESTING_GUIDE.md`](https://github.com/DishaGoyal16/StepUp/blob/Complete_Flutter_App/TESTING_GUIDE.md) for Flutter, Android, backend, emulator, and device testing.
- [`IMPLEMENTATION_PROGRESS.md`](https://github.com/DishaGoyal16/StepUp/blob/Complete_Flutter_App/IMPLEMENTATION_PROGRESS.md) for implemented features and recorded verification results.
- [`KNOWN_LIMITATIONS.md`](https://github.com/DishaGoyal16/StepUp/blob/Complete_Flutter_App/KNOWN_LIMITATIONS.md) for current technical limits.

The repository does not include private Firebase credentials. The professor-demo workflow uses the Firebase Emulator Suite and can run without a paid Firebase plan. A real remote deployment requires creating a Firebase project, supplying its configuration, deploying the rules and functions, and validating the deployment separately.

## Running the web dashboard

The `steup-website` branch is a separate browser application. It can run entirely with browser demo data, or it can use its optional in-memory Express API.

```bash
git clone --branch steup-website https://github.com/DishaGoyal16/StepUp.git StepUp-Website
cd StepUp-Website
npm run install:all
npm run dev
```

Open `http://localhost:5173`. See the branch's [`README.md`](https://github.com/DishaGoyal16/StepUp/blob/steup-website/README.md) for demo login details, API mode, production builds, project structure, and known limitations. See [`AWS_DEPLOYMENT.md`](https://github.com/DishaGoyal16/StepUp/blob/steup-website/AWS_DEPLOYMENT.md) for deployment planning.

## Step-verification status

The genuine-step engine has automated native tests and has been replayed against real recordings from a realme RMX3990. Recorded phone-shaking tests were rejected, and several walking recordings improved through calibration. Walking retention still varies with carrying position and motion pattern, especially with the phone in a pocket. The current evidence demonstrates an engineering prototype with anti-shake behavior and measured limitations; it is not a universal accuracy certification across all phones, users, vehicles, and movement types.

## Recommended branch workflow

1. Use `main` for repository-level documentation and final academic reports.
2. Develop and test the product in `Complete_Flutter_App`.
3. Develop and demonstrate the browser dashboard in `steup-website`.
4. Treat `App`, `Backend`, and `Frontend` as historical development branches.
5. Maintain presentation and architecture assets in `Team_Website`.
6. Merge or cherry-pick into `main` only when repository-level documentation or final deliverables need updating.

## Academic documents

- [Final project report](docs/final_project_report.pdf)
- [Gantt chart](docs/gantt_chart.pdf)

## Project scope

StepUp is intended for campus fitness, community participation, and academic evaluation. Friendly competitions use virtual points. No real-money deposits, withdrawals, or gambling features are part of the project.
