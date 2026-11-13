# DEMO_GUIDE.md — showing StepUp live to a professor

Goal: log in on a real phone, track REAL steps live, then tour the other features. Everything runs on your PC (Firebase emulators) and your
phone talks to it over the PC's own Wi-Fi hotspot. Cost: ₹0. Nothing is hosted on the internet.

**Be upfront (say this early):** the backend is a local test server on this PC, not a cloud service. Your own steps are real. The "(sample)" students,
their 3 days of step history, the challenges and the bet are **demo data** created by `scripts/seed-demo.js` (hand-built step records sent through the real
server rules). Step accuracy has only been measured on one phone with one person (`GENUINE_STEP_ENGINE.md`).

---------------------------------------------------------------------------------------------------------------------------------

## A. One-time preparation (do this days before; rehearse once)

1. **Firewall (admin PowerShell, once):** lets the phone reach the emulators.
   ```powershell
   New-NetFirewallRule -DisplayName "StepUp demo emulators" -Direction Inbound -Protocol TCP -LocalPort 9099,8080,5001,9199 -Action Allow -Profile Private,Public
   ```
2. **Hotspot:** Windows Settings → Network & internet → **Mobile hotspot → On**. The PC's address on it is normally `192.168.137.1`
   (the demo APK is built for that). Join your phone to this hotspot. Do NOT use college Wi-Fi: it usually blocks device-to-device traffic and the
   emulators have no security of their own.
   *If the hotspot will not start:* connect the PC to the PHONE's hotspot instead, find the PC's address (`ipconfig`), rebuild with
   `.\scripts\demo-build-apk.ps1 -HostIp <that address>` and use that address in every `-HostIp` below.
3. **Install the app on the phone:** `StepUp_DEMO_192.168.137.1-debug.apk` (Desktop\steps). Either `adb install -r <apk>` over USB, or copy the file to
   the phone and open it (allow "install unknown apps" for your file manager). Tap Install / Install anyway on any Play Protect warning.
4. **Phone settings you choose yourself (not done by any script):** screen timeout long, battery "unrestricted"/"no restrictions" for StepUp
   (otherwise realme may stop the step service), Wi-Fi → the PC hotspot.
5. Open the app once while the emulators are running and allow **Physical activity** and **Notifications** when asked.

## B. Demo-day morning (3 windows)

```powershell
# window 1 - leave open all day
cd "<path-to>\StepUp_Complete_Flutter_App"
.\scripts\demo-start-emulators.ps1

# window 2 - fresh data for today (wipes the emulators, seeds hostels + demo accounts)
$env:PRESENTER_EMAIL = 'presenter@thapar.edu'; $env:PRESENTER_PASSWORD = '<your password>'
.\scripts\demo-reset-and-seed.ps1

# check everything (read-only)
.\scripts\demo-preflight.ps1 -HostIp 192.168.137.1
```
Re-run window 2 on the day of the demo: the sample students' "today" is created at that moment. Re-running wipes everything, including your steps.
The data lives in memory: if you close window 1 or the PC restarts, run window 1 and 2 again.
Never run `npm run test:*` while the demo emulators are up (port clash).

## C. Accounts (local emulator only)

| Account | Password | Use it for |
|---|---|---|
| `presenter@thapar.edu` (you) | the one you chose | **Part 1: real steps.** Onboarded, no step history. 1 incoming buddy request (Riya), 1 buddy (Aarav), 0 points. |
| `demo.student@thapar.edu` | `Demo@12345` | **Part 2: pre-loaded.** 3 days of SAMPLE steps, ~50 points, an active bet with Aarav. Log in as this one to show bets. |
| `demo.admin@thapar.edu` | `Demo@12345` | **Admin panel** (Profile → Settings → Admin). |
| `aarav/riya/kabir/meera.sample@thapar.edu` | `Demo@12345` | Sample classmates (labelled "(sample)"). |
| anyone new `x@thapar.edu` | any | Register live. Then run `.\scripts\demo-verify-email.ps1 -Email x@thapar.edu` (no real e-mail is sent). |

## D. Run of show (about 12–15 minutes)

**Order matters for the live walk: start tracking early, because verified steps appear about 2 minutes after you walk.**

1. *(1 min)* Idea: only **verified genuine steps** count for anything (leaderboards, challenges, bets, rewards). Show `GENUINE_STEP_ENGINE.md` or the architecture diagram.
2. *(1 min)* On the phone, log in as **you**. (Optionally, first show registration refusing `someone@gmail.com`: "Use your @thapar.edu email address".)
3. *(1 min)* Home: progress ring, streak, weekly bars, quick actions, campus activity, team credits (Project Lead: Disha).
4. *(1 min)* **Turn on step tracking** → tap Allow on the prompts → the "StepUp is counting verified steps" notification appears (pull down the shade).
5. *(1 min)* **Walk ~50 steps** at a normal pace, phone in your hand, and say the count out loud. Return and continue the tour while it settles.
6. *(2 min)* Buddies: the incoming request from Riya (accept it live), your existing buddy Aarav, filters. Challenges: Campus Step Week + the individual challenge (join one).
7. *(1 min)* Leaderboard: podium, "my rank" row, hostel average-per-participant. (Samples show higher numbers: they are demo data.)
8. *(1 min)* Back on Home: your **verified** steps should now show (raw vs verified vs pending). Explain pending/rejected.
9. *(optional 1 min)* **Fake test:** shake the phone hard for 30 s, wait ~2 min, show that these steps are NOT credited. (The prototype credited 0 of 562 shaken steps; rehearse this first.)
10. *(2 min)* Switch to `demo.student` → Create Step Bet screen (virtual points only), the active bet, the points ledger. As yourself you have 0 points: trying a bet shows the "not enough points" rule.
11. *(1 min)* Switch to `demo.admin` → admin panel: students, hostels (admin-configurable), settings, reports/risk events.
12. *(1 min)* Security & tests: 907 app tests, 148+59+231 backend tests, domain rules. Show `IMPLEMENTATION_PROGRESS.md`.
13. Close with the one-slide honest status (section F).

If the professor wants to try it: have them register a new `@thapar.edu` address, run the verify helper, and let them walk.

## D2. If the phone shows "network problem" (seen in practice on 2026-11-14)

Cause found: the phone and PC were both on the **college Wi-Fi** (`172.16.x.x`); the phone could not reach the PC at all (ping/TCP: "No route to host" — the network
isolates devices from each other), and the demo APK expects the PC hotspot address `192.168.137.1`, which did not exist because the hotspot was off.
Three ways out, easiest first:
1. **USB fallback (works with no hotspot, no firewall change, no admin rights):** install the USB build and forward the ports, keep the cable plugged in while logging in and touring:
   ```powershell
   adb install -r StepUp_USB_127.0.0.1-debug.apk        # built with: .\scripts\demo-build-apk.ps1 -HostIp 127.0.0.1
   adb reverse tcp:9099 tcp:9099; adb reverse tcp:8080 tcp:8080; adb reverse tcp:5001 tcp:5001; adb reverse tcp:9199 tcp:9199
   ```
   Steps you walk while unplugged are kept on the phone and sync after you plug in and re-run the four `adb reverse` lines.
2. **PC hotspot** (section A): Mobile hotspot ON, phone joined, firewall rule added. Preflight must show READY.
3. **Phone hotspot:** PC joins the phone's hotspot, then `.\scripts\demo-build-apk.ps1 -HostIp <PC address on that hotspot>` and install that APK.

## E. Troubleshooting

| Symptom | Fix |
|---|---|
| App shows "Backend not configured" | You installed the wrong APK. Use `StepUp_DEMO_192.168.137.1-debug.apk`. |
| Login hangs / "network error" | Phone not on the PC hotspot, hotspot IP differs from the one built in, firewall rule missing, or emulators not running. Run `demo-preflight.ps1`; in the phone browser open `http://192.168.137.1:9099` (should answer). |
| "Activity permission needed" | Tap the switch again and Allow. Settings → Apps → StepUp → Permissions → Physical activity. |
| No notification / tracking stops | Battery optimisation: set StepUp to unrestricted; keep the app open and the screen awake during the walk. |
| Steps do not appear | Wait ~2 minutes (settlement), tap **Sync now** on Home, check that the PC hotspot is still on. If you walked while disconnected, they sync when the phone reaches the PC again. |
| Verified < what you counted | Expected sometimes: steps while handling the phone are deliberately not credited; the credit is capped at 1.15 × the gait the sensors see. Say so honestly. |
| Sample numbers look wrong the next day | Re-run window 2 on the day (they were created relative to the time of seeding). |

## F. The honest status slide (read it out)

* **Done and tested:** all features implemented; 907 app tests; 148 backend unit + 59 rules + 231 backend scenario tests on a local Firebase emulator; 5 end-to-end tests on a real phone.
* **Demo conditions:** local test server; sample students and challenges are demo data; step accuracy measured on one phone, one person.
* **Not done:** a real cloud backend (needs a paid plan or a rewrite for a free host), a real-world accuracy study, push notifications, Google sign-in, release build.
* **Next, if approved:** pick a hosting route (see `HANDOFF_FOR_NEXT_AGENT.md` §9 and the free options: Firebase free tier + free host, or Supabase), run a pilot with a few dozen students, validate accuracy on more phones.

## G. Files

`scripts/demo-start-emulators.ps1` · `demo-reset-and-seed.ps1` · `seed-demo.js` · `demo-preflight.ps1` · `demo-verify-email.ps1` · `demo-build-apk.ps1` · `firebase.demo.json`.
The demo seed refuses to run against anything but the local emulators. No password is stored in the repo except the demo-only `Demo@12345`.
