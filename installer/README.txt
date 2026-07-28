PGC SMP - One Click Installer
==============================
Minecraft 1.20.1  |  Forge 47.4.20

HOW TO INSTALL
--------------
1. Make sure these 3 files stay together in the same folder:
     - Install PGC SMP.bat
     - Install-PGC-SMP.ps1
     - PGC_SMP_1_0_0.mrpack

2. Double-click "Install PGC SMP.bat".
   (Windows may show a blue "Windows protected your PC" popup the first time
   you run a script from an unknown publisher - click "More info" then
   "Run anyway". This is normal for any personal script, not just this one.)

3. Wait for it to finish - it downloads ~80 mods, so it can take a few
   minutes depending on your internet speed.

4. Open the Minecraft Launcher, sign in with your PAID Microsoft account,
   pick the "PGC SMP" profile from the dropdown at the bottom, and click Play.

WHAT THE INSTALLER DOES
------------------------
- Detects your Minecraft launcher folder automatically (no manual paths).
- Installs Forge 47.4.20 for Minecraft 1.20.1.
- Creates a separate "PGC_SMP" game folder so your normal worlds/mods are
  never touched or overwritten.
- Downloads every mod in the pack and copies the bundled configs/datapacks.
- Adds a ready-to-click "PGC SMP" profile to the Official Minecraft Launcher.

REQUIREMENTS
------------
- Windows 10/11 with PowerShell (built in).
- A PAID/premium Minecraft (Microsoft) account - the Official Launcher will
  not let a non-premium account join online-mode servers.
- Java 17+ (the installer checks for this and will open the download page
  for you if it's missing - install it, then run the installer again).
- A working internet connection (mods are ~1-2 GB total).

OTHER LAUNCHERS (Prism Launcher / MultiMC / ATLauncher / GDLauncher / Modrinth App)
------------------------------------------------------------------------------------
These launchers can import the .mrpack file directly - no script needed:
  Open the launcher -> "Add Instance" / "Import" -> select PGC_SMP_1_0_0.mrpack
The installer will tell you if it detects one of these already on your PC.

CURSEFORGE APP
---------------
CurseForge's own importer expects a CurseForge-format pack, so results can
vary with a Modrinth pack. If "Import Profile" doesn't work for you, run
the Official Launcher installer above instead - it's fully supported.

TROUBLESHOOTING
----------------
- "Forge installer exited with an error": open forge-installer.jar manually
  from your Temp\PGC_SMP_Install folder and choose "Install Client".
- A specific mod failed to download: just re-run the installer, it skips
  files that are already there and only retries the missing ones.
- Still stuck: ask in the PGC Discord with the exact error message shown.
