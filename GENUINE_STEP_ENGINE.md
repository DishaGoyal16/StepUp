# Genuine-step engine — what it is and what has actually been measured

Source: `../StepUp_Genuine_Step_Detection_v2` (copied unchanged into `android/stepup_core`). Spec: `../DOCS/StepUp_AntiFraud_Architecture_v2.md`.

## Pipeline
1. `TYPE_STEP_COUNTER` deltas bucketed by **sensor timestamp** into 10 s buckets; the first event after (re)registration/reboot is baseline only.
2. Accelerometer (+gyro) → 25 Hz grid → 4 s windows / 2 s hops → features → explainable classifier (WALK, RUN, SHAKE, VEHICLE, STILL, UNKNOWN). Hard rules: H1 still, H2 vehicle (Activity Recognition, downgrade-only), **H3 extreme-shake veto** (dynRms ≥ 8 m/s² and churn ≥ 150 deg/s).
3. Bucket verifier: UNWITNESSED if IMU hop coverage < 0.8; REJECTED if < 50 % WALK/RUN hops; else `credited = min(raw, floor(1.15 × Σ IMU gait steps))`.
4. Ledgers: raw/display vs verified; states PENDING (not yet settled), VERIFIED, PARTIAL, REJECTED, UNWITNESSED, GAP. GAP steps (service not listening) are display-only.

## Measured on one phone (realme RMX3990, one person) — NOT a validated accuracy
Replay of all recordings with the final settings:
* Hand-held walks with ground truth (50 steps each): credited 50/52 and 54/59 counter steps (retention 1.00; one run +8 % over the manual count).
* Pocket / unlabeled walks: 45 of 65, 43 of 50, 16 of 62 counter steps credited (steps taken while handling the phone are deliberately not credited). Pooled over 5 walking recordings: 237 of 350 (68 %).
* Fast phone shaking (~7 runs): 0 of 562 counter steps credited. Sitting still: counter counted nothing.
**Not tested on hardware:** slow rhythmic shake, leg bounce, pendulum, vehicle, cycling, bag, stairs, running, other phones/people.
Treat reward use as provisional until those are tested.
