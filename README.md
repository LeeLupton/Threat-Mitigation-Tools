# Threat-Mitigation-Tools
[![PowerShell](https://img.shields.io/badge/PowerShell-0078D7?style=for-the-badge&logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)

Tools I made for everyday protection, mitigation, prevention, and determent.

## Clear-Edge-Cache.ps1
A **desktop-shortcut-first** PowerShell script for Microsoft Edge that quickly clears caches, offers deeper cleaning modes, and includes incident-response backup/restore.

---

## 1) Clone the repo
```powershell
git clone https://github.com/<your-username>/Threat-Mitigation-Tools.git
cd Threat-Mitigation-Tools
````

> For consistency, clone or move the folder to:
> `C:\Threat-Mitigation-Tools\`

## 2) Run the shortcut generator

Use the included helper script `Create-Shortcuts.ps1` to automatically generate Desktop shortcuts for all cleaning modes:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Threat-Mitigation-Tools\Create-Shortcuts.ps1"
```

This creates the following shortcuts on your Desktop:

* **Edge Clean — Default**
* **Edge Clean — Moderate**
* **Edge Clean — Aggressive**
* **Edge Clean — IR (Incident Response)**
* **Edge Clean — Restore Backup**

Each shortcut points to `Clear-Edge-Cache.ps1` with the correct parameters and uses the `icons\broom.ico` icon.

---

## Manual shortcut creation (optional)

If you prefer to create shortcuts manually:

1. Right-click Desktop → **New → Shortcut**.
2. Use one of the commands below as the shortcut **location**.
3. Name the shortcut accordingly.
4. Click **Change Icon…** → browse to `C:\Threat-Mitigation-Tools\icons\broom.ico`.

### Shortcut targets

* **Default (safe caches only)**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Threat-Mitigation-Tools\Clear-Edge-Cache.ps1"
```

* **Moderate**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Threat-Mitigation-Tools\Clear-Edge-Cache.ps1" -Moderate
```

* **Aggressive**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Threat-Mitigation-Tools\Clear-Edge-Cache.ps1" -Aggressive
```

* **Incident Response**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Threat-Mitigation-Tools\Clear-Edge-Cache.ps1" -IncidentResponse -Force
```

* **Restore latest backup**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Threat-Mitigation-Tools\Clear-Edge-Cache.ps1" -RestoreBackup
```

* **Restore specific backup**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Threat-Mitigation-Tools\Clear-Edge-Cache.ps1" -RestoreBackup -RestoreBackupPath "C:\Users\Lee\EdgeIR_Backups\EdgeUserData-20250816-010203.zip"
```

---

## What each mode does

* **Default** → Clears HTTP, code, GPU/shader, and service worker caches.
* **Moderate** → Default + IndexedDB, CacheStorage, File System, WebSQL. (Keeps Local/Session Storage.)
* **Aggressive** → Moderate + Local/Session Storage + Service Worker registrations. (May log you out.)
* **IncidentResponse** →

  * Creates a **full backup** in `%USERPROFILE%\EdgeIR_Backups`
  * Removes almost everything **except** essential user data (passwords, cookies, autofill, history, bookmarks, preferences, favicons, top sites).
  * Requires `-Force` and two confirmations.
* **RestoreBackup** → Restores from ZIP (defaults to the latest backup if none specified).

---

## Backup & Restore

* **Backups** are stored in `%USERPROFILE%\EdgeIR_Backups`.
* Format: `EdgeUserData-YYYYMMDD-HHMMSS.zip` + `EdgeUserData-REMOVED-*.log`.
* **Restore** safely renames the current profile to `User Data.before-restore-<timestamp>` before extracting the ZIP.

---

## Security Notes

* **Passwords & cookies are never deleted**.
* **IR mode is destructive** — use only when investigating suspected compromise.
* Always review backups before restoring.

---

## Troubleshooting

* If blocked by PowerShell policy, either use the shortcuts (which include `-ExecutionPolicy Bypass`) or run:

  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```
* Ensure Edge is closed; script will attempt to stop `msedge.exe`.

---
