# Creates the Windows plugin links as directory junctions.
#
# Flutter normally creates symbolic links in
# `windows/flutter/ephemeral/.plugin_symlinks`, which requires Developer Mode (or
# an elevated shell) on Windows. Junctions do not, and Flutter skips creating a
# link that already exists, so this script lets the project build without
# changing system settings.
#
# Run AFTER `flutter pub get`.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools/make_plugin_junctions.ps1 [-Project ibo_player] [-Force]

param(
    [string]$Project = "ibo_player",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$dependencies = Join-Path $Project ".flutter-plugins-dependencies"
if (-not (Test-Path $dependencies)) {
    throw "Run 'flutter pub get' in $Project first ($dependencies not found)."
}

$linksDir = Join-Path $Project "windows\flutter\ephemeral\.plugin_symlinks"
if ($Force -and (Test-Path $linksDir)) {
    Remove-Item $linksDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $linksDir | Out-Null

$info = Get-Content $dependencies -Raw | ConvertFrom-Json
$platformPlugins = $info.plugins.windows
if ($null -eq $platformPlugins) {
    Write-Host "No Windows plugins declared."
    exit 0
}

$created = 0
foreach ($plugin in $platformPlugins) {
    $name = [string]$plugin.name
    $target = ([string]$plugin.path).TrimEnd('\', '/')
    if (-not (Test-Path $target)) {
        Write-Warning "skip $name (missing $target)"
        continue
    }

    $linkPath = Join-Path $linksDir $name
    if (Test-Path $linkPath) {
        Write-Host "exists   $name"
        continue
    }

    New-Item -ItemType Junction -Path $linkPath -Target $target | Out-Null
    Write-Host "junction $name -> $target"
    $created++
}

Write-Host ""
Write-Host "Created $created plugin junction(s) in $linksDir"
