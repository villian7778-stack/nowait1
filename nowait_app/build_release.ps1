# Builds the Google Play bundle (and optionally an APK) with the production settings.
#   .\build_release.ps1          -> build\app\outputs\bundle\release\app-release.aab   (upload this to Play)
#   .\build_release.ps1 -Apk     -> also build\app\outputs\flutter-apk\app-release.apk (for testing on a phone)
# Needs: release.env (copy release.env.example) and android\key.properties (copy android\key.properties.example).
param([switch]$Apk)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path 'release.env')) { throw 'release.env not found - copy release.env.example to release.env and fill it in.' }
$vars = @{}
foreach ($line in Get-Content 'release.env') {
    if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $vars[$Matches[1]] = $Matches[2] }
}
foreach ($k in @('BASE_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY')) {
    if (-not $vars[$k]) { throw "$k is empty in release.env" }
}
if (-not $vars['BASE_URL'].StartsWith('https://')) { throw 'BASE_URL must start with https://' }
if ($vars['BASE_URL'] -match 'localhost|10\.0\.2\.2|192\.168\.') { throw 'BASE_URL points at a development machine.' }
if (-not (Test-Path 'android\key.properties')) {
    throw 'android\key.properties not found - the build would be signed with the debug key, which Google Play rejects. See PRODUCTION.md.'
}

$defines = @(
    "--dart-define=BASE_URL=$($vars['BASE_URL'].TrimEnd('/'))",
    "--dart-define=SUPABASE_URL=$($vars['SUPABASE_URL'])",
    "--dart-define=SUPABASE_ANON_KEY=$($vars['SUPABASE_ANON_KEY'])"
)

flutter clean
flutter pub get
flutter build appbundle --release @defines
if ($LASTEXITCODE -ne 0) { throw 'flutter build appbundle failed' }
Write-Host "Play bundle: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Green
if ($Apk) {
    flutter build apk --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }
    Write-Host "Test APK:    build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
}
