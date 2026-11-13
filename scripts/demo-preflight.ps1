<#
 Read-only pre-flight check before the demo. Changes nothing.
   .\scripts\demo-preflight.ps1 [-HostIp 192.168.137.1]
#>
param([string]$HostIp = '192.168.137.1')
$ok = $true
function Check($name, $pass, $hint) { if ($pass) { Write-Host "[ OK ] $name" -ForegroundColor Green } else { Write-Host "[FAIL] $name  -> $hint" -ForegroundColor Red; $script:ok = $false } }

$listen = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 9099, 8080, 5001, 9199 })
foreach ($port in 9099, 8080, 5001, 9199) {
  $l = $listen | Where-Object { $_.LocalPort -eq $port }
  Check "emulator port $port is listening on all interfaces" ($l | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' }) 'start .\scripts\demo-start-emulators.ps1 (uses firebase.demo.json)'
}
$ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $HostIp }
Check "this PC has address $HostIp (Windows Mobile hotspot default)" ($null -ne $ip) 'turn on Settings > Network > Mobile hotspot, or pass -HostIp <your PC address on the private network>'
$rules = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | Where-Object { $_.Protocol -eq 'TCP' -and ($_.LocalPort -match '9099|8080|5001|9199') })
Check 'Windows Firewall has an inbound allow rule that could cover the emulator ports (loose check - the real test is the phone opening the app)' ($rules.Count -gt 0) 'run once in an ADMIN PowerShell: New-NetFirewallRule -DisplayName "StepUp demo emulators" -Direction Inbound -Protocol TCP -LocalPort 9099,8080,5001,9199 -Action Allow -Profile Private,Public'
try { $r = Invoke-RestMethod -Uri "http://${HostIp}:9099/emulator/v1/projects/demo-stepup/config" -TimeoutSec 5; Check "Auth emulator answers on http://${HostIp}:9099" $true '' } catch { Check "Auth emulator answers on http://${HostIp}:9099" $false 'hotspot off, firewall, or emulators not running' }
try {
  $h = @{ Authorization = 'Bearer owner' }
  $hostels = (Invoke-RestMethod -Uri 'http://127.0.0.1:8080/v1/projects/demo-stepup/databases/(default)/documents/hostels?pageSize=50' -Headers $h).documents.Count
  Check "base data seeded ($hostels hostels)" ($hostels -eq 18) 'run .\scripts\demo-reset-and-seed.ps1'
  $users = (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-stepup/accounts:query' -Headers $h -Body '{}' -ContentType 'application/json').recordsCount
  Check "demo accounts exist ($users)" ([int]$users -ge 7) 'run .\scripts\demo-reset-and-seed.ps1'
} catch { Check 'emulators reachable on this PC' $false 'start the emulators first' }
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$j = Start-Job { param($a) & $a devices 2>&1 } -ArgumentList $adb
if (Wait-Job $j -Timeout 10) { $dev = (Receive-Job $j) -join ' ' } else { $dev = 'adb hung'; Stop-Job $j }
Remove-Job $j -Force
Write-Host "adb (only needed to install the app): $dev"
Write-Host ''
if ($ok) { Write-Host 'READY. On the phone: join the PC hotspot, open StepUp, log in.' -ForegroundColor Green } else { Write-Host 'Fix the FAIL lines above, then run this again.' -ForegroundColor Yellow }
