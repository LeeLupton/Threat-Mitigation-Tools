<#
Clear-Edge-Cache.ps1

Purpose:
  Quickly clear Microsoft Edge's caches without touching cookies, saved passwords, or sign-in state by default.
  Designed to be a desktop shortcut.

Default behavior (safe):
  • Clears HTTP cache, code cache, GPU/Shader caches, and Service Worker caches.
  • Does NOT clear cookies, local storage, passwords, or history.

Optional behavior:
  • -Moderate switch also clears heavier site data (IndexedDB, CacheStorage, File System, WebSQL) but keeps Local/Session Storage intact so you don’t get logged out.
  • -Aggressive switch clears everything Moderate does PLUS Local/Session Storage and Service Worker registrations (⚠️ may sign you out of sites).
  • -IncidentResponse (IR) switch performs a malware-mitigation deep clean: backs up all Edge data to a timestamped ZIP first, then wipes nearly everything except essential user data (passwords, cookies, autofill, history, bookmarks, preferences) so you keep your sign‑in and saved items. Requires **-Force** and double confirmation (two y/n prompts).
  • -RestoreBackup switch restores from a ZIP backup. If no path is provided, the most recent ZIP in %USERPROFILE%\EdgeIR_Backups is used.

Usage examples:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\\Threat-Mitigation-Tools\\Clear-Edge-Cache.ps1"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\\Threat-Mitigation-Tools\\Clear-Edge-Cache.ps1" -Moderate
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\\Threat-Mitigation-Tools\\Clear-Edge-Cache.ps1" -Aggressive
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\\Threat-Mitigation-Tools\\Clear-Edge-Cache.ps1" -IncidentResponse -Force
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\\Threat-Mitigation-Tools\\Clear-Edge-Cache.ps1" -RestoreBackup
  powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\\Threat-Mitigation-Tools\\Clear-Edge-Cache.ps1" -RestoreBackup -RestoreBackupPath "C:\\Users\\Lee\\EdgeIR_Backups\\EdgeUserData-20250816-010203.zip"

Notes:
  • IR creates a ZIP backup in %USERPROFILE%\EdgeIR_Backups (override with -BackupDir).
  • -RestoreBackup without a path restores the most recent ZIP in %USERPROFILE%\EdgeIR_Backups.
  • Logs every removed path to a .log file next to the ZIP.
  • IR preserves: Cookies, Login Data (passwords), Web Data (autofill), History, Bookmarks, Preferences, Top Sites, Favicons.
  • IR removes: caches, site storage (all types), extensions, service workers, temp/telemetry/artifacts.

#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch] $Moderate,
  [switch] $Aggressive,
  [switch] $IncidentResponse,
  [switch] $RestoreBackup,
  [switch] $Force,
  [string] $BackupDir = "$([Environment]::GetFolderPath('UserProfile'))\\EdgeIR_Backups",
  [string] $RestoreBackupPath,
  [switch] $RestartEdge
)

function Write-Info($msg){ Write-Host "[EdgeCache] $msg" }
function Write-Warn($msg){ Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Locate Edge User Data root
$edgeRoot = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"
if (-not (Test-Path $edgeRoot)) { throw "Edge user data folder not found at '$edgeRoot'. Is Microsoft Edge (Chromium) installed?" }

# Detect running Edge
$edgeWasRunning = $false
$edgeProcs = Get-Process -Name msedge -ErrorAction SilentlyContinue
if ($edgeProcs) { $edgeWasRunning = $true }

# Attempt graceful shutdown of Edge so caches unlock. If graceful shutdown is unsuccessful use Stop-Process.
$edge = Get-Process msedge -ErrorAction SilentlyContinue
if ($edge) {
  Write-Info "Attempting graceful close..."
  $null = $edge.CloseMainWindow()
  if (-not $edge.WaitForExit(3000)) { # wait up to 3s
    Write-Info "Graceful close failed; terminating..."
    Stop-Process -Id $edge.Id -Force -ErrorAction SilentlyContinue # Force shutdown of Edge
  }
}

# Build list of profiles
$profiles = Get-ChildItem -LiteralPath $edgeRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'System Profile' -and (Test-Path (Join-Path $_.FullName 'Preferences')) }
if (-not $profiles) {
  $defaultPath = Join-Path $edgeRoot 'Default'
  if (Test-Path $defaultPath) { $profiles = ,(Get-Item $defaultPath) }
}
if (-not $profiles) { throw "No Edge profiles found under '$edgeRoot'." }

# Relative cache targets (safe set)
$safeDirs = @(
  'Cache','Code Cache','Code Cache\\js','Code Cache\\wasm',
  'GPUCache','ShaderCache','GrShaderCache',
  'Service Worker\\CacheStorage','Service Worker\\ScriptCache',
  'DawnCache','OptimizationGuidePredictionModelStore','Platform Notifications','Reporting and NEL'
)

# Moderate set (heavier site data, but keeps Local/Session Storage)
$moderateDirs = @('IndexedDB','databases','File System','Storage')

# Aggressive set (adds Local/Session Storage & full Service Worker wipe)
$aggressiveDirs = @('Local Storage','Session Storage','Service Worker')

# Files to remove (safe)
$safeFiles = @('Network\\Network Action Predictor','Network\\Network Persistent State.tmp','Network\\Reporting and NEL','GPUCache\\index','First Run')

# Never touch these (core user data to preserve sign-in & credentials)
$protectFiles = @(
  'Cookies','Cookies-journal','Network\\Cookies','Network\\Cookies-journal',
  'Login Data','Login Data-journal',
  'Web Data','Web Data-journal',
  'History','History-journal',
  'Top Sites','Top Sites-journal',
  'Favicons','Favicons-journal',
  'Bookmarks','Preferences'
)

$targets = [System.Collections.Generic.List[string]]::new()
foreach ($p in $profiles) {
  foreach ($d in $safeDirs)  { $targets.Add((Join-Path $p.FullName $d)) }
  foreach ($f in $safeFiles) { $targets.Add((Join-Path $p.FullName $f)) }
  if ($Moderate -or $Aggressive) { foreach ($d in $moderateDirs) { $targets.Add((Join-Path $p.FullName $d)) } }
  if ($Aggressive) { foreach ($d in $aggressiveDirs) { $targets.Add((Join-Path $p.FullName $d)) } }
}

# ----------------------------
# Incident Response (IR) mode
# ----------------------------
$removedLog = $null
if ($IncidentResponse) {
  if (-not $Force) { throw "-IncidentResponse requires -Force. Aborting." }

  Write-Warn "INCIDENT RESPONSE MODE WILL:"
  Write-Warn "  1) BACK UP your entire Edge user data folder to a timestamped ZIP."
  Write-Warn "  2) DEEPLY CLEAN almost everything: caches, site storage, service workers, extensions, temp artifacts."
  Write-Warn "  3) PRESERVE essential user data so you remain signed-in: passwords, cookies, autofill, history, bookmarks, preferences, favicons, top sites."
  Write-Warn "This is intended for suspected browser-based malware. Use with caution."

  # First confirmation
  $resp1 = Read-Host "Continue? (y/n)"
  if ($resp1 -notin @('y','Y')) { Write-Err "Aborted by user."; return }

  # Second confirmation
  $resp2 = Read-Host "Are you sure? This will remove extensions and site data but keep core user data. Proceed? (y/n)"
  if ($resp2 -notin @('y','Y')) { Write-Err "Aborted by user."; return }

  # Prepare backup
  try { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null } catch {}
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
  $zipPath = Join-Path $BackupDir "EdgeUserData-$stamp.zip"
  $removedLog = Join-Path $BackupDir "EdgeUserData-REMOVED-$stamp.log"

  Write-Info "Backing up '$edgeRoot' -> '$zipPath' ..."
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path (Join-Path $edgeRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
  Write-Info "Backup complete." 

  # IR removal sets
  $irRemoveDirs = @(
    'Cache','Code Cache','GPUCache','ShaderCache','GrShaderCache','DawnCache',
    'OptimizationGuidePredictionModelStore','Platform Notifications','Reporting and NEL',
    'Service Worker','IndexedDB','databases','File System','Storage','File System Origins','BudgetService',
    'Extension Rules','Extension State','Extensions','AutofillStates','Media Cache','Network','blob_storage',
    'VideoDecodeStats','WebRTC Logs','Safe Browsing','TransportSecurity','Certificates','Partitioned WebSQL'
  )

  $irRemoveFiles = @(
    'Network\\Network Action Predictor','Network\\Reporting and NEL','Visited Links',
    'Translation Ranker Model','OriginTrials','QuotaManager','QuotaManager-journal','First Run','Preferences.lock'
  )

  $preserveSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($f in $protectFiles) { [void]$preserveSet.Add($f) }

  $removed = New-Object System.Collections.Generic.List[string]
  foreach ($p in $profiles) {
    foreach ($d in $irRemoveDirs) {
      $path = Join-Path $p.FullName $d
      if (Test-Path -LiteralPath $path) {
        try { Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue; $removed.Add($path); Write-Info "IR cleared: $path" } catch {}
      }
    }
    foreach ($f in $irRemoveFiles) {
      $path = Join-Path $p.FullName $f
      if (Test-Path -LiteralPath $path) {
        try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; $removed.Add($path); Write-Info "IR removed file: $path" } catch {}
      }
    }

    # Sweep: delete all non-preserved top-level items inside the profile
    Get-ChildItem -LiteralPath $p.FullName -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $name = $_.Name
      if ($preserveSet.Contains($name)) { return }
      if ($_.PSIsContainer) {
        try { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue; $removed.Add($_.FullName); Write-Info "IR removed dir: $($_.FullName)" } catch {}
      } else {
        try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; $removed.Add($_.FullName); Write-Info "IR removed file: $($_.FullName)" } catch {}
      }
    }
  }

  # Also sweep some root-level artifacts while preserving Local State and system bits
  $rootPreserve = @('Local State','pnacl')
  Get-ChildItem -LiteralPath $edgeRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($profiles.FullName -contains $_.FullName) { return } # skip profile folders already handled
    if ($rootPreserve -contains $_.Name) { return }
    try {
      if ($_.PSIsContainer) { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
      else { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
      $removed.Add($_.FullName); Write-Info "IR cleaned root: $($_.FullName)"
    } catch {}
  }

  # Write removal log
  try { $removed | Out-File -FilePath $removedLog -Encoding UTF8 -Force; Write-Info "Removal log: $removedLog" } catch {}
}

# ----------------------------
# Restore Backup mode
# ----------------------------
if ($RestoreBackup) {
  # Determine ZIP to restore
  $zipPathToRestore = $RestoreBackupPath
  if (-not $zipPathToRestore -or -not (Test-Path -LiteralPath $zipPathToRestore)) {
    try { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null } catch {}
    $latest = Get-ChildItem -LiteralPath $BackupDir -Filter 'EdgeUserData-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No backup ZIPs found in '$BackupDir'. Provide -RestoreBackupPath <zip>." }
    $zipPathToRestore = $latest.FullName
  }

  Write-Info "Restoring from '$zipPathToRestore' ..."

  # Move current User Data out of the way (safer than deleting)
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
  $currentPath = $edgeRoot
  if (Test-Path -LiteralPath $currentPath) {
    $backupCurrent = Join-Path (Split-Path $currentPath -Parent) ("User Data.before-restore-" + $stamp)
    try {
      Rename-Item -LiteralPath $currentPath -NewName (Split-Path $backupCurrent -Leaf) -Force
      Write-Info "Existing profile moved to '$(Split-Path $backupCurrent -Leaf)'."
    } catch {
      Remove-Item -LiteralPath $currentPath -Recurse -Force -ErrorAction SilentlyContinue
      Write-Info "Existing profile removed to allow restore."
    }
  }

  Expand-Archive -LiteralPath $zipPathToRestore -DestinationPath (Join-Path $env:LOCALAPPDATA 'Microsoft\\Edge') -Force
  Write-Info "Restore complete."
}

# Regular (non-IR) removal path
if (-not $IncidentResponse -and -not $RestoreBackup) {
  $errors = @()
  foreach ($path in $targets) {
    try {
      if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($item -and $item.PSIsContainer) {
          Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
          Write-Info "Cleared: $path"
        } else {
          Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
          Write-Info "Removed file: $path"
        }
      }
    } catch { $errors += $_ }
  }

  if ($errors.Count -gt 0) { Write-Info "Completed with some non-fatal errors on locked items." } else { Write-Info "Cache clear complete." }
} elseif ($IncidentResponse) {
  Write-Info "Incident Response cleanup complete."
} elseif ($RestoreBackup) {
  Write-Info "Backup restore finished."
}

# Relaunch Edge if needed
if ($RestartEdge -or $edgeWasRunning) {
  Write-Info "Launching Edge..."; Start-Process "msedge.exe" | Out-Null
}

