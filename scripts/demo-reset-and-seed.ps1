<#
 Wipes the RUNNING local emulators (Auth accounts + Firestore documents of project demo-stepup), re-seeds the base data
 (18 hostels, challenge templates, badges, settings) and the demo accounts/data (scripts/seed-demo.js). Run it on the day of the demo.
   $env:PRESENTER_EMAIL = 'you@thapar.edu'; $env:PRESENTER_PASSWORD = '...'; .\scripts\demo-reset-and-seed.ps1
 It never touches a real Firebase project (the seed script refuses non-local emulator addresses).
#>
param([string]$PresenterName = 'Disha')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $env:PRESENTER_EMAIL -or -not $env:PRESENTER_PASSWORD) { throw 'set $env:PRESENTER_EMAIL and $env:PRESENTER_PASSWORD first' }
$p = 'demo-stepup'
Invoke-RestMethod -Method Delete -Uri "http://127.0.0.1:9099/emulator/v1/projects/$p/accounts" | Out-Null
Invoke-RestMethod -Method Delete -Uri "http://127.0.0.1:8080/emulator/v1/projects/$p/databases/(default)/documents" | Out-Null
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5001'
$env:PRESENTER_NAME = $PresenterName
Set-Location "$root\functions"
node ..\scripts\seed.js
node ..\scripts\seed-demo.js
if ($LASTEXITCODE -ne 0) { throw 'demo seed failed' }
