<#
 Runs one integration test file on the phone against the running emulators.
   .\integration_test\tools\run-e2e.ps1 -File e2e_full_test.dart -Reset -Watcher
 -Reset    resets + re-seeds the emulators and re-creates the adb reverse rules first.
 -Watcher  passes --dart-define=ADB_WATCHER=true: the test then needs tools\adb-watcher.ps1 running in another window
           (permission grant, foreground-service / notification check, admin grant).
 Requires: emulators running (npm run emulators in functions/).
#>
param([Parameter(Mandatory)][string]$File, [switch]$Reset, [string]$Serial = 'dbc4b60', [switch]$Watcher)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$root\..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1" | Out-Null
$env:Path = "C:\src\flutter\flutter\bin;" + $env:Path
Set-Location $root
if ($Reset) { & "$PSScriptRoot\reset-and-seed.ps1" -Serial $Serial }
$w = if ($Watcher) { '--dart-define=ADB_WATCHER=true' } else { '--dart-define=ADB_WATCHER=false' }
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = "$root\build\app\outputs\flutter-apk\app-debug.apk"
for ($attempt = 1; $attempt -le 3; $attempt++) {
  flutter test "integration_test\$File" -d $Serial --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1 $w 2>&1 | Tee-Object -Variable out
  # The realme package verifier intermittently rejects `flutter test`'s install (INSTALL_FAILED_VERIFICATION_FAILURE); a plain
  # `adb install -r` of the same APK succeeds, after which the retry works.
  if (($out -join "`n") -match 'INSTALL_FAILED_VERIFICATION_FAILURE') {
    Write-Host "install rejected by the package verifier; installing the APK with adb and retrying ($attempt)"
    & $adb -s $Serial install -r -t $apk
    continue
  }
  break
}
