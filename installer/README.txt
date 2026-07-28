PGC SMP - One Click Installer (GUI)
======================================
Minecraft 1.20.1  |  Forge 47.4.20

HOW TO INSTALL
--------------
1. Keep these files together in the same folder:
     - Install PGC SMP.bat
     - Install-PGC-SMP-GUI.ps1
     - PGC_SMP_1_0_0.mrpack

2. Double-click "Install PGC SMP.bat" - a window opens.
   (Windows may show a blue "Windows protected your PC" popup the first
   time you run a script from an unknown publisher - click "More info"
   then "Run anyway". Normal for any unsigned script.)

3. The app auto-detects any Minecraft launcher already on your PC and
   pre-fills the install folder. You can pick a different detected
   launcher from the dropdown, or click "Browse..." to choose your own
   folder. Click Rescan any time.

4. Click "Install" and watch the log + progress bar. It downloads ~80
   mods (verified against checksums) and copies configs/datapacks in.

5. Open the Minecraft Launcher, sign in with your Microsoft account
   (must own Minecraft - see note below), pick "PGC SMP" from the
   profile dropdown, and click Play.

ACCOUNTS
--------
This installer sets up the Official Minecraft Launcher and legitimate
third-party launchers (Prism, MultiMC, ATLauncher, GDLauncher, Modrinth
App, CurseForge). All of these need a Minecraft account you actually
own - there's no offline/cracked-account mode, since the PGC server
requires real, owned accounts.

WHAT'S NEW IN THIS VERSION
---------------------------
- Real GUI: dropdown launcher picker, progress bar, live log, browse button
- Wider auto-detection: registry-based custom install paths, common
  alternate drive locations, all major legitimate launchers
- SHA-1 checksum verification on every downloaded mod, with automatic
  retry (3 attempts) for anything that fails or doesn't match
- Skips files that are already correctly installed - safe to re-run
- Background install worker so the window never freezes
- Backs up your existing launcher_profiles.json before editing it
- Fixed the profile-registration bug from the previous console version

REQUIREMENTS
------------
- Windows 10/11 with PowerShell (built in)
- A Minecraft account you own, signed into your chosen launcher
- Java 17+ for the Official Launcher path (installer checks and opens
  the download page for you if missing)
- Internet connection (mods total roughly 1-2 GB)

OTHER LAUNCHERS
----------------
Prism Launcher, MultiMC, ATLauncher, GDLauncher and the Modrinth App can
all import the .mrpack file directly via their own "Add Instance /
Import" button - the GUI tells you when it detects one of these and you
can pick it from the dropdown to have this installer place the files
for you instead, if you'd rather not use their importer.

TROUBLESHOOTING
----------------
- Forge install step reports an error: run forge-installer.jar manually
  from %TEMP%\PGC_SMP_Install and choose "Install Client".
- A mod keeps failing after 3 retries: check your connection and click
  Install again - it only re-downloads what's missing or mismatched.
- Still stuck: ask in the PGC Discord with the exact log line shown.
