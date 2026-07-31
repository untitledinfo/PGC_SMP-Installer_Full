<#
    build-exe.ps1
    ---------------------------------------------------------------
    One-click builder: turns Install-PGC-SMP-GUI.ps1 into
    PGC_SMP_Installer.exe using the ps2exe module.

    Run this ON WINDOWS, in the same folder as:
      - Install-PGC-SMP-GUI.ps1
      - PGC_SMP_1_0_0.mrpack
      - build-exe.ps1  (this file)

    Right-click this file -> "Run with PowerShell", or from a
    PowerShell prompt:  .\build-exe.ps1
#>

$ErrorActionPreference = "Stop"
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$SourcePs1 = Join-Path $Here "Install-PGC-SMP-GUI.ps1"
$OutputExe = Join-Path $Here "PGC_SMP_Installer.exe"

Write-Host "=== PGC SMP Installer - EXE Builder ===" -ForegroundColor Cyan

if (-not (Test-Path $SourcePs1)) {
    Write-Host "[X] Could not find Install-PGC-SMP-GUI.ps1 next to this script." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ---------------------------------------------------------------------------
# Make sure ps2exe is installed
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "[..] ps2exe module not found - installing for current user..." -ForegroundColor Yellow
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
        }
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    } catch {
        Write-Host "[X] Failed to install ps2exe automatically: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Try running PowerShell as Administrator and re-run this script," -ForegroundColor Yellow
        Write-Host "    or install manually: Install-Module ps2exe -Scope CurrentUser" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Import-Module ps2exe -Force

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
Write-Host "[..] Compiling $((Get-Item $SourcePs1).Name) -> PGC_SMP_Installer.exe ..." -ForegroundColor Yellow

try {
    Invoke-ps2exe -inputFile $SourcePs1 `
                   -outputFile $OutputExe `
                   -noConsole `
                   -title "PGC SMP Installer" `
                   -description "PGC SMP One-Click Modpack Installer" `
                   -company "PGC" `
                   -product "PGC SMP Installer" `
                   -version "1.2.0.0" `
                   -requireAdmin:$false
} catch {
    Write-Host "[X] Build failed: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (Test-Path $OutputExe) {
    Write-Host ""
    Write-Host "[OK] Built: $OutputExe" -ForegroundColor Green
    Write-Host "     Keep PGC_SMP_Installer.exe next to PGC_SMP_1_0_0.mrpack" -ForegroundColor Green
    Write-Host "     when you distribute it - the installer looks for the" -ForegroundColor Green
    Write-Host "     .mrpack file in its own folder." -ForegroundColor Green
} else {
    Write-Host "[X] ps2exe reported no error but the exe was not created." -ForegroundColor Red
}

Read-Host "Press Enter to exit"
