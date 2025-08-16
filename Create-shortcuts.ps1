<#
Create-Shortcuts.ps1
Creates Desktop shortcuts for Clear-Edge-Cache.ps1 using the repo path and an optional custom icon.

Assumptions:
- Repo root: C:\Threat-Mitigation-Tools\
- Cleaner script: Clear-Edge-Cache.ps1 (sibling of this file)
- Icon: icons\broom.ico (relative to repo root)

Usage:
  Right-click → Run with PowerShell
  or
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Threat-Mitigation-Tools\Create-Shortcuts.ps1"
#>

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolPath   = Join-Path $scriptRoot 'Clear-Edge-Cache.ps1'
$iconPath   = Join-Path $scriptRoot 'icons\broom.ico'
$desktop    = [Environment]::GetFolderPath('Desktop')
$psExe      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

if (!(Test-Path $toolPath)) { throw "Cleaner script not found at '$toolPath'. Ensure Clear-Edge-Cache.ps1 is in the repo root." }

function New-EdgeCleanerShortcut {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][string]$Args = ''
  )
  $lnkPath = Join-Path $desktop ("$Name.lnk")
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($lnkPath)
  $sc.TargetPath = $psExe
  $sc.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$toolPath`" $Args"
  $sc.WorkingDirectory = $scriptRoot
  if (Test-Path $iconPath) { $sc.IconLocation = $iconPath } else { $sc.IconLocation = "$env:SystemRoot\System32\SHELL32.dll,264" }
  $sc.Save()
  Write-Host "Created: $lnkPath"
}

Write-Host "Using cleaner: $toolPath"
Write-Host (Test-Path $iconPath ? "Icon: $iconPath" : "Icon: (fallback) shell32.dll,264")

# Create shortcuts
New-EdgeCleanerShortcut -Name 'Edge Clean — Default'            -Args ''
New-EdgeCleanerShortcut -Name 'Edge Clean — Moderate'           -Args '-Moderate'
New-EdgeCleanerShortcut -Name 'Edge Clean — Aggressive'         -Args '-Aggressive'
New-EdgeCleanerShortcut -Name 'Edge Clean — Incident Response'  -Args '-IncidentResponse -Force'
New-EdgeCleanerShortcut -Name 'Edge Clean — Restore Latest'     -Args '-RestoreBackup'

Write-Host "All shortcuts created on Desktop."
