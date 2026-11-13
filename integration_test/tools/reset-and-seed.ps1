<#
 Resets the RUNNING Firebase emulators (Auth accounts + Firestore documents of project demo-stepup),
 re-seeds hostels/templates/badges/settings and clears the app's data on the phone, then pre-grants
 the two runtime permissions to the app (the only phone change the E2E run makes).
 Touches ONLY package edu.thapar.stepup on the phone.
#>
param([string]$Serial = 'dbc4b60', [switch]$SkipPhone)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$p = 'demo-stepup'
Invoke-RestMethod -Method Delete -Uri "http://127.0.0.1:9099/emulator/v1/projects/$p/accounts" | Out-Null
Invoke-RestMethod -Method Delete -Uri "http://127.0.0.1:8080/emulator/v1/projects/$p/databases/(default)/documents" | Out-Null
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
Push-Location "$root\functions"
node ..\scripts\seed.js
Pop-Location
if (-not $SkipPhone) {
  $ErrorActionPreference = 'Continue'   # `pm clear` errors when the app is not installed yet
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  & $adb -s $Serial shell pm clear edu.thapar.stepup
  & $adb -s $Serial reverse tcp:9099 tcp:9099
  & $adb -s $Serial reverse tcp:8080 tcp:8080
  & $adb -s $Serial reverse tcp:5001 tcp:5001
  & $adb -s $Serial reverse tcp:9199 tcp:9199
}
