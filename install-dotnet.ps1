<#
.SYNOPSIS
  Dahlia .NET installer (Windows). Installs every .NET SDK Dahlia needs
  (see dotnet-versions.env) using Microsoft's dotnet-install.ps1.
  Safe to re-run: only missing major.minor SDK channels are installed.

.DESCRIPTION
  Channels cover every TargetFramework in AleytiaFairlight/Dahlia:
    net8.0  -> TwitchLib.Client tests (SDK 8)
    net9.0  -> bot/coordinator/twitch/obs/dashboard/avatar/youtube/games/social (SDK 9)
    net10.0 -> stage-tamagotchi-kirie + TwitchLib multi-target (SDK 10)

.PARAMETER InstallDir
  Where to install. Default: $env:DOTNET_INSTALL_DIR, else "$env:ProgramFiles\dotnet"
  (falls back to "$env:USERPROFILE\.dotnet" when not elevated).

.PARAMETER Channel
  Install only this channel, e.g. -Channel 9.0. Default: all in dotnet-versions.env.

.PARAMETER Check
  Check only: exit 0 when all requested SDKs are present, 1 otherwise (no network).

.PARAMETER DryRun
  Print what would be installed, install nothing.

.PARAMETER Quality
  SDK quality band. Default: value of DOTNET_QUALITY in dotnet-versions.env, else GA.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-dotnet.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-dotnet.ps1 -Check
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-dotnet.ps1 -Channel 9.0 -DryRun
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "",
  [string]$Channel = "",
  [switch]$Check,
  [switch]$DryRun,
  [string]$Quality = ""
)

$ErrorActionPreference = "Stop"
$InstallerUrl = "https://dot.net/v1/dotnet-install.ps1"

function Say([string]$msg) { Write-Host "dotnet-installer: $msg" }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$versionsFile = Join-Path $scriptDir "dotnet-versions.env"
if (-not (Test-Path $versionsFile)) { throw "versions file not found: $versionsFile" }

# Minimal .env parser (KEY="v" / KEY='v' / KEY=v, # comments).
$channels = ""
$envQuality = "GA"
foreach ($line in (Get-Content $versionsFile)) {
  $t = $line.Trim()
  if ($t -eq "" -or $t.StartsWith("#")) { continue }
  $m = [regex]::Match($t, '^(?<k>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<v>.*)$')
  if (-not $m.Success) { continue }
  $k = $m.Groups["k"].Value
  $v = $m.Groups["v"].Value.Trim()
  if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
    $v = $v.Substring(1, $v.Length - 2)
  }
  $hash = $v.IndexOf(" #")
  if ($hash -ge 0) { $v = $v.Substring(0, $hash).Trim() }
  if ($k -eq "DOTNET_CHANNELS") { $channels = $v }
  if ($k -eq "DOTNET_QUALITY") { $envQuality = $v }
}
if ([string]::IsNullOrWhiteSpace($channels)) { throw "DOTNET_CHANNELS empty in $versionsFile" }
if ([string]::IsNullOrWhiteSpace($Quality)) { $Quality = $envQuality }
if ([string]::IsNullOrWhiteSpace($Quality)) { $Quality = "GA" }

if (-not [string]::IsNullOrWhiteSpace($Channel)) { $channels = $Channel }
$wanted = @($channels -split '\s+' | Where-Object { $_ -ne "" })

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  if (-not [string]::IsNullOrWhiteSpace($env:DOTNET_INSTALL_DIR)) {
    $InstallDir = $env:DOTNET_INSTALL_DIR
  } else {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated -and (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles))) {
      $InstallDir = Join-Path $env:ProgramFiles "dotnet"
    } else {
      $InstallDir = Join-Path $env:USERPROFILE ".dotnet"
    }
  }
}

function Get-DotnetBin {
  $inDir = Join-Path $InstallDir "dotnet.exe"
  if (Test-Path $inDir) { return $inDir }
  $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Test-SdkPresent([string]$major, [string]$bin) {
  if ([string]::IsNullOrWhiteSpace($bin)) { return $false }
  try {
    $out = & $bin --list-sdks 2>$null
  } catch { return $false }
  foreach ($line in $out) {
    if ($line -match "^\s*$major\.") { return $true }
  }
  return $false
}

$dotnetBin = Get-DotnetBin
$missing = @()
foreach ($ch in $wanted) {
  $major = ($ch -split '\.')[0]
  if (Test-SdkPresent $major $dotnetBin) {
    Write-Verbose "SDK $ch present ($dotnetBin)"
  } else {
    $missing += $ch
  }
}

if ($Check) {
  if ($missing.Count -eq 0) {
    Say("all requested SDKs present ($($wanted -join ' ')) via $dotnetBin")
    exit 0
  } else {
    Say("missing SDK channel(s): $($missing -join ' ') (install dir: $InstallDir, dotnet: $dotnetBin)")
    exit 1
  }
}

if ($missing.Count -eq 0) {
  Say("all requested SDKs present ($($wanted -join ' ')) via $dotnetBin")
  & $dotnetBin --list-sdks
  exit 0
}

if ($DryRun) {
  Say("would install SDK channel(s): $($missing -join ' ') into $InstallDir")
  Say("installer: $InstallerUrl (quality: $Quality)")
  exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dahlia-dotnet-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $installer = Join-Path $tmp "dotnet-install.ps1"
  Say("downloading $InstallerUrl ...")
  Invoke-WebRequest -Uri $InstallerUrl -OutFile $installer -UseBasicParsing
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  foreach ($ch in $missing) {
    Say("installing .NET SDK channel $ch into $InstallDir ...")
    & $installer -Channel $ch -Quality $Quality -InstallDir $InstallDir
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$dotnetBin = Get-DotnetBin
$failed = @()
foreach ($ch in $wanted) {
  $major = ($ch -split '\.')[0]
  if (-not (Test-SdkPresent $major $dotnetBin)) { $failed += $ch }
}
if ($failed.Count -gt 0) {
  Say("FAILED: SDK channel(s) still missing after install: $($failed -join ' ')")
  if ($dotnetBin) { & $dotnetBin --list-sdks }
  exit 1
}

Say("done. SDKs:")
& $dotnetBin --list-sdks
Say("runtimes:")
& $dotnetBin --list-runtimes
