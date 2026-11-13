<#
 The demo emulators send no real e-mail. After someone registers in the app, run this to "click the verification link" for them:
   .\scripts\demo-verify-email.ps1 -Email prof.name@thapar.edu
 Works only against the local emulator on this PC.
#>
param([Parameter(Mandatory)][string]$Email)
$h = @{ Authorization = 'Bearer owner' }
$e = $Email.Trim().ToLowerInvariant()
$codes = (Invoke-RestMethod "http://127.0.0.1:9099/emulator/v1/projects/demo-stepup/oobCodes" -Headers $h).oobCodes |
  Where-Object { $_.email -eq $e -and $_.requestType -eq 'VERIFY_EMAIL' }
if (-not $codes) { Write-Host "No verification request for $e yet - register in the app first (and wait for 'Check your inbox')." -ForegroundColor Yellow; exit 1 }
$link = (@($codes) | Select-Object -Last 1).oobLink
try { Invoke-WebRequest -Uri $link -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop | Out-Null } catch { }
$q = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-stepup/accounts:query' -Headers $h -Body '{}' -ContentType 'application/json'
$u = $q.userInfo | Where-Object { $_.email -eq $e }
if ($u.emailVerified) { Write-Host "$e is verified. In the app tap 'I verified' (it also notices by itself)." -ForegroundColor Green } else { Write-Host "Could not verify $e" -ForegroundColor Red; exit 1 }
