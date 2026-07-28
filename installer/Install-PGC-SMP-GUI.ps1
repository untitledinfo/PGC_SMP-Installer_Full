<#
    PGC SMP - One-Click Modpack Installer (GUI)
    ---------------------------------------------
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

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$MrpackFile = Join-Path $ScriptDir "PGC_SMP_1_0_0.mrpack"
$WorkDir    = Join-Path $env:TEMP "PGC_SMP_Install"
$McVersion  = "1.20.1"
$ForgeVersion = "47.4.20"
$ForgeFullVersion = "$McVersion-$ForgeVersion"
$ForgeVersionId = "$McVersion-forge-$ForgeVersion"

# ---------------------------------------------------------------------------
# Auto-detect Minecraft / launcher install paths
# ---------------------------------------------------------------------------
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

    # Also check the registry for a custom Official Launcher install location.
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
# Build the form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "PGC SMP Installer"
$form.Size = New-Object System.Drawing.Size(560, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "PGC SMP  -  Minecraft $McVersion  |  Forge $ForgeVersion"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(15, 15)
$title.Size = New-Object System.Drawing.Size(520, 30)
$form.Controls.Add($title)

$lblLauncher = New-Object System.Windows.Forms.Label
$lblLauncher.Text = "Detected launcher / install folder:"
$lblLauncher.Location = New-Object System.Drawing.Point(15, 55)
$lblLauncher.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($lblLauncher)

$comboLaunchers = New-Object System.Windows.Forms.ComboBox
$comboLaunchers.Location = New-Object System.Drawing.Point(15, 78)
$comboLaunchers.Size = New-Object System.Drawing.Size(420, 24)
$comboLaunchers.DropDownStyle = "DropDownList"
$form.Controls.Add($comboLaunchers)

$btnRescan = New-Object System.Windows.Forms.Button
$btnRescan.Text = "Rescan"
$btnRescan.Location = New-Object System.Drawing.Point(445, 77)
$btnRescan.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnRescan)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Install folder:"
$lblPath.Location = New-Object System.Drawing.Point(15, 112)
$lblPath.Size = New-Object System.Drawing.Size(90, 20)
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(105, 110)
$txtPath.Size = New-Object System.Drawing.Size(330, 24)
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(445, 109)
$btnBrowse.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnBrowse)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 150)
$progressBar.Size = New-Object System.Drawing.Size(515, 24)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready."
$lblStatus.Location = New-Object System.Drawing.Point(15, 178)
$lblStatus.Size = New-Object System.Drawing.Size(515, 20)
$form.Controls.Add($lblStatus)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Location = New-Object System.Drawing.Point(15, 205)
$txtLog.Size = New-Object System.Drawing.Size(515, 210)
$form.Controls.Add($txtLog)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install"
$btnInstall.Location = New-Object System.Drawing.Point(360, 425)
$btnInstall.Size = New-Object System.Drawing.Size(170, 34)
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

if (-not (Test-Path $MrpackFile)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Could not find PGC_SMP_1_0_0.mrpack next to this program.`nKeep the installer and the .mrpack file in the same folder.",
        "PGC SMP Installer", "OK", "Error") | Out-Null
    exit 1
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
    if ($selectedName -like "Official Minecraft Launcher*") {
        $txtPath.Text = Join-Path $basePath "PGC_SMP"
    } else {
        $txtPath.Text = $basePath
    }
})
$comboLaunchers.SelectedIndex = 0

$btnRescan.Add_Click({ Populate-Launchers })

$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Choose the folder to install PGC SMP into"
    if ($fbd.ShowDialog() -eq "OK") { $txtPath.Text = $fbd.SelectedPath }
})

function Append-Log($msg) {
    $txtLog.AppendText("$msg`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
}

function Get-FileSha1($path) {
    if (-not (Test-Path $path)) { return $null }
    return (Get-FileHash -Path $path -Algorithm SHA1).Hash.ToLower()
}

# ---------------------------------------------------------------------------
# Background worker (runspace) so the UI never freezes
# ---------------------------------------------------------------------------
$sync = [hashtable]::Synchronized(@{
    Log      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    Progress = 0
    Status   = "Idle"
    Done     = $false
    Failed   = $false
})

$installScript = {
    param($sync, $InstallDir, $UseOfficial, $MrpackFile, $WorkDir, $McVersion, $ForgeVersion, $ForgeFullVersion, $ForgeVersionId, $DotMinecraft)

    function Log($m)      { $sync.Log.Add($m) | Out-Null }
    function SetProgress($p) { $sync.Progress = [int]$p }
    function SetStatus($s)   { $sync.Status = $s }

    try {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $InstallDir "mods") -Force | Out-Null
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

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
                Invoke-WebRequest -Uri $forgeUrl -OutFile $forgeJar -UseBasicParsing
                Log "[OK] Forge installer downloaded."

                SetStatus "Installing Forge (this can take a minute)..."
                $proc = Start-Process -FilePath "java" -ArgumentList @("-jar", "`"$forgeJar`"", "--installClient", "`"$DotMinecraft`"") -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -ne 0 -or -not (Test-Path $versionFolder)) {
                    Log "[X] Forge install may have failed (exit code $($proc.ExitCode)). You can run forge-installer.jar manually from $WorkDir and choose 'Install Client'."
                } else {
                    Log "[OK] Forge $ForgeVersion installed."
                }
            }
        }
        SetProgress 10

        SetStatus "Unpacking modpack..."
        $extractDir = Join-Path $WorkDir "extracted"
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        $zipCopy = Join-Path $WorkDir "pgc_smp.zip"
        Copy-Item $MrpackFile $zipCopy -Force
        Expand-Archive -Path $zipCopy -DestinationPath $extractDir -Force
        Log "[OK] Modpack unpacked."
        SetProgress 15

        $index = Get-Content (Join-Path $extractDir "modrinth.index.json") -Raw | ConvertFrom-Json
        $total = $index.files.Count
        $i = 0
        SetStatus "Downloading mods (0/$total)..."
        foreach ($file in $index.files) {
            $i++
            $relPath = $file.path -replace "/", "\"
            $destPath = Join-Path $InstallDir $relPath
            $destDir = Split-Path -Parent $destPath
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

            $expectedSha1 = $file.hashes.sha1
            $needsDownload = $true
            if (Test-Path $destPath) {
                $actualSha1 = (Get-FileHash -Path $destPath -Algorithm SHA1).Hash.ToLower()
                if ($actualSha1 -eq $expectedSha1) { $needsDownload = $false }
            }

            if ($needsDownload) {
                $attempt = 0
                $ok = $false
                while ($attempt -lt 3 -and -not $ok) {
                    $attempt++
                    try {
                        Invoke-WebRequest -Uri $file.downloads[0] -OutFile $destPath -UseBasicParsing
                        $actualSha1 = (Get-FileHash -Path $destPath -Algorithm SHA1).Hash.ToLower()
                        if (-not $expectedSha1 -or $actualSha1 -eq $expectedSha1) {
                            $ok = $true
                            Log "[$i/$total] downloaded: $($file.path)"
                        } else {
                            Log "[$i/$total] hash mismatch (attempt $attempt): $($file.path)"
                        }
                    } catch {
                        Log "[$i/$total] retry $attempt failed: $($file.path) - $($_.Exception.Message)"
                    }
                }
                if (-not $ok) { Log "[X] Giving up on $($file.path) after 3 attempts." }
            } else {
                Log "[$i/$total] already up to date: $($file.path)"
            }
            SetStatus "Downloading mods ($i/$total)..."
            SetProgress (15 + [math]::Floor((70.0 * $i / [math]::Max($total,1))))
        }

        SetStatus "Copying bundled mods, configs and datapacks..."
        $overridesDir = Join-Path $extractDir "overrides"
        if (Test-Path $overridesDir) {
            Copy-Item -Path (Join-Path $overridesDir "*") -Destination $InstallDir -Recurse -Force
            Log "[OK] Overrides copied."
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
                javaArgs      = "-Xmx4G -Xms2G"
            }
            $profilesJson.profiles | Add-Member -MemberType NoteProperty -Name "PGC_SMP" -Value $newProfile -Force
            $profilesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $profilesFile -Encoding UTF8
            Log "[OK] 'PGC SMP' profile registered in the Official Launcher."
        } else {
            Log "[OK] Files placed in: $InstallDir"
            Log "     If your launcher needs manual import, point it at this folder."
        }

        SetProgress 100
        SetStatus "Done!"
        Log ""
        Log "=== Installation complete ==="
    } catch {
        Log "[X] Fatal error: $($_.Exception.Message)"
        $sync.Failed = $true
    } finally {
        $sync.Done = $true
    }
}

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $comboLaunchers.Enabled = $false
    $btnBrowse.Enabled = $false
    $btnRescan.Enabled = $false
    $txtLog.Clear()
    $sync.Log.Clear()
    $sync.Progress = 0
    $sync.Done = $false
    $sync.Failed = $false

    $selectedName = ($script:DetectedPaths.Keys | Select-Object -Index $comboLaunchers.SelectedIndex)
    $useOfficial = $selectedName -like "Official Minecraft Launcher*"
    $dotMinecraft = $script:DetectedPaths[$selectedName]
    $installDir = $txtPath.Text

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($installScript).AddArgument($sync).AddArgument($installDir).AddArgument($useOfficial).AddArgument($MrpackFile).AddArgument($WorkDir).AddArgument($McVersion).AddArgument($ForgeVersion).AddArgument($ForgeFullVersion).AddArgument($ForgeVersionId).AddArgument($dotMinecraft) | Out-Null
    $asyncResult = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        while ($sync.Log.Count -gt 0) {
            $line = $sync.Log[0]
            $sync.Log.RemoveAt(0)
            Append-Log $line
        }
        $progressBar.Value = [Math]::Min([Math]::Max($sync.Progress,0),100)
        $lblStatus.Text = $sync.Status

        if ($sync.Done) {
            $timer.Stop()
            $ps.EndInvoke($asyncResult) | Out-Null
            $ps.Dispose()
            $rs.Close()
            $btnInstall.Enabled = $true
            $comboLaunchers.Enabled = $true
            $btnBrowse.Enabled = $true
            $btnRescan.Enabled = $true
            if ($sync.Failed) {
                [System.Windows.Forms.MessageBox]::Show("Installation finished with errors - check the log.", "PGC SMP Installer", "OK", "Warning") | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show("Done! Open your launcher and pick the 'PGC SMP' profile.", "PGC SMP Installer", "OK", "Information") | Out-Null
            }
        }
    })
    $timer.Start()
})

[System.Windows.Forms.Application]::Run($form)
