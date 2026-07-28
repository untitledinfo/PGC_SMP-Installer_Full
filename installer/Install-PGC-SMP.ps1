<#
    PGC SMP - One-Click Modpack Installer
    --------------------------------------
    Pack   : PGC SMP v1.0.0
    Game   : Minecraft 1.20.1
    Loader : Forge 47.4.20

    What this script does:
      1. Looks for a Minecraft launcher on this PC (Official Launcher, Modrinth App,
         Prism Launcher, MultiMC, ATLauncher, GDLauncher, CurseForge App).
      2. For the Official Minecraft Launcher (the one that needs your paid/Microsoft
         account) it will:
           - Check/prompt for Java 17+
           - Silently install Forge 47.4.20 for Minecraft 1.20.1
           - Create a separate game folder so it never touches your normal saves/mods
           - Copy every mod + config + datapack from the pack into that folder
           - Register a ready-to-click "PGC SMP" profile in the launcher
      3. For launchers that can import .mrpack files natively (Modrinth App, Prism
         Launcher, MultiMC, ATLauncher, GDLauncher) it detects them and tells you
         the exact button to press, since re-implementing their importers would be
         redundant and more fragile than the tool they already ship with.

    Requires: Windows + PowerShell 5.1+ (comes with Windows 10/11).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$MrpackFile = Join-Path $ScriptDir "PGC_SMP_1_0_0.mrpack"
$WorkDir    = Join-Path $env:TEMP "PGC_SMP_Install"
$McVersion  = "1.20.1"
$ForgeVersion = "47.4.20"
$ForgeFullVersion = "$McVersion-$ForgeVersion"
$ForgeVersionId = "$McVersion-forge-$ForgeVersion"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}
function Write-Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "    [X]  $msg" -ForegroundColor Red }

Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "   PGC SMP - One Click Installer" -ForegroundColor Magenta
Write-Host "   Minecraft $McVersion  |  Forge $ForgeVersion" -ForegroundColor Magenta
Write-Host "=======================================" -ForegroundColor Magenta

if (-not (Test-Path $MrpackFile)) {
    Write-Err "Could not find PGC_SMP_1_0_0.mrpack next to this script."
    Write-Err "Keep Install-PGC-SMP.ps1 and the .mrpack file in the SAME folder."
    Read-Host "Press Enter to exit"
    exit 1
}

# ---------------------------------------------------------------------------
# STEP 1 - Detect installed launchers
# ---------------------------------------------------------------------------
Write-Step "Scanning this PC for Minecraft launchers..."

$Launchers = @{
    "Official Minecraft Launcher" = Join-Path $env:APPDATA ".minecraft"
    "Modrinth App"                = Join-Path $env:APPDATA "com.modrinth.theseus"
    "Prism Launcher"              = Join-Path $env:APPDATA "PrismLauncher"
    "MultiMC"                     = Join-Path $env:APPDATA "MultiMC"
    "ATLauncher"                  = Join-Path $env:APPDATA "ATLauncher"
    "GDLauncher"                  = Join-Path $env:APPDATA "gdlauncher_next"
    "CurseForge App"              = Join-Path $env:USERPROFILE "curseforge\minecraft"
}

$Found = @{}
foreach ($name in $Launchers.Keys) {
    $path = $Launchers[$name]
    if (Test-Path $path) {
        $Found[$name] = $path
        Write-Ok "$name -> $path"
    }
}

if ($Found.Count -eq 0) {
    Write-Warn "No launcher folders found. I'll set up the Official Minecraft Launcher"
    Write-Warn "profile anyway - it will appear the first time you open the launcher."
    $Found["Official Minecraft Launcher"] = Join-Path $env:APPDATA ".minecraft"
}

# Native .mrpack importers - just point the user at the right button instead of
# re-implementing each app's own (proprietary) import logic.
$NativeImporters = @("Modrinth App", "Prism Launcher", "MultiMC", "ATLauncher", "GDLauncher")
foreach ($name in $NativeImporters) {
    if ($Found.ContainsKey($name)) {
        Write-Host ""
        Write-Host "    $name supports importing .mrpack files directly:" -ForegroundColor Yellow
        Write-Host "      Open $name -> Add Instance / Import -> select PGC_SMP_1_0_0.mrpack" -ForegroundColor Yellow
    }
}
if ($Found.ContainsKey("CurseForge App")) {
    Write-Host ""
    Write-Host "    CurseForge App detected - use 'Import Profile' and point it at" -ForegroundColor Yellow
    Write-Host "    PGC_SMP_1_0_0.mrpack, or use the Official Launcher setup below." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# STEP 2 - Full automatic setup for the Official Minecraft Launcher
#          (this is the one that needs your paid Microsoft account, and the
#          one with no built-in .mrpack support, so it's the one worth
#          automating end to end)
# ---------------------------------------------------------------------------
Write-Step "Setting up the Official Minecraft Launcher profile..."

$DotMinecraft = $Found["Official Minecraft Launcher"]
if (-not (Test-Path $DotMinecraft)) {
    New-Item -ItemType Directory -Path $DotMinecraft -Force | Out-Null
}
$InstanceDir = Join-Path $DotMinecraft "PGC_SMP"
New-Item -ItemType Directory -Path $InstanceDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstanceDir "mods") -Force | Out-Null

# --- Check Java ---
Write-Step "Checking for Java 17+ (required by Minecraft $McVersion / Forge)..."
$javaOk = $false
try {
    $javaVersionOutput = & java -version 2>&1 | Out-String
    if ($javaVersionOutput -match '"(\d+)') {
        $major = [int]$matches[1]
        if ($major -ge 17) { $javaOk = $true }
    }
} catch { }

if ($javaOk) {
    Write-Ok "Java 17+ found."
} else {
    Write-Warn "Java 17+ was not found on this PC."
    Write-Warn "Forge 1.20.1 needs Java 17+ to install and to run."
    Write-Warn "Opening the Adoptium download page for you - please install it,"
    Write-Warn "then re-run this installer."
    Start-Process "https://adoptium.net/temurin/releases/?version=17"
    Read-Host "Press Enter to exit"
    exit 1
}

# --- Download & silently run the Forge installer ---
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$ForgeInstallerUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$ForgeFullVersion/forge-$ForgeFullVersion-installer.jar"
$ForgeInstallerJar = Join-Path $WorkDir "forge-installer.jar"

$versionFolder = Join-Path $DotMinecraft "versions\$ForgeVersionId"
if (Test-Path $versionFolder) {
    Write-Ok "Forge $ForgeVersion for Minecraft $McVersion is already installed."
} else {
    Write-Step "Downloading Forge $ForgeVersion installer..."
    Invoke-WebRequest -Uri $ForgeInstallerUrl -OutFile $ForgeInstallerJar -UseBasicParsing
    Write-Ok "Downloaded."

    Write-Step "Installing Forge into your Minecraft launcher (this can take a minute)..."
    $proc = Start-Process -FilePath "java" -ArgumentList @("-jar", "`"$ForgeInstallerJar`"", "--installClient", "`"$DotMinecraft`"") -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Err "Forge installer exited with an error (code $($proc.ExitCode))."
        Write-Err "You can also just double-click forge-installer.jar in $WorkDir and choose 'Install Client'."
    } else {
        Write-Ok "Forge installed."
    }
}

# --- Extract the mrpack and copy mods/overrides into the instance ---
Write-Step "Unpacking PGC_SMP_1_0_0.mrpack..."
$ExtractDir = Join-Path $WorkDir "extracted"
if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
$ZipCopy = Join-Path $WorkDir "pgc_smp.zip"
Copy-Item $MrpackFile $ZipCopy -Force
Expand-Archive -Path $ZipCopy -DestinationPath $ExtractDir -Force
Write-Ok "Unpacked."

Write-Step "Downloading mods listed in the pack..."
$Index = Get-Content (Join-Path $ExtractDir "modrinth.index.json") -Raw | ConvertFrom-Json
$total = $Index.files.Count
$i = 0
foreach ($file in $Index.files) {
    $i++
    $relPath = $file.path -replace "/", "\"
    $destPath = Join-Path $InstanceDir $relPath
    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    if (Test-Path $destPath) {
        Write-Host "    [$i/$total] already present: $($file.path)" -ForegroundColor DarkGray
        continue
    }

    $url = $file.downloads[0]
    try {
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
        Write-Host "    [$i/$total] downloaded: $($file.path)" -ForegroundColor DarkGray
    } catch {
        Write-Warn "Failed to download $($file.path) - $($_.Exception.Message)"
    }
}
Write-Ok "All pack files downloaded."

Write-Step "Copying bundled mods, configs and datapacks..."
$OverridesDir = Join-Path $ExtractDir "overrides"
if (Test-Path $OverridesDir) {
    Copy-Item -Path (Join-Path $OverridesDir "*") -Destination $InstanceDir -Recurse -Force
    Write-Ok "Overrides copied."
}

# ---------------------------------------------------------------------------
# STEP 3 - Register the profile in the Official Launcher
# ---------------------------------------------------------------------------
Write-Step "Registering the 'PGC SMP' profile in your Minecraft Launcher..."

$ProfilesFile = Join-Path $DotMinecraft "launcher_profiles.json"
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

if (Test-Path $ProfilesFile) {
    $profilesJson = Get-Content $ProfilesFile -Raw | ConvertFrom-Json
} else {
    $profilesJson = [PSCustomObject]@{
        profiles = [PSCustomObject]@{}
        settings = [PSCustomObject]@{}
        version  = 3
    }
}

if (-not ($profilesJson.PSObject.Properties.Name -contains "profiles")) {
    $profilesJson | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([PSCustomObject]@{})
}

$newProfile = [PSCustomObject]@{
    name         = "PGC SMP"
    type         = "custom"
    created      = $now
    lastUsed     = $now
    icon         = "Furnace"
    lastVersionId = $ForgeVersionId
    gameDir      = $InstanceDir
    javaArgs     = "-Xmx4G -Xms2G"
}

if ($profilesJson.profiles.PSObject.Properties.Name -contains "PGC_SMP") {
    $profilesJson.profiles.PSObject.Properties.Remove("PGC_SMP")
}
$profilesJson.profiles | Add-Member -MemberType NoteProperty -Name "PGC_SMP" -Value $newProfile -Force

$profilesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $ProfilesFile -Encoding UTF8
Write-Ok "Profile 'PGC SMP' added to the Official Minecraft Launcher."

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "   Done!" -ForegroundColor Magenta
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "1. Open the Minecraft Launcher and sign in with your paid Microsoft account."
Write-Host "2. Select the 'PGC SMP' profile from the profile dropdown."
Write-Host "3. Click Play. Minecraft will start with the full modpack installed."
Write-Host ""
Write-Host "Install folder: $InstanceDir"
Write-Host ""
Read-Host "Press Enter to close"
