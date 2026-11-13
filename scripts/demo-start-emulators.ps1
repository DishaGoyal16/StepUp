<#
 Starts the Firebase emulators for the LIVE DEMO, reachable from other devices on the network (binds 0.0.0.0).
 Uses firebase.demo.json (the normal firebase.json used by the tests is untouched). Leave this window open during the demo.
 The emulators have NO security of their own: use a private network (the PC's own hotspot), not the college Wi-Fi.
#>
$root = Split-Path -Parent $PSScriptRoot
$devEnv = Join-Path $root '..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1'
if (Test-Path $devEnv) { . $devEnv | Out-Null } else {
  # dev-env.ps1 lives outside this project; the essential part is the Unix-socket workaround for Gradle/Firebase on Windows.
  New-Item -ItemType Directory -Force C:\jt | Out-Null
  $env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/jt'
}
Set-Location (Join-Path $root 'functions')
npm run build
Set-Location $root
& "$root\functions\node_modules\.bin\firebase.cmd" emulators:start --project demo-stepup --config firebase.demo.json
