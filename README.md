<div align="center">

# ⚡ WinOpt Suite

### The all-in-one Windows optimizer that asks before it touches anything.

**Clean • Tune • Game • Monitor — with a backup behind every change.**

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D4?style=for-the-badge&logo=windows)
![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Languages](https://img.shields.io/badge/languages-EN%20%7C%20TR%20%7C%20中文%20%7C%20العربية-8A2BE2?style=for-the-badge)
![Dependencies](https://img.shields.io/badge/dependencies-none-success?style=for-the-badge)

*Developed by **Leone***

</div>

---

## 🌍 Pick your language on launch

Start the app and choose **English · Türkçe · 中文 · العربية**. The whole interface switches instantly, and your choice is remembered for next time.

> 🤖 **Note:** The translations were generated with AI and may contain mistakes. Corrections are welcome.

## ✨ What's inside

| Tab | What it does |
|---|---|
| 🚀 **Startup** | See every startup app (registry, folders, scheduled tasks), its publisher and boot impact. Disable what you don't need. |
| 📊 **Processes & RAM** | Live CPU/RAM view, heavy-process hints, safe "close these apps" suggestions. Nothing is killed without your OK. |
| 🛠️ **Services** | Review and change service start types, with protected system services locked out. |
| 🧹 **Deep Clean** | Scan temp files, caches, logs, shader caches, old update leftovers and more. Review the biggest files before anything is deleted. |
| 🌐 **Browsers** | Clean Chrome / Edge / Firefox data safely. Cookies and history are backed up first, and open browsers are never touched. |
| 🗂️ **Registry** | Find broken app paths and leftover entries. `.reg` backups are taken before removal. |
| 🪟 **Windows Tweaks** | Visual effects, animations, privacy and power settings, each with a clear "expected effect" and a one-click undo. |
| 🎮 **Gaming** | Per-game profiles, Game Mode control, power plans and live CPU/GPU/RAM tracking while you play. |
| 🩺 **System Health** | Disk health, hardware info, DISM repair and a read-only disk check. |
| 🧠 **Smart Optimization** | Analyzes your PC, then proposes a plan (Safe / Balanced / FPS-focused). You review it, confirm it, and can roll it back. |
| 📝 **Reports** | Before/after resource measurements, session reports and a full change history. |
| ⏰ **Auto Maintenance** | Schedule cleanups through Windows Task Scheduler, only on the categories *you* pick and only when the PC is idle. |
| 🎨 **Themes** | Light and dark looks to match your setup. |

## 🛡️ Safety first (the whole point)

- **Nothing happens without your confirmation.** Every apply step shows you what will change.
- **Backups before changes.** Settings, registry keys, power plans and browser data are saved first, and a restore point can be created in one click.
- **Undo everywhere.** Smart Optimization, tweaks and power plans can be reverted.
- **No snake oil.** WinOpt never promises FPS gains or "% faster" numbers. It measures real resource usage and tells you honestly what changed.
- **Protected items stay protected.** Critical Windows processes, services and system files are off-limits.

## 🚀 Quick start

1. Download or clone this repo.
2. Double-click **`Baslat.bat`** and accept the admin prompt.
3. Pick your language and start optimizing.

```powershell
# or from PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\WinOptSuite.ps1
```

**Requirements:** Windows 10/11 and the built-in Windows PowerShell 5.1. No installs, no extra dependencies.

## 📦 Build a single file / EXE

```powershell
.\Build.ps1
```

This merges everything into `dist\WinOptSuite-tek-dosya.ps1`. If [`ps2exe`](https://github.com/MScholtes/PS2EXE) is installed (`Install-Module ps2exe`), it also produces `dist\WinOptSuite.exe`.

## 🗺️ Project layout

```
WinOptSuite.ps1   # entry point
Baslat.bat        # one-click launcher
Build.ps1         # single-file / EXE builder
src/              # one module per tab (Cleaner, Gaming, Services, Registry, ...)
src/Lang.ps1      # language picker + EN/TR/ZH/AR translation layer
```

## 🌐 Adding or fixing a translation

All translations live in the table at the bottom of `src/Lang.ps1` (`key → EN / ZH / AR`, tab-separated). Since they are AI-generated, fixes are very welcome. Fix a line, open a PR. 🙌

## ⚠️ Disclaimer

WinOpt Suite changes system settings. It is designed to be careful and reversible, but use it at your own risk, and create a restore point first if you're unsure.

---

<div align="center">

⭐ If you like it, leave a star!

</div>
