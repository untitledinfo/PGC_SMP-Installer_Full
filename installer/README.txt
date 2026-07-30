PGC SMP - One Click Installer (GUI) v1.3.0
=============================================
Minecraft 1.20.1  |  Forge 47.4.20

WHAT CHANGED IN THIS VERSION
------------------------------
- Removed the old "preview" step that extracted the whole pack to a temp
  folder just to count mods. It now reads modrinth.index.json straight out
  of the .mrpack zip in memory - faster, and always reflects the real file,
  never a stale leftover extraction.
- Live console: the log is now colour-coded (green = success, red = failed,
  yellow = warning) and the status line updates in real time per file -
  percent complete, MB downloaded / total, and current speed - instead of
  only showing a line once a file finishes.
- Modrinth API integration: mod names shown in the log and in the new
  "Mods included" list are the real project titles from Modrinth
  (api.modrinth.com), not raw jar filenames. Falls back to filenames
  automatically if you're offline when the app starts - never blocks
  the installer.
- Optional GitHub self-update check: if you set $GithubRepo near the top
  of Install-PGC-SMP-GUI.ps1 to "yourname/yourrepo", the app checks your
  latest GitHub Release on startup and shows a banner if a newer version
  exists. Left blank by default - no network call, no dependency on you
  having a repo.
- Mods included list box so players can see exactly what's in the pack
  before clicking Install.
- Overrides (bundled mods/configs/datapacks) are extracted and copied
  automatically - no manual paste required, same as before, just faster.

CARRIED OVER FROM v1.2.0
--------------------------
- RAM allocation selector, Cancel, Uninstall, Open Folder, Save Log
- Disk space check, SHA-1 verification with 3 retries, skip-if-current
- EN / UR language toggle, remembers last install path + RAM
- Fixed exe path-resolution crash from the console version

HOW TO INSTALL
--------------
1. Keep these files together in the same folder:
     - Install PGC SMP.bat
     - Install-PGC-SMP-GUI.ps1
     - PGC_SMP_1_0_0.mrpack

2. Double-click "Install PGC SMP.bat".
3. Check the mod list, pick your launcher (auto-detected) and RAM.
4. Click Install and watch the live log.
5. Open the Minecraft Launcher, sign in, pick "PGC SMP", click Play.

ACCOUNTS
--------
Supports the Official Launcher (paid/Microsoft account) and legitimate
third-party launchers using their own real sign-in. No offline/cracked
mode - the server requires owned accounts.

REQUIREMENTS
------------
- Windows 10/11 with PowerShell (built in)
- A Minecraft account you own
- Java 17+ for the Official Launcher path (checked automatically)
- Internet connection (mods total roughly 1-2 GB; Modrinth API name
  lookup needs internet too, but skips itself gracefully if offline)

TROUBLESHOOTING
----------------
- Forge install step reports an error: run forge-installer.jar manually
  from %TEMP%\PGC_SMP_Install and choose "Install Client".
- A mod keeps failing after 3 retries: check your connection and click
  Install again - it only re-downloads what's missing or mismatched.
- Still stuck: use Save Log and share it in the PGC Discord.

------------------------------------------------------------
v1.5.0 update: modpack fixes + faster installs
------------------------------------------------------------
- Fixed: the installer used to hardcode Minecraft 1.20.1 /
  Forge 47.4.20 no matter which .mrpack was loaded, so picking
  a different pack via "Select .mrpack..." could try to install
  the wrong Forge version. It now reads the real Minecraft +
  loader version straight out of each pack's own
  modrinth.index.json every time a pack is loaded or selected.
- Added: NeoForge packs are now auto-installed the same way
  Forge packs are. Fabric/Quilt packs aren't auto-installed yet
  (no loader-installer step for those loaders) - the installer
  says so clearly, still downloads all mods/configs/overrides,
  and skips creating a broken launcher profile until you add
  the loader yourself.
- Faster: mods now download up to 6 at a time instead of one at
  a time, using the same retry + SHA1 verification as before.
  On a typical pack this cuts total download time significantly
  versus sequential downloads.
