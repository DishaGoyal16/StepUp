# Save the running LOCAL demo before closing the server or restarting Windows.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
& "$root\functions\node_modules\.bin\firebase.cmd" emulators:export (Join-Path $root '.demo-data') --project demo-stepup --config firebase.demo.json --force
if ($LASTEXITCODE -ne 0) { throw 'Could not save demo data; leave the server running and check its log.' }
Write-Host 'Saved. demo-start-emulators.ps1 will import this data next time.'
