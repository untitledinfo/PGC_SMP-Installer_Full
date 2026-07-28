PGC SMP - One Click Installer (GUI) v1.2.0
=============================================
Minecraft 1.20.1  |  Forge 47.4.20

BUG FIX IN THIS VERSION
------------------------
Fixed: "Cannot bind argument to parameter 'Path' because it is null."
Cause: the compiled .exe couldn't resolve its own folder location, so the
installer couldn't find PGC_SMP_1_0_0.mrpack next to it. The script now
resolves its folder through $PSScriptRoot with a process-path fallback,
so it works both as a raw .ps1 and as the compiled .exe.

NEW IN THIS VERSION
---------------------
- RAM allocation selector (2-16 GB) written into the launcher profile
- Cancel button - stops an in-progress install cleanly
- Uninstall button - removes the install folder and the launcher profile
- Open Folder button - jumps straight to the installed files
- Save Log button - export the log for troubleshooting/support
- Mod count + total download size shown before you even click Install
- Disk space check before downloading starts, with a warning if it's tight
- Remembers your last install path and RAM choice between runs
- Install summary at the end: downloaded / already up to date / failed counts
- EN / UR language toggle for the interface labels
- Forge installer now runs hidden instead of relying on -NoNewWindow, which
  could misbehave in a console-less compiled .exe

HOW TO INSTALL
--------------
1. Keep these files together in the same folder:
     - Install PGC SMP.bat
     - Install-PGC-SMP-GUI.ps1
     - PGC_SMP_1_0_0.mrpack

2. Double-click "Install PGC SMP.bat".
3. Pick your launcher (auto-detected) and RAM, then click Install.
4. Open the Minecraft Launcher, sign in with your Microsoft account,
   pick "PGC SMP", and click Play.

ACCOUNTS
--------
Supports the Official Launcher (paid/Microsoft account) and legitimate
third-party launchers (Prism, MultiMC, ATLauncher, GDLauncher, Modrinth
App, CurseForge) using their own real sign-in. No offline/cracked mode -
the server requires owned accounts.

REQUIREMENTS
------------
- Windows 10/11 with PowerShell (built in)
- A Minecraft account you own
- Java 17+ for the Official Launcher path (checked automatically)
- Internet connection (mods total roughly 1-2 GB)

TROUBLESHOOTING
----------------
- Forge install step reports an error: run forge-installer.jar manually
  from %TEMP%\PGC_SMP_Install and choose "Install Client".
- A mod keeps failing after 3 retries: check your connection and click
  Install again - it only re-downloads what's missing or mismatched.
- Still stuck: use Save Log and share it in the PGC Discord.
