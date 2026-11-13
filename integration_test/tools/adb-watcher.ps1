<#
 PC-side helper for the on-device integration tests (--dart-define=ADB_WATCHER=true).

 The test runs inside the app on the phone and cannot call adb. At checkpoints it writes
 testControl/phase = {name, seq} into the Firestore emulator. This script polls that
 document, runs the matching read-only adb queries against the phone and writes
 testControl/adb_<name> = {service, notification, ...} which the test then asserts.

 Usage (Windows PowerShell):  .\adb-watcher.ps1 -Serial dbc4b60 -OutDir C:\temp\adb-evidence -MaxMinutes 30
 While a run is active it keeps this app in front (Flutter stops rendering, and the test stalls, when another app is on
 top or the screen is off): it only launches this app's activity and sends KEYCODE_WAKEUP; pass -NoKeepForeground to disable.
 Reads dumpsys activity services (this package only) and the notification records posted by this package only
 (other apps' notifications are never written to disk); grants this app's two runtime permissions on request; runs scripts/grant-admin.js on request.
#>
param(
  [string]$Serial = 'dbc4b60',
  [string]$OutDir = "$env:TEMP\stepup-adb-evidence",
  [int]$MaxMinutes = 30,
  [switch]$NoKeepForeground
)
$ErrorActionPreference = 'Continue'   # a failing adb call must never kill the watcher
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$pkg = 'edu.thapar.stepup'
$base = 'http://127.0.0.1:8080/v1/projects/demo-stepup/databases/(default)/documents/testControl'
$h = @{ Authorization = 'Bearer owner' }
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Set-Control($id, $fields) {
  $f = @{}
  foreach ($k in $fields.Keys) { $f[$k] = @{ stringValue = [string]$fields[$k] } }
  $body = @{ fields = $f } | ConvertTo-Json -Depth 6
  Invoke-RestMethod -Method Patch -Uri "$base/$id" -Headers $h -Body $body -ContentType 'application/json' | Out-Null
}

$lastSeq = ''
$tick = 0
$end = (Get-Date).AddMinutes($MaxMinutes)
Write-Host "watching until $end"
while ((Get-Date) -lt $end) {
  $tick++
  if ($tick % 6 -eq 0) {
    # A USB re-connect drops all `adb reverse` rules; put back the four emulator ports (port forwards only).
    try {
      $rev = (& $adb -s $Serial reverse --list 2>$null) -join ' '
      foreach ($port in 9099, 8080, 5001, 9199) {
        if ($rev -notmatch "tcp:$port ") { & $adb -s $Serial reverse "tcp:$port" "tcp:$port" 2>$null | Out-Null; Write-Host "re-added adb reverse tcp:$port" }
      }
    } catch { }
  }
  if (-not $NoKeepForeground -and ($tick % 4 -eq 0)) {
    # Flutter stops producing frames when the app is not the visible activity (another app in front, screen off), which
    # stalls `tester.pump` forever. While the app process exists (i.e. a test run is active) bring OUR app back to the
    # front and wake the screen. No settings are changed; only this app's activity is launched.
    try {
      $appPid = (& $adb -s $Serial shell pidof $pkg 2>$null) -join ''
      if ($appPid.Trim()) {
        $power = (& $adb -s $Serial shell dumpsys power 2>$null) -join "`n"
        if ($power -match 'mWakefulness=(Asleep|Dozing)') { & $adb -s $Serial shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null }
        $top = (& $adb -s $Serial shell dumpsys activity activities 2>$null | Select-String -Pattern 'topResumedActivity|mResumedActivity' | Select-Object -First 1) -join ''
        if ($top -and ($top -notmatch [regex]::Escape($pkg))) {
          # NEW_TASK | REORDER_TO_FRONT: moves the EXISTING activity to the front (a plain `am start` made a second MainActivity
          # instance because the app uses taskAffinity="", which re-ran the whole test inside the new instance).
          & $adb -s $Serial shell am start -n "$pkg/.MainActivity" -f 0x10020000 2>$null | Out-Null
          Write-Host 'app was not in front: brought edu.thapar.stepup back to the foreground'
        }
      }
    } catch { }
  }
  try {
    $d = Invoke-RestMethod -Uri "$base/phase" -Headers $h
    $name = $d.fields.name.stringValue
    $seq = $d.fields.seq.stringValue
    if ($seq -ne $lastSeq) {
      $lastSeq = $seq
      Write-Host "checkpoint $name ($seq)"
      if ($name -eq 'grant_permissions') {
        # The only phone setting this run changes: this app's two runtime permissions (pm grant, package edu.thapar.stepup).
        # Some phones (realme/ColorOS) reject `pm grant` unless "USB debugging (Security settings)" is on; then a HUMAN must tap
        # Allow on the app's own permission dialogs. Verify instead of assuming, and say so.
        $null = & $adb -s $Serial shell pm grant $pkg android.permission.ACTIVITY_RECOGNITION 2>&1
        $null = & $adb -s $Serial shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>&1
        $state = (& $adb -s $Serial shell "dumpsys package $pkg" 2>$null | Select-String 'ACTIVITY_RECOGNITION: granted=(true|false)' | Select-Object -First 1)
        $ok = ($state -and $state.ToString() -match 'granted=true')
        $res = if ($ok) { 'granted' } else { 'NOT-GRANTED (adb pm grant refused; tap Allow on the permission dialogs on the phone)' }
        Set-Control "adb_$name" @{ result = $res; seq = $seq }
        Write-Host "  $res"
        continue
      }
      if ($name -eq 'grant_admin') {
        # Not an adb query: runs the repo's admin-grant script (the legitimate admin path) for the e-mail in `arg`.
        $email = $d.fields.arg.stringValue
        $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'; $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
        $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Push-Location "$root\functions"
        $out = (node ..\scripts\grant-admin.js $email 2>&1) -join ' '
        Pop-Location
        Write-Host "  $out"
        Set-Control "adb_$name" @{ result = $out; seq = $seq }
        continue
      }
      $svc = (& $adb -s $Serial shell dumpsys activity services $pkg) -join "`n"
      # PRIVACY: the notification dump contains every app's notifications. Keep ONLY the records posted by our package.
      # Android 12+ defers showing a foreground-service notification by up to ~10 s, so retry for up to 20 s.
      $notif = ''
      for ($try = 0; $try -lt 20; $try++) {
        $lines = @(& $adb -s $Serial shell dumpsys notification --noredact)
        $mine = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $lines.Count; $i++) {
          if ($lines[$i] -match "NotificationRecord\(.*pkg=$([regex]::Escape($pkg)) ") {
            $end2 = [Math]::Min($lines.Count - 1, $i + 45)
            for ($j = $i; $j -le $end2; $j++) { if ($j -gt $i -and $lines[$j] -match 'NotificationRecord\(') { break }; $mine.Add($lines[$j]) }
          }
        }
        $lines = $null
        $notif = $mine -join "`n"
        if ($notif -match 'StepUp is counting verified steps') { break }
        Start-Sleep -Seconds 1
      }
      Set-Content "$OutDir\$name.services.txt" $svc
      Set-Content "$OutDir\$name.notification-own-package.txt" $notif
      $svcOk = $svc -match 'SensorWitnessService'
      $isFg = $svc -match 'isForeground=true'
      $notifOk = $notif -match 'StepUp is counting verified steps'
      Set-Control "adb_$name" @{
        service       = $svcOk.ToString().ToLower()
        foreground    = $isFg.ToString().ToLower()
        notification  = $notifOk.ToString().ToLower()
        seq           = $seq
      }
      Write-Host "  service=$svcOk foreground=$isFg notification=$notifOk"
    }
  } catch {
    # phase doc not there yet (404) or emulator hiccup
  }
  Start-Sleep -Milliseconds 700
}
