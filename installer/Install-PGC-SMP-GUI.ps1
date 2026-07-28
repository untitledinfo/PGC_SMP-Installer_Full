<#
    PGC SMP - One-Click Modpack Installer (GUI)  v1.3.0
    ------------------------------------------------------
    Pack   : PGC SMP v1.0.0
    Game   : Minecraft 1.20.1
    Loader : Forge 47.4.20

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
$AppVersion = "1.3.0"

# Set this to "yourname/your-repo" to enable a GitHub-releases self-update
# check on startup. Left blank = feature silently skipped, no network call.
$GithubRepo = ""

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
        $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 8
        foreach ($proj in $resp) { $names[$proj.id] = $proj.title }
    } catch {
        # offline or API down - filenames will be used instead, no big deal
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
# Real, single-source pack summary (real file list, real sizes, real names)
# ---------------------------------------------------------------------------
$PackIndex = $null
$PackSummary = $null
$ModDisplayNames = @{}
if (Test-Path $MrpackFile) {
    try {
        $PackIndex = Get-IndexFromMrpack $MrpackFile
        $totalBytes = ($PackIndex.files | Measure-Object -Property fileSize -Sum).Sum
        $PackSummary = [PSCustomObject]@{
            ModCount = $PackIndex.files.Count
            TotalMB  = [math]::Round($totalBytes / 1MB, 1)
        }
        $projNames = Get-ModrinthNames $PackIndex
        foreach ($f in $PackIndex.files) {
            $friendly = $null
            if ($f.downloads -and $f.downloads[0] -match "cdn\.modrinth\.com/data/([^/]+)/versions/") {
                $pid = $matches[1]
                if ($projNames.ContainsKey($pid)) { $friendly = $projNames[$pid] }
            }
            if (-not $friendly) { $friendly = [System.IO.Path]::GetFileNameWithoutExtension($f.path) }
            $ModDisplayNames[$f.path] = $friendly
        }
    } catch { $PackSummary = $null }
}

# ---------------------------------------------------------------------------
# Optional self-update check (GitHub Releases API) - silent if not configured
# or offline; never blocks the installer.
# ---------------------------------------------------------------------------
$UpdateAvailable = $null
if ($GithubRepo) {
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$GithubRepo/releases/latest" -TimeoutSec 5 -Headers @{ "User-Agent" = "PGC-SMP-Installer" }
        $latestTag = ($rel.tag_name -replace '^v','')
        if ($latestTag -and $latestTag -ne $AppVersion) { $UpdateAvailable = $latestTag }
    } catch { }
}

# ---------------------------------------------------------------------------
# Build the form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "PGC SMP Installer v$AppVersion"
$form.Size = New-Object System.Drawing.Size(620, 700)
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
    $lblSummary.Text = "PGC_SMP_1_0_0.mrpack not found next to this program."
}
$lblSummary.ForeColor = [System.Drawing.Color]::DimGray
$lblSummary.Location = New-Object System.Drawing.Point(15, 42)
$lblSummary.Size = New-Object System.Drawing.Size(580, 20)
$form.Controls.Add($lblSummary)

if ($UpdateAvailable) {
    $lblUpdate = New-Object System.Windows.Forms.Label
    $lblUpdate.Text = "A newer installer version ($UpdateAvailable) is available."
    $lblUpdate.ForeColor = [System.Drawing.Color]::DarkOrange
    $lblUpdate.Location = New-Object System.Drawing.Point(15, 62)
    $lblUpdate.Size = New-Object System.Drawing.Size(580, 18)
    $form.Controls.Add($lblUpdate)
}

$lblLauncher = New-Object System.Windows.Forms.Label
$lblLauncher.Text = T "Launcher"
$lblLauncher.Location = New-Object System.Drawing.Point(15, 85)
$lblLauncher.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($lblLauncher)

$comboLaunchers = New-Object System.Windows.Forms.ComboBox
$comboLaunchers.Location = New-Object System.Drawing.Point(15, 107)
$comboLaunchers.Size = New-Object System.Drawing.Size(480, 24)
$comboLaunchers.DropDownStyle = "DropDownList"
$form.Controls.Add($comboLaunchers)

$btnRescan = New-Object System.Windows.Forms.Button
$btnRescan.Text = "Rescan"
$btnRescan.Location = New-Object System.Drawing.Point(505, 106)
$btnRescan.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnRescan)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = T "Install"
$lblPath.Location = New-Object System.Drawing.Point(15, 141)
$lblPath.Size = New-Object System.Drawing.Size(90, 20)
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(105, 139)
$txtPath.Size = New-Object System.Drawing.Size(390, 24)
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(505, 138)
$btnBrowse.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnBrowse)

$lblRam = New-Object System.Windows.Forms.Label
$lblRam.Text = T "Ram"
$lblRam.Location = New-Object System.Drawing.Point(15, 173)
$lblRam.Size = New-Object System.Drawing.Size(140, 20)
$form.Controls.Add($lblRam)

$numRam = New-Object System.Windows.Forms.NumericUpDown
$numRam.Location = New-Object System.Drawing.Point(160, 171)
$numRam.Size = New-Object System.Drawing.Size(60, 24)
$numRam.Minimum = 2
$numRam.Maximum = 16
$numRam.Value = [Math]::Min([Math]::Max([int]$Settings.RamGB, 2), 16)
$form.Controls.Add($numRam)

$lblMods = New-Object System.Windows.Forms.Label
$lblMods.Text = T "Mods"
$lblMods.Location = New-Object System.Drawing.Point(15, 205)
$lblMods.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($lblMods)

$listMods = New-Object System.Windows.Forms.ListBox
$listMods.Location = New-Object System.Drawing.Point(15, 227)
$listMods.Size = New-Object System.Drawing.Size(575, 90)
if ($PackIndex) {
    foreach ($f in ($PackIndex.files | Sort-Object { $ModDisplayNames[$_.path] })) {
        $listMods.Items.Add($ModDisplayNames[$f.path]) | Out-Null
    }
}
$form.Controls.Add($listMods)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 328)
$progressBar.Size = New-Object System.Drawing.Size(575, 24)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = T "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(15, 356)
$lblStatus.Size = New-Object System.Drawing.Size(575, 20)
$form.Controls.Add($lblStatus)

# Live "console" - colour coded, auto-scrolling
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::Black
$txtLog.ForeColor = [System.Drawing.Color]::Gainsboro
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Location = New-Object System.Drawing.Point(15, 382)
$txtLog.Size = New-Object System.Drawing.Size(575, 200)
$form.Controls.Add($txtLog)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = T "InstallBtn"
$btnInstall.Location = New-Object System.Drawing.Point(15, 592)
$btnInstall.Size = New-Object System.Drawing.Size(120, 34)
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = T "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(145, 592)
$btnCancel.Size = New-Object System.Drawing.Size(100, 34)
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = T "OpenFolder"
$btnOpenFolder.Location = New-Object System.Drawing.Point(255, 592)
$btnOpenFolder.Size = New-Object System.Drawing.Size(110, 34)
$btnOpenFolder.Enabled = $false
$form.Controls.Add($btnOpenFolder)

$btnSaveLog = New-Object System.Windows.Forms.Button
$btnSaveLog.Text = T "SaveLog"
$btnSaveLog.Location = New-Object System.Drawing.Point(375, 592)
$btnSaveLog.Size = New-Object System.Drawing.Size(90, 34)
$form.Controls.Add($btnSaveLog)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = T "Uninstall"
$btnUninstall.Location = New-Object System.Drawing.Point(475, 592)
$btnUninstall.Size = New-Object System.Drawing.Size(115, 34)
$form.Controls.Add($btnUninstall)

if (-not (Test-Path $MrpackFile)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Could not find PGC_SMP_1_0_0.mrpack next to this program.`nKeep the installer and the .mrpack file in the same folder.",
        "PGC SMP Installer", "OK", "Error") | Out-Null
}

function Populate-Launchers {
    $comboLaunchers.Items.Clear()
    $script:DetectedPaths = Get-DetectedPaths
    if ($script:DetectedPaths.Count -eq 0) {
        $comboLaunchers.Items.Add("Official Minecraft Launcher (not found - will create)") | Out-Null
        $script:DetectedPaths["Official Minecraft Launcher (not found - will create)"] = (Join-Path $env:APPDATA ".minecraft")
    } else {
        foreach ($name in $script:DetectedPaths.Keys) {
            $comboLaunchers.Items.Add("$name  ->  $($script:DetectedPaths[$name])") | Out-Null
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
    $btnInstall.Text = T "InstallBtn"
    $btnCancel.Text = T "Cancel"
    $btnOpenFolder.Text = T "OpenFolder"
    $btnSaveLog.Text = T "SaveLog"
    $btnUninstall.Text = T "Uninstall"
    if (-not $sync -or $sync.Status -eq "Idle" -or $sync.Done) { $lblStatus.Text = T "Ready" }
})

$btnRescan.Add_Click({ Populate-Launchers })

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
})

$installScript = {
    param($sync, $InstallDir, $UseOfficial, $MrpackFile, $WorkDir, $McVersion, $ForgeVersion, $ForgeFullVersion, $ForgeVersionId, $DotMinecraft, $RamGB, $ModNamesMap)

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

        if ($UseOfficial) {
            SetStatus "Checking Java..."
            $javaOk = $false
            try {
                $out = & java -version 2>&1 | Out-String
                if ($out -match '"(\d+)') { if ([int]$matches[1] -ge 17) { $javaOk = $true } }
            } catch { }
            if (-not $javaOk) {
                Log "[X] Java 17+ not found. Opening the download page - install Java, then run this installer again."
                Start-Process "https://adoptium.net/temurin/releases/?version=17"
                $sync.Failed = $true; $sync.Done = $true; return
            }
            Log "[OK] Java 17+ found."

            SetStatus "Checking Forge installation..."
            $versionFolder = Join-Path $DotMinecraft "versions\$ForgeVersionId"
            if (Test-Path $versionFolder) {
                Log "[OK] Forge $ForgeVersion already installed."
            } else {
                SetStatus "Downloading Forge installer..."
                $forgeUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$ForgeFullVersion/forge-$ForgeFullVersion-installer.jar"
                $forgeJar = Join-Path $WorkDir "forge-installer.jar"
                $err = Download-WithProgress $forgeUrl $forgeJar "Forge installer"
                if ($err) { Log "[X] Forge installer download failed: $err" }
                else { Log "[OK] Forge installer downloaded." }

                SetStatus "Installing Forge (this can take a minute)..."
                $proc = Start-Process -FilePath "java" -ArgumentList @("-jar", "`"$forgeJar`"", "--installClient", "`"$DotMinecraft`"") -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -ne 0 -or -not (Test-Path $versionFolder)) {
                    Log "[X] Forge install may have failed (exit code $($proc.ExitCode)). Run forge-installer.jar manually from $WorkDir and choose 'Install Client'."
                } else {
                    Log "[OK] Forge $ForgeVersion installed."
                }
            }
        }
        SetProgress 10
        if ($sync.Cancel) { Log "[!] Cancelled."; $sync.Done = $true; return }

        SetStatus "Unpacking modpack overrides..."
        $extractDir = Join-Path $WorkDir "extracted"
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($MrpackFile, $extractDir)
        Log "[OK] Pack read: $($index.files.Count) mods, approx $([math]::Round($neededBytes/1MB,1)) MB."
        SetProgress 15

        $total = $index.files.Count
        $i = 0
        foreach ($file in $index.files) {
            if ($sync.Cancel) { Log "[!] Cancelled by user."; break }
            $i++
            $relPath = $file.path -replace "/", "\"
            $destPath = Join-Path $InstallDir $relPath
            $destDir = Split-Path -Parent $destPath
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

            $displayName = if ($ModNamesMap.ContainsKey($file.path)) { $ModNamesMap[$file.path] } else { Split-Path $file.path -Leaf }
            $expectedSha1 = $file.hashes.sha1
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

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnCancel.Enabled = $true
    $comboLaunchers.Enabled = $false
    $btnBrowse.Enabled = $false
    $btnRescan.Enabled = $false
    $btnUninstall.Enabled = $false
    $txtLog.Clear()
    $sync.Log.Clear()
    $sync.Progress = 0
    $sync.Done = $false
    $sync.Failed = $false
    $sync.Cancel = $false
    $sync.OkCount = 0; $sync.FailCount = 0; $sync.SkipCount = 0

    $selectedName = ($script:DetectedPaths.Keys | Select-Object -Index $comboLaunchers.SelectedIndex)
    $useOfficial = $selectedName -like "Official Minecraft Launcher*"
    $dotMinecraft = $script:DetectedPaths[$selectedName]
    $installDir = $txtPath.Text
    $ramGB = [int]$numRam.Value

    $Settings.LastInstallPath = $installDir
    $Settings.RamGB = $ramGB
    Save-Settings $Settings

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($installScript).AddArgument($sync).AddArgument($installDir).AddArgument($useOfficial).AddArgument($MrpackFile).AddArgument($WorkDir).AddArgument($McVersion).AddArgument($ForgeVersion).AddArgument($ForgeFullVersion).AddArgument($ForgeVersionId).AddArgument($dotMinecraft).AddArgument($ramGB).AddArgument($ModDisplayNames) | Out-Null
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
            $btnCancel.Enabled = $false
            $comboLaunchers.Enabled = $true
            $btnBrowse.Enabled = $true
            $btnRescan.Enabled = $true
            $btnUninstall.Enabled = $true
            if (Test-Path $installDir) { $btnOpenFolder.Enabled = $true }
            if ($sync.Cancel) {
                [System.Windows.Forms.MessageBox]::Show("Installation cancelled.", "PGC SMP Installer", "OK", "Warning") | Out-Null
            } elseif ($sync.Failed) {
                [System.Windows.Forms.MessageBox]::Show("Installation finished with errors - check the log.", "PGC SMP Installer", "OK", "Warning") | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show("Done! Open your launcher and pick the 'PGC SMP' profile.", "PGC SMP Installer", "OK", "Information") | Out-Null
            }
        }
    })
    $timer.Start()
})

$btnCancel.Add_Click({
    $sync.Cancel = $true
    $lblStatus.Text = "Cancelling..."
})

$form.Add_FormClosing({
    $Settings.RamGB = [int]$numRam.Value
    Save-Settings $Settings
})

[System.Windows.Forms.Application]::Run($form)
