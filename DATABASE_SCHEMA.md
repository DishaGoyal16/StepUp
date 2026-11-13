# StepUp — Database schema, server API and native channel contract

This file is the **single source of truth** shared by the Flutter app (`lib/`), the Cloud Functions (`functions/`),
the Firestore rules (`firestore.rules`) and the Android bridge (`android/`). If you change a name here, change it
everywhere and update `CLAUDE.md`.

Conventions
* Region for all functions: **`asia-south1`** (constant `REGION` in `functions/src/config.ts` and `AppConfig.functionsRegion` in Dart).
* Timezone for day/week/month boundaries: **`Asia/Kolkata`** (`adminSettings/global.timezone`). `dayKey` = `YYYYMMDD` in that zone. `weekKey` = ISO week start date `YYYYMMDD` (Monday). `monthKey` = `YYYYMM`.
* All timestamps are Firestore `Timestamp`s written with `FieldValue.serverTimestamp()` or computed server-side. Step bucket times are epoch **milliseconds** (number) because they come from the sensor engine.
* **Clients never write any collection directly**, except `notifications/{id}.read` (own docs) and `users/{uid}/devices/{id}.fcmToken` is written through `registerDevice`. Everything else is a callable function (Admin SDK). Rules default-deny.
* Eligible user = Firebase Auth user with `token.email` ending `@thapar.edu` **and** `token.email_verified == true` and `users/{uid}.status == 'ACTIVE'`. Every callable except `createProfile` requires an existing profile.
* Errors: callables throw `HttpsError` with codes `unauthenticated`, `permission-denied`, `invalid-argument`, `failed-precondition`, `already-exists`, `not-found`, `resource-exhausted`. Message is human-readable; `details.reason` is a stable reason code.
* Idempotency: every ledger/result/reward document has a **deterministic ID** so retries and trigger re-delivery cannot double-pay.

## Collections

### `hostels/{hostelId}`  (read: eligible users; write: admin callables only)
`hostelId` is a stable slug (see table). Fields: `displayName`, `legacyName` (nullable), `block` (nullable), `category` (`'GENERAL'|'GIRLS'`), `active` (bool), `sortOrder` (int), `createdAt`, `updatedAt`.

| hostelId | displayName | legacyName | block | category |
|---|---|---|---|---|
| agira | Agira Hall | Hostel-A | – | GENERAL |
| amritam | Amritam Hall | Hostel-B | – | GENERAL |
| prithvi | Prithvi Hall | Hostel-C | – | GENERAL |
| neeram | Neeram Hall | Hostel-D | – | GENERAL |
| vyan | Vyan Hall | Hostel-H | – | GENERAL |
| tejas | Tejas Hall | Hostel-J | – | GENERAL |
| ambaram | Ambaram Hall | Hostel-K | – | GENERAL |
| viyat | Viyat Hall | Hostel-L | – | GENERAL |
| anantam | Anantam Hall | Hostel-M | – | GENERAL |
| vyom | Vyom Hall | Hostel-O | – | GENERAL |
| frf-g | Hostel-FRF/G | – | – | GENERAL |
| vasudha-e | Vasudha Hall - Block E | Hostel-E | E | GIRLS |
| vasudha-g | Vasudha Hall - Block G | Hostel-G | G | GIRLS |
| ira | Ira Hall | Hostel-I | – | GIRLS |
| ananta | Ananta Hall | Hostel-N | – | GIRLS |
| dhriti | Dhriti Hall (Hostel-PG) | – | – | GIRLS |
| vahni | Vahni Hall | Hostel-Q | – | GIRLS |
| pavani | Hostel-Pavani Hall | PG-2 | – | GIRLS |

(Seeded by `functions/src/seed/hostels.ts` and `lib/domain/hostel_seed.dart`; the Firestore copy is authoritative and admin-editable. Blocks are never merged.)

### `users/{uid}`  (read: owner only; write: functions only)
`displayName`, `email` (private, never copied to public data), `hostelId`, `block` (nullable), `fitnessLevel` (`BEGINNER|INTERMEDIATE|ADVANCED`), `sportsInterests` (string[] from the sports list), `preferredActivity`, `preferredTime` (`MORNING|AFTERNOON|EVENING|NIGHT|ANYTIME`), `goals` (string[]), `availability` (string[] of `MON..SUN`), `buddyType` (`INDIVIDUAL|GROUP|BOTH`), `bio` (≤160 chars), `photoUrl` (nullable), `dailyGoal` (int, default 10000, 1000..50000),
`privacy` {`discoverable`:true, `showHostel`:true, `showWeeklySteps`:true, `showOnLeaderboards`:true},
`notificationPrefs` {`buddy`:true, `challenges`:true, `bets`:true, `leaderboard`:true, `reminders`:true},
`pointsBalance` (int ≥0, available), `pointsReserved` (int ≥0, locked in bets), `lifetimeVerifiedSteps` (int),
`currentStreak`, `bestStreak` (int), `lastGoalDayKey`, `status` (`ACTIVE|SUSPENDED|DELETION_REQUESTED`), `role` (`'student'|'admin'`, mirrors the custom claim), `rewardDeviceId` (nullable), `createdAt`, `updatedAt`.
Never client-writable: `pointsBalance`, `pointsReserved`, `lifetimeVerifiedSteps`, `streak*`, `status`, `role`.

### `publicProfiles/{uid}`  (read: eligible users; write: functions only)
The only user data other students can see: `displayName`, `photoUrl`, `hostelId` (only if `privacy.showHostel`), `fitnessLevel`, `sportsInterests`, `preferredActivity`, `preferredTime`, `goals`, `availability`, `buddyType`, `bio`, `weeklyVerifiedSteps` (only if `privacy.showWeeklySteps`), `discoverable`, `showOnLeaderboards`, `updatedAt`. **Never** email, points, or location.

### `users/{uid}/devices/{deviceId}`  (read: owner; write: `registerDevice`)
`deviceId`, `model`, `platform:'android'`, `appVersion`, `fcmToken` (nullable), `isRewardDevice` (bool), `registeredAt`, `lastSeenAt`, `lastSeq`. One reward device per account; others are display-only (their buckets are stored with `rewardEligible:false`).

### `stepBuckets/{uid}_{deviceId}_{startMs}`  (read: owner; write: `syncStepBuckets` only)
`uid`, `deviceId`, `startMs`, `bootCount`, `rawDelta`, `clientCredited`, `serverCredited`, `state` (`VERIFIED|PARTIAL|REJECTED|UNWITNESSED`), `reason` (nullable), `flags` (string[]), `evidenceMode`, `carryMode`, `walkFraction`, `hops` ([{label, imuSteps}]), `dayKey`, `rewardEligible` (bool), `receivedAt`. Deterministic ID ⇒ duplicate sync is a no-op (`duplicates` in the result). The server can only **downgrade** a client claim: `serverCredited ≤ clientCredited ≤ rawDelta`.

### `dailyStepSummaries/{uid}_{dayKey}`  (read: owner; write: functions only)
`uid`, `dayKey`, `hostelId` (snapshot), `rawSteps` (sum rawDelta of accepted buckets), `verifiedSteps` (sum serverCredited, rewardEligible only), `rejectedSteps`, `unwitnessedSteps`, `pendingSteps` (always 0 server-side; pending exists only on device), `updatedAt`. **Only `verifiedSteps` feeds leaderboards, challenges, bets, rewards.**

### `leaderboards/{boardId}`  +  `leaderboards/{boardId}/entries/{entryId}`  (read: eligible users; write: functions only)
`boardId` = `CAMPUS_{periodKey}` where `period` ∈ `DAILY|WEEKLY|MONTHLY|ALL_TIME` and periodKey is `dayKey|weekKey|monthKey|ALL`, plus `HOSTELS_{periodKey}` for hostel ranking.
Board doc: `scope`, `period`, `periodKey`, `metricLabel`, `updatedAt`.
Student entry (`entryId`=uid): `uid`, `displayName`, `photoUrl`, `hostelId`, `verifiedSteps`, `showOnLeaderboards`, `updatedAt`.
Hostel entry (`entryId`=hostelId): `hostelId`, `displayName`, `totalVerifiedSteps`, `participants` (students with ≥1 verified step in the period), `averagePerParticipant` (= total/participants, 0 if none), `updatedAt`.
Maintained **idempotently by recomputation** (sum of that user's `dailyStepSummaries` for the period), never by blind increments. Hostel metric is always labelled; default ranking metric = `averagePerParticipant`, optional = `totalVerifiedSteps`.

### `buddyRequests/{fromUid}_{toUid}`  (read: participants; write: functions)
`fromUid`, `toUid`, `status` (`PENDING|ACCEPTED|REJECTED|CANCELLED`), `message` (≤120), `fromName`, `fromPhotoUrl`, `createdAt`, `respondedAt`. Deterministic ID prevents duplicate requests; re-requesting after REJECTED/CANCELLED is allowed after 24 h.
### `buddyConnections/{minUid}_{maxUid}`  (read: participants; write: functions)
`uids` ([a,b] sorted), `createdAt`, `active` (bool). Remove ⇒ `active:false`.

### `challenges/{challengeId}`  (read: eligible users, except `BUDDY` challenges readable by participants only; write: functions)
`type` (`INDIVIDUAL|BUDDY|INTER_HOSTEL|CAMPUS`), `title`, `description`, `metric` (`TOTAL_STEPS|DAILY_TARGET_DAYS|STREAK_DAYS`), `target` (int: steps for TOTAL_STEPS; days for the other two), `dailyTarget` (int steps/day for the two day-based metrics, else null), `windowMode` (`FIXED|ROLLING`), `startAt`, `endAt` (FIXED; day-aligned in IST), `durationDays` (ROLLING and BUDDY), `status` (`PENDING|UPCOMING|ACTIVE|COMPLETED|CANCELLED`; `PENDING` = buddy invite not yet accepted), `createdBy` (uid or `'system'`/admin uid), `hostelIds` (INTER_HOSTEL: competing hostel ids), `hostelAggregation` (`AVERAGE_PER_PARTICIPANT|TOTAL`), `maxParticipants` (nullable), `participantCount`, `rewardPoints` (winner/completion points), `isTemplate` (bool; INDIVIDUAL catalogue entries), `winnerUid`/`winnerHostelId` (set once at finalize), `finalizedAt`, `createdAt`, `updatedAt`.
Individual catalogue (seeded): 5,000 Steps Daily; 10,000 Steps Daily; 50,000 Steps Weekly; 100,000 Steps Weekly; 7-Day Walking Streak; 30-Day Fitness Challenge. Seeded campus/hostel/buddy templates are listed in `functions/src/seed/challenges.ts`.
### `challengeParticipants/{challengeId}_{uid}`  (read: owner, and participants of the same challenge via `getChallengeLeaderboard` only; write: functions)
`challengeId`, `uid`, `displayName`, `photoUrl`, `hostelId`, `status` (`INVITED|JOINED|LEFT|COMPLETED`), `joinedAt`, `windowStart`, `windowEnd` (ROLLING: set at join), `progress` (int per metric), `progressUpdatedAt`, `completedAt`, `rewardPaid` (bool). Deterministic ID prevents duplicate joins. Progress is **computed only by functions** from `dailyStepSummaries.verifiedSteps` inside the window (never from client numbers).
### `challengeResults/{challengeId}`  (read: eligible users who can read the challenge; write: functions at finalize)
`challengeId`, `type`, `winnerUid`, `winnerHostelId`, `ranking` ([{rank, uid|hostelId, name, value}] top 50), `participantCount`, `finalizedAt`, `metricLabel`. Existence of this doc makes finalize idempotent.

### `stepBets/{betId}`  (read: the two participants; write: functions)
`challengerUid`, `opponentUid`, `challengerName`, `opponentName`, `targetSteps`, `durationDays` (1..30), `stakePoints` (10..1000 virtual points, each), `status` (`PENDING|ACTIVE|DECLINED|CANCELLED|EXPIRED|COMPLETED`), `startAt`, `endAt` (day-aligned IST; start = next IST midnight after acceptance), `challengerSteps`, `opponentSteps` (functions-maintained, verified only), `winnerUid` (nullable; null on draw/refund), `resolution` (`HIGHER_STEPS|ONLY_ONE_REACHED_TARGET|REFUND_NONE_REACHED|REFUND_TIE`), `createdAt`, `respondedAt`, `settledAt`, `expiresAt` (PENDING expires after 48 h).
Rule: at `endAt` + grace: both reached target ⇒ higher verified steps wins (tie ⇒ refund); exactly one reached ⇒ that one wins; none ⇒ refund. **Virtual points only. No currency.**
### `virtualPointsLedger/{entryId}`  (read: owner; write: functions)
`uid`, `delta` (signed int; for RESERVE/RELEASE it moves between available and reserved), `type` (`RESERVE|RELEASE|BET_WIN|BET_LOSS|REWARD|ADJUSTMENT`), `refType` (`BET|CHALLENGE|DAILY_GOAL|STREAK|BADGE|ADMIN`), `refId`, `balanceAfter`, `reservedAfter`, `note`, `createdAt`. `entryId` = `{refType}_{refId}_{uid}_{type}` ⇒ idempotent. Balance mutations happen only inside Firestore transactions that also create the ledger doc (create fails if it exists ⇒ no double spend/pay).

### `achievements/{uid}_{badgeId}`  (read: owner; write: functions)
`uid`, `badgeId` (`FIRST_1K|TEN_K_WALKER|STREAK_7|CHALLENGE_CHAMPION|HOSTEL_CHAMPION|CAMPUS_FITNESS_STAR`), `awardedAt`, `refId`. Badge catalogue in `adminSettings/badges` (title, description, icon, rule text, `points`).
### `notifications/{id}`  (read/update-`read`-only: owner; create: functions)
`uid`, `type` (`BUDDY_REQUEST|BUDDY_ACCEPTED|CHALLENGE_NEW|CHALLENGE_REMINDER|CHALLENGE_DONE|LEADERBOARD|BET_INVITE|BET_RESULT|HOSTEL_RESULT|SYSTEM`), `title`, `body`, `data` (map), `read` (bool), `dedupeKey` (doc ID = `{uid}_{dedupeKey}` ⇒ no repeats), `createdAt`. FCM push is sent in the same function if the user's `notificationPrefs` allow and a token exists.
### `reports/{reportId}`  (read: admin; create via `reportProfile`)
`reporterUid`, `targetUid`, `reason`, `details`, `status` (`OPEN|DISMISSED|ACTIONED`), `resolvedBy`, `createdAt`, `resolvedAt`.
### `riskEvents/{id}`  (read: admin; write: functions) — suspicious step activity for review
`uid`, `kind` (`HARD_LIMIT|DAILY_CAP|DOWNGRADE|ROBOTIC|MANY_REJECTIONS|DEVICE_MISMATCH`), `detail` (map), `status` (`OPEN|REVIEWED|CLEARED`), `dayKey`, `createdAt`.
### `adminSettings/{doc}` (read: eligible users for `global`/`badges`; write: admin callables)
`global`: `timezone`, `dailyGoalDefault`, `maxStepsPerBucket`:35, `maxStepsPer30Min`:6300, `maxRewardStepsPerDay`:20000, `maxBucketAgeHours`:72, `futureToleranceSec`:120, `settlementGraceHours`:6, `pointsDailyGoal`:10, `pointsStreak7`:50, `pointsChallengeComplete`:50, `pointsChallengeWin`:100, `betMinStake`:10, `betMaxStake`:1000, `betExpiryHours`:48. `badges`: map of badge definitions. `admins`: audit list of role changes.

## Callable function API (`asia-south1`)

| Callable | Params → Result |
|---|---|
| `createProfile` | profile fields → `{ok, profile}` (token must be verified @thapar.edu; idempotent) |
| `updateProfile` | partial editable fields (not points/status/role/email) → `{ok}` |
| `requestAccountDeletion` | `{}` → `{ok}` sets status `DELETION_REQUESTED`, notifies admins via `reports`-style queue |
| `registerDevice` | `{deviceId, model, appVersion, fcmToken?}` → `{isRewardDevice}` |
| `syncStepBuckets` | `{deviceId, buckets:[{startMs,bootCount,rawDelta,credited,state,reason,walkFraction,evidenceMode,carryMode,hops:[{label,imuSteps}]}]}` (≤200) → `{accepted, duplicates, rejected:[{startMs,reason}], today:{verifiedSteps,rawSteps,rejectedSteps,unwitnessedSteps}}` |
| `searchBuddies` | `{fitnessLevel?, sports?:[], hostelId?, preferredTime?, goals?:[], availability?:[], buddyType?, query?, limit?, cursor?}` → `{profiles:[publicProfile+uid+relation], nextCursor}`; excludes self; `relation` ∈ `NONE|REQUEST_SENT|REQUEST_RECEIVED|BUDDY` |
| `sendBuddyRequest` / `respondBuddyRequest` / `cancelBuddyRequest` / `removeBuddy` | `{toUid,message?}` / `{requestId,accept}` / `{requestId}` / `{buddyUid}` → `{ok}` |
| `reportProfile` | `{targetUid, reason, details?}` → `{ok}` |
| `createBuddyChallenge` | `{buddyUid, title?, durationDays, targetSteps}` → `{challengeId}` (status PENDING until accepted; starts next IST midnight after acceptance) |
| `respondChallengeInvite` | `{challengeId, accept}` → `{ok}` |
| `joinChallenge` / `leaveChallenge` | `{challengeId}` → `{ok, participant}` |
| `getChallengeLeaderboard` | `{challengeId, limit?}` → `{entries:[{rank,uid|hostelId,name,photoUrl,hostelId,value,progressPct}], me:{rank,value}, metricLabel}` |
| `createStepBet` | `{opponentUid, targetSteps, durationDays, stakePoints, requestId?}` (`requestId` = `^[A-Za-z0-9-]{8,40}$`, client-generated retry key) → `{betId, duplicate}`; ledger docs may also carry `reservedDelta` (reserves challenger stake; opponent must be an active buddy) |
| `respondStepBet` | `{betId, accept}` → `{ok}` (accept reserves opponent stake & activates) |
| `cancelStepBet` | `{betId}` → `{ok}` (challenger, PENDING only; releases stake) |
| `getLeaderboard` | `{scope:'CAMPUS'|'MY_HOSTEL'|'HOSTELS'|'BUDDIES', period:'DAILY'|'WEEKLY'|'MONTHLY'|'ALL_TIME', hostelMetric?:'AVERAGE'|'TOTAL', limit?}` → `{entries, me:{rank,value}, metricLabel, periodKey, updatedAt}` |
| `markNotificationsRead` | `{ids?:[]}` (none = all) → `{ok}` |
| Admin: `adminUpsertHostel`, `adminSetHostelActive`, `adminCreateChallenge`, `adminCancelChallenge`, `adminListStudents`, `adminSetUserRole`, `adminSuspendUser`, `adminListReports`, `adminResolveReport`, `adminListRiskEvents`, `adminResolveRiskEvent`, `adminSetSettings`, `adminUpsertBadge`, `adminStats`, `adminSeedDefaults` | all require `request.auth.token.admin === true`; every call is audit-logged to `adminSettings/admins` / `adminAudit` |

## Scheduled and trigger functions
* `onDailySummaryWritten` (Firestore trigger on `dailyStepSummaries`): recompute that user's leaderboard entries (daily/weekly/monthly/all-time), hostel entries, challenge progress for the user's active participations, bet step totals, daily-goal reward, streak, badges. All idempotent.
* `finalizeChallenges` (every 15 min): finalize ended challenges after `settlementGraceHours`; write `challengeResults`, award points/badges/notifications once.
* `settleStepBets` (every 15 min): settle ended bets, expire PENDING bets after 48 h (release stakes).
* `challengeReminders` (daily 18:00 IST): at most one reminder per user/challenge/day via `dedupeKey`.
* `refreshWeeklySteps` (hourly): updates `publicProfiles.weeklyVerifiedSteps`.
* `beforeUserCreated` (Auth blocking, Identity Platform): reject non-`@thapar.edu` emails. (Callable/rules checks remain the authoritative second layer.)

## Server-side step validation (`functions/src/steps/validateBatch.ts`, port of v2 §8.3 + `BucketVerifier.kt`)
Per bucket: `startMs` multiple of 10,000; not older than 72 h; not more than 120 s in the future; `rawDelta` 1..35 (else rejected `CADENCE_EXCEEDED`); rolling 30-minute sum ≤ 6,300; recompute credit with the Kotlin rule using the supplied 5 hops: coverage ≥ 0.8 else `UNWITNESSED`; walk fraction (WALK/RUN) ≥ 0.5 else `REJECTED`; `credited = min(raw, floor(1.15 × Σ imuSteps of walk hops))`; **serverCredited = min(clientCredited, recomputed)**. Per day reward cap 20,000 (excess stored but `rewardEligible:false`). Non-reward device ⇒ `rewardEligible:false`. Violations also open `riskEvents`.
Honest limit: the server cannot re-observe the sensor stream; a rooted/instrumented device can fabricate hop evidence. L6 attestation/Play Integrity is **not** implemented (documented in `KNOWN_LIMITATIONS`).

## Android ⇄ Flutter channel contract
`MethodChannel('edu.thapar.stepup/engine')`:
* `getCapabilities` → `{stepCounter, accelerometer, gyroscope, activityRecognitionGranted, notificationsGranted, evidenceMode, sdkInt, model}`
* `startTracking` → `{started, reason?}` (`PERMISSION_DENIED`, `NO_STEP_COUNTER`); `stopTracking` → `{}`; `isTracking` → bool
* `getTodaySummary {dayStartMs, dayEndMs}` → `{raw, verified, pending, rejected, suspicious, unwitnessed, gap}` from the engine ledgers (bucket start in range); `suspicious` = rejected steps whose reason ∈ {SHAKE_PATTERN, CADENCE_EXCEEDED, VEHICLE_MOTION, IN_VEHICLE, ON_BICYCLE}
* `getBucketsForSync {limit}` → settled buckets not yet acknowledged: `[{startMs, bootCount, rawDelta, credited, state, reason, walkFraction, evidenceMode, carryMode, hops:[{label,imuSteps}], lateRawAdded, lateCreditedAdded}]`
* `ackBuckets {startMsList}` → `{acked}` (idempotent; persisted natively)
* `getLiveStatus` → `{tracking, liveLabel, carryMode, lastRejection}`
* `bindUser {uid}` → `{bound:true, changed, sinceMs}`: binds the engine ledger view to the signed-in student. Dart must call it after sign-in and BEFORE `startTracking`/sync/summary. On a different uid, `sinceMs` moves to now (10 s floor); `getTodaySummary` and `getBucketsForSync` then only cover buckets with `startMs >= sinceMs`, so one student's steps never sync under another account. Blank/whitespace uid → channel error `BAD_ARGUMENTS`.
* `getDeviceId` → stable random per-install id (UUID stored natively; not an advertising/hardware ID)
`EventChannel('edu.thapar.stepup/engine_events')`: map `{tracking, raw, verified, pending, rejected, suspicious, liveLabel}` every 2 s while a listener is attached.
Foreground service of type `health`, boot receiver restores tracking if the user had it on. Raw IMU recording is **off** in release (debug build flag only, never in this app's UI).

---

## Backend implementation notes and contract additions (added by the backend engineer, `functions/`)

Everything above is implemented as written; the items below are **additions or clarifications** (nothing was renamed).

### `syncStepBuckets` — late step-counter events on already-settled buckets (contract addition)
Each bucket may additionally carry `lateRawAdded` (int ≥ 0) and `lateCreditedAdded` (int ≥ 0; both default 0). They are **cumulative** late parts and `rawDelta`/`credited` already include them. Both are stored on the `stepBuckets` doc (default 0).
* **New doc id** → stored as usual (late fields stored).
* **Existing deterministic doc**, incoming `lateRawAdded` **greater** than the stored one → **UPDATE**: the same validation is re-run (≤ 35 steps per bucket, rolling 30 min, daily reward cap, age 72 h, future tolerance), `serverCredited` is recomputed from the supplied hops with the downgrade-only rule (`≤ clientCredited ≤ new rawDelta`), the doc is updated (flags gain `LATE_UPDATED`, `lateUpdatedAt` set), the user's `dailyStepSummaries` doc is recomputed from the stored buckets, and the bucket is reported as `accepted` (not `duplicates`) when it ends VERIFIED/PARTIAL (or in `rejected[]` with its reason when the update leaves it REJECTED/UNWITNESSED) and counted in `updated`.
* **Equal or lower** `lateRawAdded` → plain duplicate, no-op (`duplicates`), whatever the other numbers say.
* A re-send can **never lower** a stored `serverCredited`. An update is **rejected and the old doc stays unchanged** (listed in `rejected[]`) when: `CADENCE_EXCEEDED` (new rawDelta > 35), `TOO_OLD`/`FUTURE_BUCKET`/`BAD_ALIGNMENT`, `LATE_RAW_DECREASED` (new rawDelta < stored), or `LATE_UPDATE_LOWERS_CREDIT` (recomputed/claimed/capped credit would be below the stored credit).
* Result: `{accepted, duplicates, rejected:[{startMs,reason}], downgraded, updated, today:{verifiedSteps,rawSteps,rejectedSteps,unwitnessedSteps}}`. Every bucket in the request is accounted for in exactly one of: `accepted`, `duplicates`, `rejected` (permanently rejected / not stored: `TOO_OLD`, `FUTURE_BUCKET`, `BAD_ALIGNMENT`, `MALFORMED`, `CADENCE_EXCEEDED`, `LATE_*`; or stored with state REJECTED/UNWITNESSED, with the reason). The client should ack (`ackBuckets`) every `startMs` that is in `accepted`, `duplicates` or `rejected`; it only needs to keep re-offering buckets when the call itself failed (`unavailable`, `internal`, ...).
* `rawDelta` outside 1..35 → `CADENCE_EXCEEDED` (stored as REJECTED if 1 ≤ raw ≤ 100000 and > 35; not stored if < 1). Payload > 200 buckets → `invalid-argument/TOO_MANY_BUCKETS`. Unregistered device → `failed-precondition/DEVICE_NOT_REGISTERED` (call `registerDevice` first).

### `stepBuckets` extra fields
`clientCredited` = min(claimed, rawDelta) (keeps `serverCredited ≤ clientCredited ≤ rawDelta`); `claimedCredited` (what the client sent), `recomputedCredited` (server recomputation before the downgrade-only merge), `lateRawAdded`, `lateCreditedAdded`, `lateUpdatedAt`, `startAt` (Timestamp). Daily-cap excess is stored with `serverCredited` reduced (0 for fully excess buckets), `reason:'DAILY_CAP'`, `rewardEligible:false`; `flags` may contain `DOWNGRADED, CREDIT_GT_RAW, CADENCE_EXCEEDED, DAILY_CAP, ROLLING_30MIN_CAP, LATE_UPDATED`. `riskEvents` ids are `{uid}_{kind}_{dayKey}` (one aggregate doc per kind/day with `detail.count`); kinds generated: `HARD_LIMIT, DAILY_CAP, DOWNGRADE, MANY_REJECTIONS` (`ROBOTIC` and `DEVICE_MISMATCH` are reserved, not generated).

### Callable results / parameters (additions)
* All Timestamps returned by callables are **epoch milliseconds**.
* `createProfile` → `{ok, created, profile}` (`created:false` when the profile already existed; the existing profile is returned untouched). `sendBuddyRequest` → `{ok, requestId}` (`requestId = {fromUid}_{toUid}`). `createStepBet` accepts optional `requestId` (8–40 chars `[A-Za-z0-9-]`, makes retries idempotent) → `{betId, duplicate}`. `markNotificationsRead` → `{ok, updated}`. `joinChallenge`/`leaveChallenge` → `{ok, participant}`.
* `getLeaderboard` → `{entries, me:{rank|null, value}, metricLabel, periodKey, updatedAt|null}`. Student rows (CAMPUS / MY_HOSTEL / BUDDIES): `{rank, uid, name, photoUrl, hostelId|null, value}`. Hostel rows (HOSTELS): `{rank, hostelId, name, value, participants, total, average}` where `value` is the ranking metric (`average` by default, `total` when `hostelMetric:'TOTAL'`); all active hostels are listed (zero-participant ones too) and `me` is the caller's hostel rank/value. `rank` is null when the caller has no verified steps in the period or has `showOnLeaderboards:false`.
* Admin params: `adminUpsertHostel{hostelId,displayName,legacyName?,block?,category,active?,sortOrder?}`, `adminSetHostelActive{hostelId,active}`, `adminCreateChallenge{type(INDIVIDUAL|INTER_HOSTEL|CAMPUS),title,description?,metric,target,dailyTarget(for day metrics),windowMode,startAt,endAt (FIXED, epoch ms of IST midnights) | durationDays (ROLLING, INDIVIDUAL only),hostelIds?,hostelAggregation?,maxParticipants?,rewardPoints?}→{challengeId}`, `adminCancelChallenge{challengeId}`, `adminListStudents{query?,limit?,cursor?}→{students,nextCursor}`, `adminSetUserRole{uid,role:'student'|'admin'}` (cannot demote self; sets the custom claim and mirrors `users.role`; the user must refresh the ID token), `adminSuspendUser{uid,suspend,reason?}`, `adminListReports{status?,limit?}`, `adminResolveReport{reportId,status:DISMISSED|ACTIONED}`, `adminListRiskEvents{status?,limit?}`, `adminResolveRiskEvent{id,status:REVIEWED|CLEARED}`, `adminSetSettings{settings:{<numeric keys of adminSettings/global>}}` (bounded; `timezone` is read-only; `maxStepsPerBucket ≤ 35`, `maxStepsPer30Min ≤ 6300`), `adminUpsertBadge{badgeId,title,description,icon,rule,points}`, `adminStats{}`, `adminSeedDefaults{}`. Audit entries are written to `adminAudit` (admin uid, action, primitive params) and role changes also to `adminSettings/admins.changes[]`.
* The Auth blocking function is exported as `beforeUserCreated` (Identity Platform required in production; the callable/rules checks stay authoritative).

### Collections: extra fields and semantics
* `virtualPointsLedger`: besides `delta` (= change of `pointsBalance`) there is `reservedDelta` (= change of `pointsReserved`). RESERVE `delta -s / reservedDelta +s`; RELEASE `+s / -s`; BET_WIN `+2s / -s` (winner receives both stakes); BET_LOSS `0 / -s`; REWARD/ADJUSTMENT `±n / 0`. Ledger ids: `BET_{betId}_{uid}_{RESERVE|RELEASE|BET_WIN|BET_LOSS}`, `CHALLENGE_{challengeId}_{uid}_REWARD`, `DAILY_GOAL_{dayKey}_{uid}_REWARD`, `STREAK_{runStartDayKey}_{uid}_REWARD`, `BADGE_{badgeId}_{uid}_REWARD`.
* `challenges`: BUDDY docs carry `participantUids:[a,b]` (sorted; used by the rules) and `rewardsPending`/`rewardsPaidAt` (set at finalize, cleared when rewards are paid; makes payment resumable). After acceptance a BUDDY challenge is `windowMode:'FIXED'` with `startAt/endAt` set (status `UPCOMING` until the first midnight, then `ACTIVE` via `finalizeChallenges`). `challengeResults` of BUDDY challenges also carry `participantUids`. `challengeParticipants` get `endedReason:'WINDOW_ENDED'`/`leftAt` when a ROLLING window passes without completion (status → `LEFT`, re-join allowed). INDIVIDUAL completion reward uses ledger id `CHALLENGE_{challengeId}_{uid}_REWARD`, i.e. **once per user per challenge ever**, including re-joins.
* Winner rules: BUDDY = highest progress that reached `target` (ties: first to reach it); CAMPUS = highest progress > 0 (badges `CHALLENGE_CHAMPION` + `CAMPUS_FITNESS_STAR`); INTER_HOSTEL = best hostel by `hostelAggregation` (every participant of the winning hostel with progress > 0 gets `rewardPoints` and `HOSTEL_CHAMPION`); INDIVIDUAL has no winner. Finalize happens at `endAt + settlementGraceHours`.
* `leaderboards/*/entries/{uid}` also carry `showHostel`, `countsForHostel` (false for suspended/deleted users: excluded from hostel aggregates). Students with `showOnLeaderboards:false` get an anonymised entry (`displayName:'Student'`, `photoUrl:null`) but still count in hostel aggregates. `hostelId` is stored on entries for aggregation, so a client reading entries directly could see it even if `showHostel` is false; the `getLeaderboard` callable honours `showHostel`.
* `adminSettings/global` extra keys: `rewardDeviceTakeoverDays` (14: a reward device unseen this long may be replaced by a newly registered device), `buddyRerequestCooldownHours` (24).
* `registerDevice`: the first device becomes the reward device; later ones are display-only; takeover rule above. `requestAccountDeletion` also writes `reports/deletion_{uid}` (reason `ACCOUNT_DELETION`) and hides the public profile.
* Storage rules: `profilePhotos/{uid}/{file}`, owner write, content type `image/(jpeg|png|webp|gif|heic|heif)` (SVG is deliberately excluded), size ≤ 2 MB, eligible read.
* Firestore rules deviate from nothing; `adminSettings/challengeTemplates` and `adminSettings/admins` are admin-read only.

### Account status handling (callables)
`requireEligibleUser` refuses non-ACTIVE accounts with `permission-denied` and `details.reason`: `ACCOUNT_DELETION_REQUESTED` (status DELETION_REQUESTED), `ACCOUNT_SUSPENDED` (SUSPENDED). Read-only callables `getLeaderboard`, `getChallengeLeaderboard`, `markNotificationsRead` and a repeated `requestAccountDeletion` (returns `{ok:true}`) still work for DELETION_REQUESTED users; Firestore reads of their own data (rules do not check status) and sign-out are unaffected. `getChallengeLeaderboard` rows: students `{rank, uid, name, photoUrl, hostelId, value, progressPct}`, hostels `{rank, hostelId, name, value, participants, total, progressPct}`, plus `me:{rank|null,value}` and `metricLabel`. `searchBuddies` → `{profiles:[{uid, displayName, photoUrl, hostelId|null, fitnessLevel, sportsInterests, preferredActivity, preferredTime, goals, availability, buddyType, bio, weeklyVerifiedSteps|null, discoverable, showOnLeaderboards, relation}], nextCursor|null}`.
