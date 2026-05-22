#Requires -Version 5.1
<#
.SYNOPSIS
    scshellx Installer for Windows
    v2.1 | kvxnom edition
.DESCRIPTION
    Installs scshellx.py system-wide, creates a scshellx.cmd launcher,
    adds it to PATH, and optionally replaces cmd/PowerShell with scshellx.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------
function Write-Ok   { param($m) Write-Host "  [OK]   " -ForegroundColor Green  -NoNewline; Write-Host $m }
function Write-Info { param($m) Write-Host "  [INFO] " -ForegroundColor Cyan   -NoNewline; Write-Host $m }
function Write-Warn { param($m) Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Write-Err  { param($m) Write-Host "  [ERR]  " -ForegroundColor Red    -NoNewline; Write-Host $m; exit 1 }
function Write-Step { param($m) Write-Host ""; Write-Host "  >>> " -ForegroundColor Magenta -NoNewline; Write-Host $m -ForegroundColor White }
function Write-Div  { Write-Host ("  " + ("=" * 56)) -ForegroundColor DarkGray }

# ---------------------------------------------------------------
# Banner
# ---------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "   ___  ___  ___ _  _ ___ _    _    _  _" -ForegroundColor Cyan
Write-Host "  / __|/ __|/ __| || | __| |  | |  \ \/ /" -ForegroundColor Cyan
Write-Host "  \__ \ (__\__ \ __ | _|| |__| |__  >  < " -ForegroundColor Cyan
Write-Host "  |___/\___|___/_||_|___|____|____/_/\_\" -ForegroundColor Cyan
Write-Host ""
Write-Div
Write-Host "  scshellx Installer  |  v2.1  |  kvxnom edition" -ForegroundColor White
Write-Host "  Windows (PowerShell 5.1+)" -ForegroundColor DarkGray
Write-Div
Write-Host ""

# ---------------------------------------------------------------
# Elevation check
# ---------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Warn "Not running as Administrator."
    Write-Warn "Some features (system PATH, replace-shell) need elevation."
    Write-Warn "Re-run as Admin for full install, or continue for user-only install."
    Write-Host ""
    $cont = Read-Host "  Continue anyway? [y/N]"
    if ($cont -notmatch '^[yY]') { exit 0 }
}

# ---------------------------------------------------------------
# Install scope
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  Install location:" -ForegroundColor White
Write-Host ""
Write-Host "  [1]  User profile    (%LOCALAPPDATA%\scshellx)" -ForegroundColor Cyan
Write-Host "  [2]  System-wide     (C:\Program Files\scshellx)  [needs Admin]" -ForegroundColor Cyan
Write-Host ""
$installScope = ""
while ($installScope -notin @("1","2")) {
    $installScope = Read-Host "  Choose [1/2]"
}

# ---------------------------------------------------------------
# Replace-shell option
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  Replace shell option:" -ForegroundColor White
Write-Host ""
Write-Host "  [ ] Replace with normal shell" -ForegroundColor DarkGray
Write-Host "      Adds scshellx to cmd.exe AutoRun and PowerShell profile" -ForegroundColor DarkGray
Write-Host "      so it launches automatically in new terminal windows." -ForegroundColor DarkGray
Write-Host ""
$replaceShellInput = Read-Host "  Enable replace-shell? [y/N]"
$ReplaceShell = $replaceShellInput -match '^[yY]'

# ---------------------------------------------------------------
# Locate Python 3
# ---------------------------------------------------------------
Write-Step "Locating Python 3..."

$PyExe = $null
foreach ($c in @("python","python3","py")) {
    try {
        $ver = & $c --version 2>&1
        if ("$ver" -match "Python 3\.([89]|1[0-9])") {
            $found = Get-Command $c -ErrorAction SilentlyContinue
            if ($found) { $PyExe = $found.Source; Write-Ok "Found: $PyExe  ($ver)"; break }
        }
    } catch {}
}

if (-not $PyExe) {
    try {
        $ver = & py -3 --version 2>&1
        if ("$ver" -match "Python 3") {
            $PyExe = (Get-Command py -ErrorAction SilentlyContinue).Source
            Write-Ok "Found via py launcher: $ver"
        }
    } catch {}
}

if (-not $PyExe) {
    Write-Err "Python 3.8+ not found. Download from https://python.org and re-run."
}

# ---------------------------------------------------------------
# Install psutil
# ---------------------------------------------------------------
Write-Step "Checking psutil..."

$psCheck = & $PyExe -c "import psutil; print('ok')" 2>&1
if ("$psCheck" -eq "ok") {
    Write-Ok "psutil already installed."
} else {
    Write-Info "Installing psutil..."
    & $PyExe -m pip install psutil --quiet
    $psCheck2 = & $PyExe -c "import psutil; print('ok')" 2>&1
    if ("$psCheck2" -ne "ok") {
        Write-Err "Failed to install psutil. Run manually: pip install psutil"
    }
    Write-Ok "psutil installed."
}

# ---------------------------------------------------------------
# Set install directory
# ---------------------------------------------------------------
Write-Step "Setting install location..."

if ($installScope -eq "2" -and $IsAdmin) {
    $InstallDir = "C:\Program Files\scshellx"
} else {
    $InstallDir = "$env:LOCALAPPDATA\scshellx"
    if ($installScope -eq "2") { Write-Warn "Not admin - falling back to user install." }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Ok "Install dir: $InstallDir"

# ---------------------------------------------------------------
# Copy scshellx.py
# ---------------------------------------------------------------
Write-Step "Copying scshellx.py..."

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourcePy  = Join-Path $ScriptDir "scshellx.py"

if (-not (Test-Path $SourcePy)) {
    Write-Err "scshellx.py not found next to install.ps1 - Expected: $SourcePy"
}

Copy-Item -Path $SourcePy -Destination "$InstallDir\scshellx.py" -Force
Write-Ok "Copied scshellx.py"

# ---------------------------------------------------------------
# Write launchers
# NOTE: .cmd content built as concatenated strings, NOT a here-string.
# Here-strings (@"..."@) interpret @echo as a PS statement - broken.
# ---------------------------------------------------------------
Write-Step "Writing launchers..."

$LauncherCmd = "$InstallDir\scshellx.cmd"
$CmdContent  = "@echo off`r`n`"$PyExe`" `"$InstallDir\scshellx.py`" %*`r`n"
[System.IO.File]::WriteAllText($LauncherCmd, $CmdContent, [System.Text.Encoding]::ASCII)
Write-Ok "cmd launcher:  $LauncherCmd"

$LauncherPs1 = "$InstallDir\scshellx.ps1"
$Ps1Content  = "# scshellx launcher`r`n& '$PyExe' '$InstallDir\scshellx.py' @Args`r`n"
[System.IO.File]::WriteAllText($LauncherPs1, $Ps1Content, [System.Text.Encoding]::UTF8)
Write-Ok "ps1 launcher:  $LauncherPs1"

# ---------------------------------------------------------------
# Add to PATH
# ---------------------------------------------------------------
Write-Step "Adding to PATH..."

$PathTarget  = if ($installScope -eq "2" -and $IsAdmin) { "Machine" } else { "User" }
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", $PathTarget)

if ($CurrentPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$InstallDir", $PathTarget)
    Write-Ok "Added to $PathTarget PATH."
    Write-Info "Restart your terminal for PATH to take effect."
} else {
    Write-Ok "Already in PATH."
}

$env:PATH += ";$InstallDir"

# ---------------------------------------------------------------
# Replace-shell
# NOTE: ?. (null-conditional) is PS7+ only. Using explicit null
# check with Get-ItemProperty for PS 5.1 compatibility.
# ---------------------------------------------------------------
if ($ReplaceShell) {
    Write-Step "Configuring replace-shell..."

    $RegPath    = "HKCU:\Software\Microsoft\Command Processor"
    $AutoRunVal = "`"$LauncherCmd`""

    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    # PS 5.1-safe null check (no ?. operator)
    $existingProp = Get-ItemProperty -Path $RegPath -Name "AutoRun" -ErrorAction SilentlyContinue
    $OldVal = if ($existingProp) { $existingProp.AutoRun } else { $null }

    if ($OldVal -and ($OldVal -notlike "*scshellx*")) {
        Set-ItemProperty -Path $RegPath -Name "AutoRun_backup" -Value $OldVal
        Write-Info "Backed up old AutoRun value."
    }

    Set-ItemProperty -Path $RegPath -Name "AutoRun" -Value $AutoRunVal
    Write-Ok "cmd.exe AutoRun set to scshellx"

    # PowerShell profile
    $ProfileDir = Split-Path $PROFILE
    if (-not (Test-Path $ProfileDir)) {
        New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    }

    $ProfileBlock = "`r`n# scshellx auto-launch`r`n& '$LauncherPs1'`r`n"

    if (Test-Path $PROFILE) {
        $existing = Get-Content $PROFILE -Raw
        if ($existing -notlike "*scshellx*") {
            Add-Content -Path $PROFILE -Value $ProfileBlock
            Write-Ok "Added scshellx to PS profile: $PROFILE"
        } else {
            Write-Ok "Already in PS profile."
        }
    } else {
        Set-Content -Path $PROFILE -Value $ProfileBlock
        Write-Ok "Created PS profile: $PROFILE"
    }

    Write-Warn "Open a new terminal to see scshellx launch automatically."
}

# ---------------------------------------------------------------
# Write uninstaller - built line by line, no nested here-strings,
# no ?. operator inside the embedded script either.
# ---------------------------------------------------------------
Write-Step "Writing uninstaller..."

$UninstallPath = "$InstallDir\scshellx-uninstall.ps1"
$u = [System.Collections.Generic.List[string]]::new()
$u.Add("# scshellx Uninstaller")
$u.Add("Write-Host 'Removing scshellx...' -ForegroundColor Yellow")
$u.Add("")
$u.Add("# Remove from PATH")
$u.Add('$isAdm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)')
$u.Add('$tgt = if ($isAdm) { "Machine" } else { "User" }')
$u.Add('$p = [Environment]::GetEnvironmentVariable("Path", $tgt)')
$u.Add('$p = ($p -split ";" | Where-Object { $_ -ne "' + $InstallDir + '" }) -join ";"')
$u.Add('[Environment]::SetEnvironmentVariable("Path", $p, $tgt)')
$u.Add("")
$u.Add("# Restore cmd AutoRun")
$u.Add('$reg = "HKCU:\Software\Microsoft\Command Processor"')
$u.Add('$bkProp = Get-ItemProperty -Path $reg -Name "AutoRun_backup" -ErrorAction SilentlyContinue')
$u.Add('$bkVal  = if ($bkProp) { $bkProp.AutoRun_backup } else { $null }')
$u.Add('if ($bkVal) {')
$u.Add('    Set-ItemProperty -Path $reg -Name "AutoRun" -Value $bkVal')
$u.Add('    Remove-ItemProperty -Path $reg -Name "AutoRun_backup" -ErrorAction SilentlyContinue')
$u.Add('} else {')
$u.Add('    Remove-ItemProperty -Path $reg -Name "AutoRun" -ErrorAction SilentlyContinue')
$u.Add('}')
$u.Add("")
$u.Add("# Remove from PS profile")
$u.Add('if (Test-Path $PROFILE) {')
$u.Add('    $c = Get-Content $PROFILE -Raw')
$u.Add('    $c = $c -replace "(?ms)# scshellx auto-launch[^\n]*\n[^\n]*\n", ""')
$u.Add('    Set-Content -Path $PROFILE -Value $c')
$u.Add('}')
$u.Add("")
$u.Add("# Remove install dir")
$u.Add('Remove-Item -Recurse -Force "' + $InstallDir + '" -ErrorAction SilentlyContinue')
$u.Add("Write-Host 'scshellx removed.' -ForegroundColor Green")
[System.IO.File]::WriteAllLines($UninstallPath, $u, [System.Text.Encoding]::UTF8)
Write-Ok "Uninstaller: $UninstallPath"

# ---------------------------------------------------------------
# Done
# ---------------------------------------------------------------
Write-Host ""
Write-Div
Write-Host ""
Write-Ok "scshellx installed successfully!"
Write-Info "Run it:      scshellx"
Write-Info "Uninstall:   powershell -File `"$UninstallPath`""
Write-Host ""
Write-Div
Write-Host ""