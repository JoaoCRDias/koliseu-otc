#!/usr/bin/env pwsh
param(
    [string]$Preset = "windows-release",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Import-VsDevEnv {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio 2019/2022 with 'Desktop development with C++' workload."
    }

    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $vsPath) {
        throw "No Visual Studio installation with C++ tools found."
    }

    $vsDevCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path $vsDevCmd)) {
        throw "VsDevCmd.bat not found at $vsDevCmd"
    }

    Write-Host "Loading VS dev environment from $vsPath"
    $envDump = cmd.exe /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}

if (-not $env:VCPKG_ROOT -or -not (Test-Path $env:VCPKG_ROOT)) {
    Write-Host "ERROR: VCPKG_ROOT environment variable is not set or path does not exist."
    Write-Host "Set it (persistent, user scope):"
    Write-Host "  [Environment]::SetEnvironmentVariable('VCPKG_ROOT','C:\path\to\vcpkg','User')"
    exit 1
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    Import-VsDevEnv
}

if (-not (Get-Command ninja.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Ninja not found on PATH. Trying vcpkg-installed copy..."
    $ninjaVcpkg = Get-ChildItem -Path $env:VCPKG_ROOT -Filter ninja.exe -Recurse -ErrorAction SilentlyContinue |
                  Select-Object -First 1
    if ($ninjaVcpkg) {
        $env:PATH = "$($ninjaVcpkg.DirectoryName);$env:PATH"
        Write-Host "Using Ninja at $($ninjaVcpkg.FullName)"
    } else {
        Write-Host "ERROR: Ninja not found. Install it with: winget install Ninja-build.Ninja"
        exit 1
    }
}

Write-Host "Using VCPKG_ROOT = $env:VCPKG_ROOT"
Write-Host "Using preset    = $Preset"
Write-Host "cl.exe          = $((Get-Command cl.exe).Source)"
Write-Host "ninja.exe       = $((Get-Command ninja.exe).Source)"

$buildDir = Join-Path $PSScriptRoot "build\$Preset"

if ($Clean -and (Test-Path $buildDir)) {
    Write-Host "Cleaning $buildDir"
    Remove-Item -Path $buildDir -Recurse -Force
}

Push-Location $PSScriptRoot
try {
    cmake --preset $Preset
    if ($LASTEXITCODE -ne 0) {
        Write-Host "CMake configuration failed!"
        exit 1
    }

    cmake --build --preset $Preset
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Compilation failed!"
        exit 1
    }

    Write-Host "Compilation successful!"
} finally {
    Pop-Location
}
