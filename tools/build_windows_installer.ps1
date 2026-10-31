<#
.SYNOPSIS
    Builds re_iptv-<version>-windows-x64-setup.exe from an already built app.

.DESCRIPTION
    Wraps tools/windows_installer.iss so the version number comes from
    app/pubspec.yaml rather than from a second copy that will drift. Also
    downloads Microsoft's C++ runtime once into dist\cache, because the Flutter
    runner needs it on a machine that has never had it and the installer is meant
    to be handed to someone whose computer you cannot inspect.

    Inno Setup 6 is required:  winget install JRSoftware.InnoSetup

    The output lands in dist/, which is gitignored - an installer is a build
    artefact, not source.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_windows_installer.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_windows_installer.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    # Use the bundle already in app/build instead of running flutter build again.
    [switch]$SkipBuild,

    # Path to flutter.bat or flutter.exe, for a machine where it is not on PATH.
    [string]$FlutterPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundle = Join-Path $root 'app\build\windows\x64\runner\Release'
$cache = Join-Path $root 'dist\cache'
$iss = Join-Path $PSScriptRoot 'windows_installer.iss'
$vcRedist = Join-Path $cache 'VC_redist.x64.exe'

# The version the installer reports, and the one that decides whether a new
# setup.exe is an upgrade or a second copy of the app: "1.0.4+1" -> "1.0.4".
$pubspec = Get-Content (Join-Path $root 'app\pubspec.yaml')
$line = $pubspec | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1
if (-not $line) { throw 'no version: line in app/pubspec.yaml' }
$version = ([regex]::Match($line, '^version:\s*([^+\s]+)')).Groups[1].Value
Write-Host "version $version"

if (-not $SkipBuild) {
    $flutter = $FlutterPath
    if (-not $flutter) {
        $flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
    }
    if (-not $flutter) {
        throw 'flutter is not on PATH - pass -FlutterPath C:\path\to\flutter\bin\flutter.bat'
    }
    Push-Location (Join-Path $root 'app')
    try {
        & $flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
}

if (-not (Test-Path (Join-Path $bundle 're_iptv.exe'))) {
    throw "no app to package at $bundle - build it first, or drop -SkipBuild"
}

if (-not (Test-Path $vcRedist)) {
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    Write-Host 'downloading the Microsoft C++ runtime...'
    Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcRedist
}

# Inno Setup installs itself per user by default, so it is not on PATH.
$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    $iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) {
    throw 'Inno Setup 6 not found - winget install JRSoftware.InnoSetup'
}

& $iscc "/DAppVersion=$version" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Join-Path $root "dist\re_iptv-$version-windows-x64-setup.exe"
if (-not (Test-Path $setup)) { throw "ISCC reported success but $setup is missing" }
Get-Item $setup | ForEach-Object {
    '{0}  {1:N1} MB' -f $_.FullName, ($_.Length / 1MB)
}
