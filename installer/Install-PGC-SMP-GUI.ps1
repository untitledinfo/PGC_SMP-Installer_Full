<#
    PGC SMP - One-Click Modpack Installer (GUI)  v1.4.0
    ------------------------------------------------------
    Pack   : PGC SMP v1.0.0
    Game   : Minecraft 1.20.1
    Loader : Forge 47.4.20

    Scope: this installer ONLY extracts/copies the modpack's files (mods,
    configs, resourcepacks, overrides) into the target instance folder and
    registers a launcher profile if using the Official Launcher. It does not
    check for, download, or install Java or Forge - if you're using the
    Official Minecraft Launcher, install Forge 47.4.20 for Minecraft 1.20.1
    yourself first (files.minecraftforge.net). Third-party launchers (Prism,
    Modrinth App, MultiMC, CurseForge) manage their own Java/loader installs,
    so this only matters for the Official Launcher path.

    Only supports legitimate, owned Minecraft accounts (Official Launcher with
    a Microsoft/paid account, or a third-party launcher's own legitimate auth).
    It does not support offline/cracked accounts.

    Requires: Windows + PowerShell 5.1+ (built into Windows 10/11).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = "Stop"
$AppVersion = "1.4.0"

# Set this to "yourname/your-repo" to enable a GitHub-releases self-update
# check on startup. Left blank = feature silently skipped, no network call.
$GithubRepo = ""

# Defense in depth: this is the one place that ever calls a WinForms
# .Items.Add() with a value that might legitimately be null (a hashtable
# lookup, an API result, etc). Routing every such call through here means
# the exact "Add": "Value cannot be null. Parameter name: item" crash this
# script used to hit can't happen again, even if the upstream logic that
# builds the value changes later and reintroduces a gap.
function Add-SafeListItem($control, $item) {
    if ([string]::IsNullOrWhiteSpace([string]$item)) {
        return
    }
    try { [void]$control.Items.Add($item) } catch { }
}

function Get-AppDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    try {
        $procPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($procPath) { return (Split-Path -Parent $procPath) }
    } catch { }
    return (Get-Location).Path
}

try {
    $ScriptDir  = Get-AppDir
    $MrpackFile = Join-Path $ScriptDir "PGC_SMP_1_0_0.mrpack"
    $WorkDir    = Join-Path $env:TEMP "PGC_SMP_Install"
    $SettingsDir = Join-Path $env:APPDATA "PGC_SMP_Installer"
    $SettingsFile = Join-Path $SettingsDir "settings.json"
    $McVersion  = "1.20.1"
    $ForgeVersion = "47.4.20"
    $ForgeFullVersion = "$McVersion-$ForgeVersion"
    $ForgeVersionId = "$McVersion-forge-$ForgeVersion"
} catch {
    [System.Windows.Forms.MessageBox]::Show("Startup error: $($_.Exception.Message)", "PGC SMP Installer", "OK", "Error") | Out-Null
    exit 1
}

function Load-Settings {
    if (Test-Path $SettingsFile) {
        try { return (Get-Content $SettingsFile -Raw | ConvertFrom-Json) } catch { }
    }
    return [PSCustomObject]@{ LastInstallPath = $null; RamGB = 4; Language = "EN" }
}
function Save-Settings($s) {
    try {
        New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
        $s | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
    } catch { }
}
$Settings = Load-Settings

$Strings = @{
    EN = @{
        Launcher   = "Detected launcher / install folder:"
        Install    = "Install Path:"
        InstallBtn = "Install"
        Cancel     = "Cancel"
        Uninstall  = "Uninstall"
        OpenFolder = "Open Folder"
        SaveLog    = "Save Log"
        Ram        = "RAM allocation (GB):"
        Ready      = "Ready."
        Mods       = "Mods included:"
        MrpackLabel = "Modpack (.mrpack) file:"
        MrpackMissing = "No modpack file loaded yet - click Browse to select a .mrpack file."
        VerifyBtn = "Verify Files"
        CheckUpdateBtn = "Check for Updates"
    }
    UR = @{
        Launcher   = "Launcher / install folder mila:"
        Install    = "Install Path:"
        InstallBtn = "Install Karo"
        Cancel     = "Cancel Karo"
        Uninstall  = "Uninstall Karo"
        OpenFolder = "Folder Kholo"
        SaveLog    = "Log Save Karo"
        Ram        = "RAM (GB):"
        Ready      = "Tayyar hai."
        Mods       = "Mods shamil:"
        MrpackLabel = "Modpack (.mrpack) faayl:"
        MrpackMissing = "Abhi tak koi modpack file load nahi hui - Browse per click karke .mrpack file chunein."
        VerifyBtn = "Files Verify Karo"
        CheckUpdateBtn = "Updates Check Karo"
    }
}
$Lang = if ($Settings.Language -eq "UR") { "UR" } else { "EN" }
function T($key) { return $Strings[$Lang][$key] }

# ---------------------------------------------------------------------------
# Read modrinth.index.json directly out of the zip - no extraction to disk.
# (Replaces the old "preview" folder, which extracted the whole pack twice
# and could show stale/incorrect numbers if that folder wasn't cleaned up.)
# ---------------------------------------------------------------------------
function Get-IndexFromMrpack($mrpackPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($mrpackPath)
    try {
        $entry = $zip.GetEntry("modrinth.index.json")
        if (-not $entry) { throw "modrinth.index.json not found inside the .mrpack" }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return ($json | ConvertFrom-Json)
    } finally {
        $zip.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Generic retry wrapper for external API calls (Modrinth, GitHub). A single
# transient network blip used to mean "give up silently, fall back to
# filenames/no update info" - this retries a couple of times with a short
# backoff first, which is enough to ride out most flaky-wifi hiccups without
# making the UI feel like it's hanging (kept short: 2 retries, <1s total).
# ---------------------------------------------------------------------------
function Invoke-ApiWithRetry([scriptblock]$Call, [int]$MaxAttempts = 3) {
    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            return & $Call
        } catch {
            if ($attempt -ge $MaxAttempts) { throw }
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
}

# ---------------------------------------------------------------------------
# Modrinth API: batch-resolve friendly mod names instead of raw jar filenames.
# Best-effort - if there's no internet yet, or the API is unreachable, this
# silently falls back to filenames, it never blocks the installer.
# ---------------------------------------------------------------------------
function Get-ModrinthNames($index) {
    $names = @{}
    $projectIds = @()
    foreach ($f in $index.files) {
        if ($f.downloads -and $f.downloads[0] -match "cdn\.modrinth\.com/data/([^/]+)/versions/") {
            $projectIds += $matches[1]
        }
    }
    $projectIds = $projectIds | Select-Object -Unique
    if ($projectIds.Count -eq 0) { return $names }
    try {
        $idsJson = ($projectIds | ForEach-Object { '"' + $_ + '"' }) -join ","
        $url = "https://api.modrinth.com/v2/projects?ids=[$idsJson]"
        $resp = Invoke-ApiWithRetry { Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 8 }
        foreach ($proj in $resp) { $names[$proj.id] = $proj.title }
    } catch {
        # offline or API down after retries - filenames will be used instead, no big deal
    }
    return $names
}

function Get-DetectedPaths {
    $candidates = [ordered]@{
        "Official Minecraft Launcher" = @(
            (Join-Path $env:APPDATA ".minecraft"),
            (Join-Path $env:USERPROFILE ".minecraft"),
            "C:\Games\.minecraft",
            "D:\Games\.minecraft"
        )
        "Modrinth App"   = @( (Join-Path $env:APPDATA "com.modrinth.theseus") )
        "Prism Launcher" = @( (Join-Path $env:APPDATA "PrismLauncher") )
        "MultiMC"        = @( (Join-Path $env:APPDATA "MultiMC"), "C:\MultiMC" )
        "ATLauncher"     = @( (Join-Path $env:APPDATA "ATLauncher") )
        "GDLauncher"     = @( (Join-Path $env:APPDATA "gdlauncher_next") )
        "CurseForge App" = @( (Join-Path $env:USERPROFILE "curseforge\minecraft") )
    }
    try {
        $regKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Minecraft Launcher"
        if (Test-Path $regKey) {
            $installLoc = (Get-ItemProperty -Path $regKey -ErrorAction SilentlyContinue).InstallLocation
            if ($installLoc) { $candidates["Official Minecraft Launcher"] += (Join-Path $installLoc ".minecraft") }
        }
    } catch { }

    $found = [ordered]@{}
    foreach ($name in $candidates.Keys) {
        foreach ($path in $candidates[$name]) {
            if ($path -and (Test-Path $path) -and -not $found.Contains($name)) {
                $found[$name] = $path
            }
        }
    }
    return $found
}

# ---------------------------------------------------------------------------
# Real, single-source pack summary (real file list, real sizes, real names).
# Wrapped in a function (not just run once at startup) so picking a different
# .mrpack file via the new "Modpack file" browse button can reload it.
# ---------------------------------------------------------------------------
function Load-Pack($path) {
    $script:PackIndex = $null
    $script:PackSummary = $null
    $script:ModDisplayNames = @{}

    if (-not (Test-Path $path)) { return $false }

    try {
        $script:PackIndex = Get-IndexFromMrpack $path
        $totalBytes = ($script:PackIndex.files | Measure-Object -Property fileSize -Sum).Sum
        $script:PackSummary = [PSCustomObject]@{
            ModCount = $script:PackIndex.files.Count
            TotalMB  = [math]::Round($totalBytes / 1MB, 1)
        }
        $projNames = Get-ModrinthNames $script:PackIndex
    } catch {
        # Reading the index/summary itself failed (corrupt zip, unreadable
        # modrinth.index.json, wrong file selected, etc). Reset everything
        # together so the rest of the script sees a clean "no pack loaded"
        # state instead of a half-populated one - this is what previously let
        # $PackIndex stay set while $ModDisplayNames was left incomplete,
        # which is what caused the "Add": "Value cannot be null. Parameter
        # name: item" crash further down when the mod list tried to render.
        $script:PackIndex = $null
        $script:PackSummary = $null
        $projNames = @{}
    }

    # BUGFIX: this used to live inside the try/catch above as one unit, so a
    # single bad entry (missing/odd path, a lookup failure, etc.) could throw
    # partway through and leave $ModDisplayNames with holes for the remaining
    # files, while $PackIndex stayed set — that mismatch is exactly what let
    # a $null reach $listMods.Items.Add() later. Each file is now resolved
    # independently: whatever happens, every file that exists in $PackIndex
    # gets *some* non-null display name.
    if ($script:PackIndex) {
        foreach ($f in $script:PackIndex.files) {
            $friendly = $null
            try {
                if ($f.downloads -and $f.downloads.Count -gt 0 -and $f.downloads[0] -match "cdn\.modrinth\.com/data/([^/]+)/versions/") {
                    # NOTE: this used to be named $pid, which is a *read-only* PowerShell
                    # automatic variable (the current process ID). Assigning to it throws
                    # "Cannot overwrite variable PID because it is read-only or constant"
                    # on literally the first Modrinth-hosted file in the pack — which is why
                    # this crashed every single run, not just sometimes.
                    $projectId = $matches[1]
                    if ($projNames -and $projNames.ContainsKey($projectId)) { $friendly = $projNames[$projectId] }
                }
            } catch {
                # name-lookup failed for this one file only - fall through to the
                # filename-based fallback below, don't let it affect other files
            }

            if ([string]::IsNullOrWhiteSpace($friendly)) {
                if (-not [string]::IsNullOrWhiteSpace($f.path)) {
                    try { $friendly = [System.IO.Path]::GetFileNameWithoutExtension($f.path) } catch { $friendly = $f.path }
                }
            }
            if ([string]::IsNullOrWhiteSpace($friendly)) { $friendly = "(unnamed file)" }

            if (-not [string]::IsNullOrWhiteSpace($f.path)) {
                $script:ModDisplayNames[$f.path] = $friendly
            }
        }
    }

    return ($null -ne $script:PackIndex)
}

Load-Pack $MrpackFile | Out-Null

# ---------------------------------------------------------------------------
# Self-update check (GitHub Releases API). Startup call stays silent/optional
# (never blocks the installer if unconfigured or offline); the "Check for
# Updates" button below calls the same function on demand and actually tells
# the player what happened either way, instead of only working invisibly.
# ---------------------------------------------------------------------------
function Test-ForUpdate {
    if (-not $GithubRepo) { return $null }
    try {
        $rel = Invoke-ApiWithRetry {
            Invoke-RestMethod -Uri "https://api.github.com/repos/$GithubRepo/releases/latest" -TimeoutSec 6 -Headers @{ "User-Agent" = "PGC-SMP-Installer" }
        }
        $latestTag = ($rel.tag_name -replace '^v','')
        if ($latestTag -and $latestTag -ne $AppVersion) { return $latestTag }
        return $null
    } catch {
        return $null
    }
}
$UpdateAvailable = Test-ForUpdate

# ---------------------------------------------------------------------------
# Build the form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "PGC SMP Installer v$AppVersion"
$form.Size = New-Object System.Drawing.Size(620, 745)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "PGC SMP  -  Minecraft $McVersion  |  Forge $ForgeVersion"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(15, 12)
$title.Size = New-Object System.Drawing.Size(470, 30)
$form.Controls.Add($title)

$comboLang = New-Object System.Windows.Forms.ComboBox
$comboLang.Items.AddRange(@("EN", "UR"))
$comboLang.SelectedItem = $Lang
$comboLang.DropDownStyle = "DropDownList"
$comboLang.Location = New-Object System.Drawing.Point(540, 15)
$comboLang.Size = New-Object System.Drawing.Size(60, 24)
$form.Controls.Add($comboLang)

$lblSummary = New-Object System.Windows.Forms.Label
if ($PackSummary) {
    $lblSummary.Text = "$($PackSummary.ModCount) mods  -  approx $($PackSummary.TotalMB) MB to download"
} else {
    $lblSummary.Text = T "MrpackMissing"
}
if ($UpdateAvailable) {
    $lblSummary.Text += "   |   Update available: v$UpdateAvailable"
}
$lblSummary.ForeColor = [System.Drawing.Color]::DimGray
$lblSummary.Location = New-Object System.Drawing.Point(15, 42)
$lblSummary.Size = New-Object System.Drawing.Size(580, 20)
$form.Controls.Add($lblSummary)

# --- Modpack (.mrpack) file picker ------------------------------------------
# Previously hardcoded to whatever PGC_SMP_1_0_0.mrpack happened to be sitting
# next to the exe, with no way to point at a different pack without renaming
# files by hand. Now it's a real path selector, same pattern as the Install
# Path row below it.
$lblMrpack = New-Object System.Windows.Forms.Label
$lblMrpack.Text = T "MrpackLabel"
$lblMrpack.Location = New-Object System.Drawing.Point(15, 64)
$lblMrpack.Size = New-Object System.Drawing.Size(300, 18)
$form.Controls.Add($lblMrpack)

$txtMrpack = New-Object System.Windows.Forms.TextBox
$txtMrpack.Location = New-Object System.Drawing.Point(15, 83)
$txtMrpack.Size = New-Object System.Drawing.Size(480, 24)
$txtMrpack.Text = $MrpackFile
$form.Controls.Add($txtMrpack)

$btnBrowseMrpack = New-Object System.Windows.Forms.Button
$btnBrowseMrpack.Text = "Browse..."
$btnBrowseMrpack.Location = New-Object System.Drawing.Point(505, 82)
$btnBrowseMrpack.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnBrowseMrpack)

$lblLauncher = New-Object System.Windows.Forms.Label
$lblLauncher.Text = T "Launcher"
$lblLauncher.Location = New-Object System.Drawing.Point(15, 118)
$lblLauncher.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($lblLauncher)

$comboLaunchers = New-Object System.Windows.Forms.ComboBox
$comboLaunchers.Location = New-Object System.Drawing.Point(15, 140)
$comboLaunchers.Size = New-Object System.Drawing.Size(480, 24)
$comboLaunchers.DropDownStyle = "DropDownList"
$form.Controls.Add($comboLaunchers)

$btnRescan = New-Object System.Windows.Forms.Button
$btnRescan.Text = "Rescan"
$btnRescan.Location = New-Object System.Drawing.Point(505, 139)
$btnRescan.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnRescan)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = T "Install"
$lblPath.Location = New-Object System.Drawing.Point(15, 174)
$lblPath.Size = New-Object System.Drawing.Size(90, 20)
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(105, 172)
$txtPath.Size = New-Object System.Drawing.Size(390, 24)
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(505, 171)
$btnBrowse.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnBrowse)

$lblRam = New-Object System.Windows.Forms.Label
$lblRam.Text = T "Ram"
$lblRam.Location = New-Object System.Drawing.Point(15, 206)
$lblRam.Size = New-Object System.Drawing.Size(140, 20)
$form.Controls.Add($lblRam)

$numRam = New-Object System.Windows.Forms.NumericUpDown
$numRam.Location = New-Object System.Drawing.Point(160, 204)
$numRam.Size = New-Object System.Drawing.Size(60, 24)
$numRam.Minimum = 2
$numRam.Maximum = 16
$numRam.Value = [Math]::Min([Math]::Max([int]$Settings.RamGB, 2), 16)
$form.Controls.Add($numRam)

$lblMods = New-Object System.Windows.Forms.Label
$lblMods.Text = T "Mods"
$lblMods.Location = New-Object System.Drawing.Point(15, 238)
$lblMods.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($lblMods)

$listMods = New-Object System.Windows.Forms.ListBox
$listMods.Location = New-Object System.Drawing.Point(15, 260)
$listMods.Size = New-Object System.Drawing.Size(575, 90)
if ($PackIndex) {
    foreach ($f in ($PackIndex.files | Sort-Object { $ModDisplayNames[$_.path] })) {
        Add-SafeListItem $listMods $ModDisplayNames[$f.path]
    }
}
$form.Controls.Add($listMods)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 361)
$progressBar.Size = New-Object System.Drawing.Size(575, 24)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = T "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(15, 389)
$lblStatus.Size = New-Object System.Drawing.Size(575, 20)
$form.Controls.Add($lblStatus)

# Live "console" - colour coded, auto-scrolling
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::Black
$txtLog.ForeColor = [System.Drawing.Color]::Gainsboro
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Location = New-Object System.Drawing.Point(15, 415)
$txtLog.Size = New-Object System.Drawing.Size(575, 200)
$form.Controls.Add($txtLog)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = T "InstallBtn"
$btnInstall.Location = New-Object System.Drawing.Point(15, 625)
$btnInstall.Size = New-Object System.Drawing.Size(120, 34)
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = T "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(145, 625)
$btnCancel.Size = New-Object System.Drawing.Size(100, 34)
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = T "OpenFolder"
$btnOpenFolder.Location = New-Object System.Drawing.Point(255, 625)
$btnOpenFolder.Size = New-Object System.Drawing.Size(110, 34)
$btnOpenFolder.Enabled = $false
$form.Controls.Add($btnOpenFolder)

$btnSaveLog = New-Object System.Windows.Forms.Button
$btnSaveLog.Text = T "SaveLog"
$btnSaveLog.Location = New-Object System.Drawing.Point(375, 625)
$btnSaveLog.Size = New-Object System.Drawing.Size(90, 34)
$form.Controls.Add($btnSaveLog)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = T "Uninstall"
$btnUninstall.Location = New-Object System.Drawing.Point(475, 625)
$btnUninstall.Size = New-Object System.Drawing.Size(115, 34)
$form.Controls.Add($btnUninstall)

$btnVerify = New-Object System.Windows.Forms.Button
$btnVerify.Text = T "VerifyBtn"
$btnVerify.Location = New-Object System.Drawing.Point(15, 665)
$btnVerify.Size = New-Object System.Drawing.Size(160, 30)
$form.Controls.Add($btnVerify)

$btnCheckUpdate = New-Object System.Windows.Forms.Button
$btnCheckUpdate.Text = T "CheckUpdateBtn"
$btnCheckUpdate.Location = New-Object System.Drawing.Point(185, 665)
$btnCheckUpdate.Size = New-Object System.Drawing.Size(160, 30)
$form.Controls.Add($btnCheckUpdate)

if (-not (Test-Path $MrpackFile)) {
    [System.Windows.Forms.MessageBox]::Show(
        "No PGC_SMP_1_0_0.mrpack found next to this program.`nClick 'Browse...' next to 'Modpack (.mrpack) file' to select one.",
        "PGC SMP Installer", "OK", "Information") | Out-Null
}

# Re-renders the summary label + mod list from whatever's currently loaded in
# $script:PackIndex/$script:PackSummary/$script:ModDisplayNames. Called once
# implicitly via the initial Load-Pack above, and again any time the user
# picks a different .mrpack file.
function Refresh-PackDisplay {
    if ($script:PackSummary) {
        $lblSummary.Text = "$($script:PackSummary.ModCount) mods  -  approx $($script:PackSummary.TotalMB) MB to download"
    } else {
        $lblSummary.Text = T "MrpackMissing"
    }
    $listMods.Items.Clear()
    if ($script:PackIndex) {
        foreach ($f in ($script:PackIndex.files | Sort-Object { $script:ModDisplayNames[$_.path] })) {
            Add-SafeListItem $listMods $script:ModDisplayNames[$f.path]
        }
    }
}

function Populate-Launchers {
    $comboLaunchers.Items.Clear()
    $script:DetectedPaths = Get-DetectedPaths
    if ($script:DetectedPaths.Count -eq 0) {
        Add-SafeListItem $comboLaunchers "Official Minecraft Launcher (not found - will create)"
        $script:DetectedPaths["Official Minecraft Launcher (not found - will create)"] = (Join-Path $env:APPDATA ".minecraft")
    } else {
        foreach ($name in $script:DetectedPaths.Keys) {
            Add-SafeListItem $comboLaunchers "$name  ->  $($script:DetectedPaths[$name])"
        }
    }
    $comboLaunchers.SelectedIndex = 0
}
Populate-Launchers

$comboLaunchers.Add_SelectedIndexChanged({
    $selectedName = ($script:DetectedPaths.Keys | Select-Object -Index $comboLaunchers.SelectedIndex)
    $basePath = $script:DetectedPaths[$selectedName]
    if ($Settings.LastInstallPath -and (Test-Path (Split-Path $Settings.LastInstallPath -Parent))) {
        $txtPath.Text = $Settings.LastInstallPath
    } elseif ($selectedName -like "Official Minecraft Launcher*") {
        $txtPath.Text = Join-Path $basePath "PGC_SMP"
    } else {
        $txtPath.Text = $basePath
    }
})
$comboLaunchers.SelectedIndex = 0

$comboLang.Add_SelectedIndexChanged({
    $script:Lang = $comboLang.SelectedItem.ToString()
    $Settings.Language = $script:Lang
    $lblLauncher.Text = T "Launcher"
    $lblPath.Text = T "Install"
    $lblRam.Text = T "Ram"
    $lblMods.Text = T "Mods"
    $lblMrpack.Text = T "MrpackLabel"
    $btnInstall.Text = T "InstallBtn"
    $btnCancel.Text = T "Cancel"
    $btnOpenFolder.Text = T "OpenFolder"
    $btnSaveLog.Text = T "SaveLog"
    $btnUninstall.Text = T "Uninstall"
    $btnVerify.Text = T "VerifyBtn"
    $btnCheckUpdate.Text = T "CheckUpdateBtn"
    if (-not $script:PackSummary) { $lblSummary.Text = T "MrpackMissing" }
    if (-not $sync -or $sync.Status -eq "Idle" -or $sync.Done) { $lblStatus.Text = T "Ready" }
})

$btnRescan.Add_Click({ Populate-Launchers })

$btnBrowseMrpack.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Select a modpack (.mrpack) file"
    $ofd.Filter = "Modrinth Modpack (*.mrpack)|*.mrpack|All files (*.*)|*.*"
    $initialDir = Split-Path $txtMrpack.Text -Parent -ErrorAction SilentlyContinue
    if ($initialDir -and (Test-Path $initialDir)) { $ofd.InitialDirectory = $initialDir }
    if ($ofd.ShowDialog() -eq "OK") {
        $txtMrpack.Text = $ofd.FileName
        $script:MrpackFile = $ofd.FileName
        $ok = Load-Pack $ofd.FileName
        Refresh-PackDisplay
        if (-not $ok) {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not read that file as a valid .mrpack modpack.`nMake sure it's an unmodified Modrinth modpack export.",
                "PGC SMP Installer", "OK", "Error") | Out-Null
        }
    }
})

$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Choose the folder to install PGC SMP into"
    if ($fbd.ShowDialog() -eq "OK") { $txtPath.Text = $fbd.SelectedPath }
})

$btnOpenFolder.Add_Click({
    if (Test-Path $txtPath.Text) { Start-Process explorer.exe $txtPath.Text }
})

$btnSaveLog.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "Text file (*.txt)|*.txt"
    $sfd.FileName = "PGC_SMP_install_log.txt"
    if ($sfd.ShowDialog() -eq "OK") { $txtLog.Text | Set-Content -Path $sfd.FileName -Encoding UTF8 }
})

$btnCheckUpdate.Add_Click({
    if (-not $GithubRepo) {
        [System.Windows.Forms.MessageBox]::Show(
            "Update checking isn't configured for this build (no `$GithubRepo set).",
            "PGC SMP Installer", "OK", "Information") | Out-Null
        return
    }
    $btnCheckUpdate.Enabled = $false
    $btnCheckUpdate.Text = "Checking..."
    [System.Windows.Forms.Application]::DoEvents()
    $latest = Test-ForUpdate
    $btnCheckUpdate.Enabled = $true
    $btnCheckUpdate.Text = T "CheckUpdateBtn"
    if ($latest) {
        $script:UpdateAvailable = $latest
        $lblSummary.Text = "$($lblSummary.Text -replace '\s*\|\s*Update available:.*$','')   |   Update available: v$latest"
        [System.Windows.Forms.MessageBox]::Show(
            "A newer version is available: v$latest (you're on v$AppVersion).",
            "PGC SMP Installer", "OK", "Information") | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "You're on the latest version (v$AppVersion).",
            "PGC SMP Installer", "OK", "Information") | Out-Null
    }
})

$btnUninstall.Add_Click({
    $target = $txtPath.Text
    if (-not (Test-Path $target)) {
        [System.Windows.Forms.MessageBox]::Show("Nothing installed at:`n$target", "PGC SMP Installer", "OK", "Information") | Out-Null
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will permanently delete:`n$target`n`nAnd remove the 'PGC SMP' launcher profile if present. Continue?",
        "Confirm Uninstall", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }
    try {
        Remove-Item -Path $target -Recurse -Force
        $selectedName = ($script:DetectedPaths.Keys | Select-Object -Index $comboLaunchers.SelectedIndex)
        if ($selectedName -like "Official Minecraft Launcher*") {
            $dotMc = $script:DetectedPaths[$selectedName]
            $profilesFile = Join-Path $dotMc "launcher_profiles.json"
            if (Test-Path $profilesFile) {
                $pj = Get-Content $profilesFile -Raw | ConvertFrom-Json
                if ($pj.profiles.PSObject.Properties.Name -contains "PGC_SMP") {
                    $pj.profiles.PSObject.Properties.Remove("PGC_SMP")
                    $pj | ConvertTo-Json -Depth 10 | Set-Content -Path $profilesFile -Encoding UTF8
                }
            }
        }
        [System.Windows.Forms.MessageBox]::Show("PGC SMP has been uninstalled.", "PGC SMP Installer", "OK", "Information") | Out-Null
        $btnOpenFolder.Enabled = $false
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Uninstall failed: $($_.Exception.Message)", "PGC SMP Installer", "OK", "Error") | Out-Null
    }
})

function Append-ColorLog($msg, $color) {
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $color
    $txtLog.AppendText("$msg`r`n")
    $txtLog.SelectionColor = $txtLog.ForeColor
    $txtLog.ScrollToCaret()
}
function Color-ForLine($line) {
    if ($line -match '^\[OK\]|downloaded:|already up to date:') { return [System.Drawing.Color]::LightGreen }
    if ($line -match '^\[X\]|failed|Giving up|mismatch') { return [System.Drawing.Color]::Salmon }
    if ($line -match '^\[!\]') { return [System.Drawing.Color]::Khaki }
    return [System.Drawing.Color]::Gainsboro
}

# ---------------------------------------------------------------------------
# Background worker (runspace) - live per-file download progress via
# WebClient async events, so the status line updates in real time (percent,
# MB done/total, speed) instead of only showing a line once a file finishes.
# ---------------------------------------------------------------------------
$sync = [hashtable]::Synchronized(@{
    Log      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    Progress = 0
    Status   = "Idle"
    Done     = $false
    Failed   = $false
    Cancel   = $false
    OkCount  = 0
    FailCount = 0
    SkipCount = 0
    MissingCount = 0
    CorruptCount = 0
})

$installScript = {
    param($sync, $InstallDir, $UseOfficial, $MrpackFile, $WorkDir, $McVersion, $ForgeVersion, $ForgeFullVersion, $ForgeVersionId, $DotMinecraft, $RamGB, $ModNamesMap, $VerifyOnly)

    function Log($m)      { $sync.Log.Add($m) | Out-Null }
    function SetProgress($p) { $sync.Progress = [int]$p }
    function SetStatus($s)   { $sync.Status = $s }

    function Download-WithProgress($url, $destPath, $displayName) {
        $wc = New-Object System.Net.WebClient
        $doneEvt = New-Object System.Threading.ManualResetEventSlim($false)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $script:dlError = $null

        $progHandler = {
            param($s, $e)
            $mbDone = [math]::Round($e.BytesReceived / 1MB, 2)
            $mbTotal = [math]::Round($e.TotalBytesToReceive / 1MB, 2)
            $secs = [math]::Max($sw.Elapsed.TotalSeconds, 0.1)
            $speed = [math]::Round(($e.BytesReceived / 1MB) / $secs, 2)
            $sync.Status = "Downloading $displayName - $($e.ProgressPercentage)% ($mbDone/$mbTotal MB) - $speed MB/s"
        }
        $compHandler = {
            param($s, $e)
            if ($e.Error) { $script:dlError = $e.Error.Message }
            $doneEvt.Set()
        }
        Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -Action $progHandler | Out-Null
        Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted -Action $compHandler | Out-Null

        try {
            $wc.DownloadFileAsync([Uri]$url, $destPath)
            while (-not $doneEvt.Wait(150)) {
                if ($sync.Cancel) { $wc.CancelAsync(); $doneEvt.Wait(2000) | Out-Null; break }
            }
        } finally {
            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $wc } | Unregister-Event
            $wc.Dispose()
        }
        return $script:dlError
    }

    # -----------------------------------------------------------------------
    # "PC checker" - basic system requirements sanity check. Logs warnings for
    # soft issues (low RAM vs requested allocation) and returns $false only
    # for hard blockers (32-bit OS, which can't run 64-bit Java/Minecraft/Forge
    # at all - nothing this installer does can work around that).
    # -----------------------------------------------------------------------
    function Test-SystemRequirements($requestedRamGB) {
        $ok = $true
        try {
            $is64Os = [Environment]::Is64BitOperatingSystem
            if (-not $is64Os) {
                Log "[X] 32-bit Windows detected. Modern Minecraft/Forge/Java all require 64-bit Windows - this PC can't run PGC SMP."
                $ok = $false
            } else {
                Log "[OK] 64-bit Windows detected."
            }
        } catch { }

        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $caption = $os.Caption
            Log "[OK] OS: $caption"
        } catch { }

        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
            Log "[OK] System RAM: ${totalRamGB} GB"
            # Leave roughly 2 GB headroom for Windows + the launcher itself.
            if ($requestedRamGB -gt ($totalRamGB - 2)) {
                Log "[!] You allocated ${requestedRamGB} GB to Minecraft but this PC only has ${totalRamGB} GB total. Consider lowering the RAM slider - allocating nearly all system RAM can cause crashes or a frozen PC while playing."
            }
        } catch { }

        return $ok
    }

    try {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $InstallDir "mods") -Force | Out-Null
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

        SetStatus "Reading pack index..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($MrpackFile)
        $entry = $zip.GetEntry("modrinth.index.json")
        $reader = New-Object System.IO.StreamReader($entry.Open())
        $indexJson = $reader.ReadToEnd()
        $reader.Dispose()
        $zip.Dispose()
        $index = $indexJson | ConvertFrom-Json
        $neededBytes = ($index.files | Measure-Object -Property fileSize -Sum).Sum

        SetStatus "Checking disk space..."
        try {
            $drive = (Get-Item $InstallDir).PSDrive
            $freeBytes = (Get-PSDrive $drive.Name).Free
            if ($freeBytes -lt ($neededBytes * 1.3)) {
                Log "[!] Low disk space warning: need roughly $([math]::Round($neededBytes/1MB,0)) MB, only $([math]::Round($freeBytes/1MB,0)) MB free."
            }
        } catch { }

        SetStatus "Checking system requirements..."
        if (-not (Test-SystemRequirements $RamGB)) {
            $sync.Failed = $true; $sync.Done = $true; return
        }

        if ($UseOfficial) {
            # This installer only extracts/copies modpack files (mods, configs,
            # resourcepacks, overrides) - it does not check, download, or install
            # Java or Forge. If you're using the Official Minecraft Launcher,
            # make sure Forge $ForgeVersion for Minecraft $McVersion is already
            # installed (files.minecraftforge.net) before launching the "PGC SMP"
            # profile this installer creates - otherwise the profile will exist
            # but won't have a working game version to launch.
            $versionFolder = Join-Path $DotMinecraft "versions\$ForgeVersionId"
            if (Test-Path $versionFolder) {
                Log "[OK] Forge $ForgeVersion already installed."
            } else {
                Log "[!] Forge $ForgeVersion for Minecraft $McVersion isn't installed yet. This installer only places the modpack's mod/config files - it doesn't install Forge or Java. Install Forge $ForgeVersion from https://files.minecraftforge.net first, then launch the 'PGC SMP' profile."
            }
        }
        SetProgress 10
        if ($sync.Cancel) { Log "[!] Cancelled."; $sync.Done = $true; return }

        $extractDir = Join-Path $WorkDir "extracted"
        if (-not $VerifyOnly) {
            SetStatus "Unpacking modpack overrides..."
            if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
            [System.IO.Compression.ZipFile]::ExtractToDirectory($MrpackFile, $extractDir)
        }
        Log "[OK] Pack read: $($index.files.Count) mods, approx $([math]::Round($neededBytes/1MB,1)) MB."
        SetProgress 15

        $total = $index.files.Count
        $i = 0
        foreach ($file in $index.files) {
            if ($sync.Cancel) { Log "[!] Cancelled by user."; break }
            $i++
            $relPath = $file.path -replace "/", "\"
            $destPath = Join-Path $InstallDir $relPath
            $displayName = if ($ModNamesMap.ContainsKey($file.path)) { $ModNamesMap[$file.path] } else { Split-Path $file.path -Leaf }
            $expectedSha1 = $file.hashes.sha1

            # Verify mode: read-only check against what's already on disk - never
            # downloads anything. Reports exactly what's missing or corrupt so the
            # player (or a "Repair" follow-up run) knows precisely what needs fixing,
            # without redownloading the whole pack to find out.
            if ($VerifyOnly) {
                if (-not (Test-Path $destPath)) {
                    $sync.MissingCount++
                    Log "[$i/$total] MISSING: $displayName"
                } else {
                    $actualSha1 = (Get-FileHash -Path $destPath -Algorithm SHA1).Hash.ToLower()
                    if ($expectedSha1 -and $actualSha1 -ne $expectedSha1) {
                        $sync.CorruptCount++
                        Log "[$i/$total] CORRUPT (hash mismatch): $displayName"
                    } else {
                        $sync.OkCount++
                        Log "[$i/$total] OK: $displayName"
                    }
                }
                SetProgress (15 + [math]::Floor((80.0 * $i / [math]::Max($total,1))))
                continue
            }

            $destDir = Split-Path -Parent $destPath
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

            $needsDownload = $true
            if (Test-Path $destPath) {
                $actualSha1 = (Get-FileHash -Path $destPath -Algorithm SHA1).Hash.ToLower()
                if ($actualSha1 -eq $expectedSha1) { $needsDownload = $false }
            }

            if ($needsDownload) {
                $attempt = 0
                $ok = $false
                while ($attempt -lt 3 -and -not $ok -and -not $sync.Cancel) {
                    $attempt++
                    $err = Download-WithProgress $file.downloads[0] $destPath $displayName
                    if (-not $err -and (Test-Path $destPath)) {
                        $actualSha1 = (Get-FileHash -Path $destPath -Algorithm SHA1).Hash.ToLower()
                        if (-not $expectedSha1 -or $actualSha1 -eq $expectedSha1) {
                            $ok = $true
                            $sync.OkCount++
                            Log "[$i/$total] downloaded: $displayName"
                        } else {
                            Log "[$i/$total] hash mismatch (attempt $attempt): $displayName"
                        }
                    } else {
                        Log "[$i/$total] retry $attempt failed: $displayName - $err"
                    }
                }
                if (-not $ok -and -not $sync.Cancel) { Log "[X] Giving up on $displayName after 3 attempts."; $sync.FailCount++ }
            } else {
                $sync.SkipCount++
                Log "[$i/$total] already up to date: $displayName"
            }
            SetProgress (15 + [math]::Floor((70.0 * $i / [math]::Max($total,1))))
        }

        if ($sync.Cancel) { $sync.Done = $true; return }

        if ($VerifyOnly) {
            SetProgress 100
            SetStatus "Verification complete."
            Log ""
            Log "=== Verify complete: $($sync.OkCount) OK, $($sync.MissingCount) missing, $($sync.CorruptCount) corrupt ==="
            $sync.Done = $true
            return
        }

        SetStatus "Copying bundled mods, configs and datapacks..."
        $overridesDir = Join-Path $extractDir "overrides"
        if (Test-Path $overridesDir) {
            Copy-Item -Path (Join-Path $overridesDir "*") -Destination $InstallDir -Recurse -Force
            Log "[OK] Overrides copied (extracted straight from the .mrpack, no manual paste needed)."
        }
        SetProgress 90

        if ($UseOfficial) {
            SetStatus "Registering launcher profile..."
            $profilesFile = Join-Path $DotMinecraft "launcher_profiles.json"
            $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            $profilesJson = $null
            if (Test-Path $profilesFile) {
                try {
                    $profilesJson = Get-Content $profilesFile -Raw | ConvertFrom-Json
                    Copy-Item $profilesFile "$profilesFile.bak" -Force
                } catch {
                    Log "[!] launcher_profiles.json was unreadable, backing it up and starting fresh."
                    if (Test-Path $profilesFile) { Copy-Item $profilesFile "$profilesFile.corrupt.bak" -Force }
                }
            }
            if (-not $profilesJson) {
                $profilesJson = [PSCustomObject]@{ profiles = [PSCustomObject]@{}; settings = [PSCustomObject]@{}; version = 3 }
            }
            if (-not ($profilesJson.PSObject.Properties.Name -contains "profiles")) {
                $profilesJson | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([PSCustomObject]@{})
            }
            $newProfile = [PSCustomObject]@{
                name          = "PGC SMP"
                type          = "custom"
                created       = $now
                lastUsed      = $now
                icon          = "Furnace"
                lastVersionId = $ForgeVersionId
                gameDir       = $InstallDir
                javaArgs      = "-Xmx${RamGB}G -Xms1G"
            }
            $profilesJson.profiles | Add-Member -MemberType NoteProperty -Name "PGC_SMP" -Value $newProfile -Force
            $profilesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $profilesFile -Encoding UTF8
            Log "[OK] 'PGC SMP' profile registered in the Official Launcher ($RamGB GB RAM)."
        } else {
            Log "[OK] Files placed in: $InstallDir"
            Log "     If your launcher needs manual import, point it at this folder."
        }

        SetProgress 100
        SetStatus "Done!"
        Log ""
        Log "=== Installation complete: $($sync.OkCount) downloaded, $($sync.SkipCount) already up to date, $($sync.FailCount) failed ==="
    } catch {
        Log "[X] Fatal error: $($_.Exception.Message)"
        $sync.Failed = $true
    } finally {
        $sync.Done = $true
    }
}

function Start-InstallRun([bool]$VerifyOnly) {
    $selectedMrpack = $txtMrpack.Text
    if ([string]::IsNullOrWhiteSpace($selectedMrpack) -or -not (Test-Path $selectedMrpack)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a valid .mrpack file first (click 'Browse...' next to 'Modpack (.mrpack) file').",
            "PGC SMP Installer", "OK", "Warning") | Out-Null
        return
    }
    if (-not $script:PackIndex) {
        [System.Windows.Forms.MessageBox]::Show(
            "That .mrpack file couldn't be read. Pick a different one before installing.",
            "PGC SMP Installer", "OK", "Warning") | Out-Null
        return
    }

    $btnInstall.Enabled = $false
    $btnVerify.Enabled = $false
    $btnCancel.Enabled = $true
    $comboLaunchers.Enabled = $false
    $btnBrowse.Enabled = $false
    $btnBrowseMrpack.Enabled = $false
    $btnRescan.Enabled = $false
    $btnUninstall.Enabled = $false
    $txtLog.Clear()
    $sync.Log.Clear()
    $sync.Progress = 0
    $sync.Done = $false
    $sync.Failed = $false
    $sync.Cancel = $false
    $sync.OkCount = 0; $sync.FailCount = 0; $sync.SkipCount = 0
    $sync.MissingCount = 0; $sync.CorruptCount = 0

    $selectedName = ($script:DetectedPaths.Keys | Select-Object -Index $comboLaunchers.SelectedIndex)
    $useOfficial = $selectedName -like "Official Minecraft Launcher*"
    $dotMinecraft = $script:DetectedPaths[$selectedName]
    $installDir = $txtPath.Text
    $ramGB = [int]$numRam.Value

    if (-not $VerifyOnly) {
        $Settings.LastInstallPath = $installDir
        $Settings.RamGB = $ramGB
        Save-Settings $Settings
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($installScript).AddArgument($sync).AddArgument($installDir).AddArgument($useOfficial).AddArgument($selectedMrpack).AddArgument($WorkDir).AddArgument($McVersion).AddArgument($ForgeVersion).AddArgument($ForgeFullVersion).AddArgument($ForgeVersionId).AddArgument($dotMinecraft).AddArgument($ramGB).AddArgument($script:ModDisplayNames).AddArgument($VerifyOnly) | Out-Null
    $asyncResult = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({
        while ($sync.Log.Count -gt 0) {
            $line = $sync.Log[0]
            $sync.Log.RemoveAt(0)
            Append-ColorLog $line (Color-ForLine $line)
        }
        $progressBar.Value = [Math]::Min([Math]::Max($sync.Progress,0),100)
        $lblStatus.Text = $sync.Status

        if ($sync.Done) {
            $timer.Stop()
            try { $ps.EndInvoke($asyncResult) | Out-Null } catch { }
            $ps.Dispose()
            $rs.Close()
            $btnInstall.Enabled = $true
            $btnVerify.Enabled = $true
            $btnCancel.Enabled = $false
            $comboLaunchers.Enabled = $true
            $btnBrowse.Enabled = $true
            $btnBrowseMrpack.Enabled = $true
            $btnRescan.Enabled = $true
            $btnUninstall.Enabled = $true
            if (Test-Path $installDir) { $btnOpenFolder.Enabled = $true }

            if ($sync.Cancel) {
                [System.Windows.Forms.MessageBox]::Show("Cancelled.", "PGC SMP Installer", "OK", "Warning") | Out-Null
            } elseif ($VerifyOnly) {
                $needsRepair = ($sync.MissingCount -gt 0 -or $sync.CorruptCount -gt 0)
                $summary = "$($sync.OkCount) file(s) OK, $($sync.MissingCount) missing, $($sync.CorruptCount) corrupt."
                if ($needsRepair) {
                    $choice = [System.Windows.Forms.MessageBox]::Show(
                        "$summary`n`nRepair now? This only re-downloads the missing/corrupt files - everything already OK is left untouched.",
                        "PGC SMP Installer", "YesNo", "Warning")
                    if ($choice -eq "Yes") {
                        Start-InstallRun $false
                    }
                } else {
                    [System.Windows.Forms.MessageBox]::Show("$summary`n`nEverything checks out.", "PGC SMP Installer", "OK", "Information") | Out-Null
                }
            } elseif ($sync.Failed) {
                [System.Windows.Forms.MessageBox]::Show("Installation finished with errors - check the log.", "PGC SMP Installer", "OK", "Warning") | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show("Done! Open your launcher and pick the 'PGC SMP' profile.", "PGC SMP Installer", "OK", "Information") | Out-Null
            }
        }
    })
    $timer.Start()
}

$btnInstall.Add_Click({ Start-InstallRun $false })
$btnVerify.Add_Click({ Start-InstallRun $true })

$btnCancel.Add_Click({
    $sync.Cancel = $true
    $lblStatus.Text = "Cancelling..."
})

$form.Add_FormClosing({
    $Settings.RamGB = [int]$numRam.Value
    Save-Settings $Settings
})

[System.Windows.Forms.Application]::Run($form)
