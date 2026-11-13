<#
 Builds a DEBUG APK that talks to the demo emulators on this PC over the network (no USB cable needed during the demo).
   .\scripts\demo-build-apk.ps1 [-HostIp 192.168.137.1]
 192.168.137.1 is the address Windows gives the PC when "Mobile hotspot" is on. The host is compiled into the app, so rebuild
 if you use a different network. The output is copied to the Desktop (next to the other deliverables).
#>
param([string]$HostIp = '192.168.137.1')
$root = Split-Path -Parent $PSScriptRoot
$devEnv = Join-Path $root '..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1'
if (Test-Path $devEnv) { . $devEnv | Out-Null } else { New-Item -ItemType Directory -Force C:\jt | Out-Null; $env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/jt' }
$env:Path = 'C:\src\flutter\flutter\bin;' + $env:Path
Set-Location $root
flutter build apk --debug --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=$HostIp
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
$out = Join-Path (Split-Path -Parent $root) "StepUp_DEMO_$($HostIp)-debug.apk"
Copy-Item "$root\build\app\outputs\flutter-apk\app-debug.apk" $out -Force
Get-Item $out | Select-Object FullName, Length, LastWriteTime
