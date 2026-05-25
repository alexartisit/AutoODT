#Requires -RunAsAdministrator
param(
    [switch]$Silent,
    [switch]$KeepLogs
)

function Write-Header  { param($m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Success { param($m) Write-Host "[OK]  $m" -ForegroundColor Green }
function Write-Warn    { param($m) Write-Host "[!!]  $m" -ForegroundColor Yellow }
function Write-Fail    { param($m) Write-Host "[ERR] $m" -ForegroundColor Red }
function Write-Info    { param($m) Write-Host "[--]  $m" -ForegroundColor Gray }

# Optional log
$LogPath = "$env:TEMP\OfficeUninstall.log"
if ($KeepLogs) {
    Start-Transcript -Path $LogPath -Force
    Write-Info "Transcript started: $LogPath"
}

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "Run this script as Administrator."
    exit 1
}

# Confirmation
if (-not $Silent) {
    Write-Host "`n  This will COMPLETELY remove Microsoft Office from this PC." -ForegroundColor Yellow
    $ans = Read-Host "  Type YES to continue"
    if ($ans -ne "YES") {
        Write-Warn "Aborted."
        exit 0
    }
}

# ─── STEP 1: Kill Office processes ───────────────────────────────────────────
Write-Header "Step 1: Kill running Office processes"

$procs = @(
    "WINWORD","EXCEL","POWERPNT","OUTLOOK","ONENOTE","MSPUB","MSACCESS",
    "INFOPATH","OfficeClickToRun","OfficeC2RClient","OfficeBackgroundTaskHandler",
    "AppVShNotify","lync","communicator"
)
foreach ($p in $procs) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
        Write-Info "Killed: $p"
    }
}
Write-Success "Office processes stopped."

# ─── STEP 2: Click-to-Run uninstall ──────────────────────────────────────────
Write-Header "Step 2: Remove Click-to-Run (Office 365 / Microsoft 365)"

$c2rKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
if (Test-Path $c2rKey) {
    Write-Info "Click-to-Run detected."

    $c2rExePaths = @(
        "$env:ProgramFiles\Common Files\microsoft shared\ClickToRun\OfficeClickToRun.exe",
        "${env:ProgramFiles(x86)}\Common Files\microsoft shared\ClickToRun\OfficeClickToRun.exe"
    )
    $c2rExe = $c2rExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($c2rExe) {
        Write-Info "Running C2R uninstaller..."
        Start-Process -FilePath $c2rExe -ArgumentList "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=AllProducts DISPLAY=0" -Wait -ErrorAction SilentlyContinue
        Write-Success "C2R uninstaller finished."
    } else {
        Write-Warn "C2R exe not found. Skipping C2R step."
    }
} else {
    Write-Info "No Click-to-Run installation found."
}

# ─── STEP 3: MSI-based Office (registry scan) ────────────────────────────────
Write-Header "Step 3: Remove MSI-based Office installations"

$keywords = @("Microsoft Office","Microsoft 365","Office 16","Office 15","Office 14","Office 12","Office 11")
$regPaths  = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$found = @()
foreach ($rp in $regPaths) {
    if (Test-Path $rp) {
        $items = Get-ChildItem -Path $rp -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $props = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
            $name  = $props.DisplayName
            if ($name) {
                $match = $false
                foreach ($kw in $keywords) {
                    if ($name -like "*$kw*") { $match = $true; break }
                }
                if ($match) {
                    $found += [PSCustomObject]@{
                        Name           = $name
                        UninstallString = $props.UninstallString
                        QuietUninstall = $props.QuietUninstallString
                    }
                }
            }
        }
    }
}

if ($found.Count -eq 0) {
    Write-Info "No MSI-based Office products found."
} else {
    Write-Info "Found $($found.Count) product(s):"
    foreach ($pkg in $found) {
        Write-Info "  * $($pkg.Name)"
    }

    foreach ($pkg in $found) {
        Write-Info "Removing: $($pkg.Name)..."
        $cmd = $pkg.QuietUninstall
        if (-not $cmd) { $cmd = $pkg.UninstallString }

        if ($cmd -match "\{[0-9A-Fa-f\-]+\}") {
            $guid = $Matches[0]
            $proc = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart REBOOT=ReallySuppress" -Wait -PassThru -ErrorAction SilentlyContinue
            Write-Success "Removed (exit $($proc.ExitCode)): $($pkg.Name)"
        } elseif ($cmd) {
            Start-Process "cmd.exe" -ArgumentList "/c $cmd /quiet /norestart" -Wait -ErrorAction SilentlyContinue
            Write-Success "Removed: $($pkg.Name)"
        } else {
            Write-Warn "No uninstall string found for: $($pkg.Name)"
        }
    }
}

# ─── STEP 4: Winget removal ───────────────────────────────────────────────────
Write-Header "Step 4: Remove via winget (if available)"

$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    $ids = @("Microsoft.Office","Microsoft.Office365","Microsoft.Microsoft365")
    foreach ($id in $ids) {
        Write-Info "Trying: winget uninstall $id"
        & winget uninstall --id $id --silent --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "winget removed: $id"
        }
    }
} else {
    Write-Info "winget not available. Skipping."
}

# ─── STEP 5: Delete leftover folders ─────────────────────────────────────────
Write-Header "Step 5: Delete leftover Office folders"

$folders = @(
    "$env:ProgramFiles\Microsoft Office",
    "${env:ProgramFiles(x86)}\Microsoft Office",
    "$env:ProgramFiles\Common Files\microsoft shared\OFFICE16",
    "$env:ProgramFiles\Common Files\microsoft shared\OFFICE15",
    "$env:ProgramFiles\Common Files\microsoft shared\OFFICE14",
    "$env:ProgramFiles\Common Files\microsoft shared\ClickToRun",
    "${env:ProgramFiles(x86)}\Common Files\microsoft shared\ClickToRun",
    "$env:LOCALAPPDATA\Microsoft\Office",
    "$env:APPDATA\Microsoft\Office",
    "$env:LOCALAPPDATA\Microsoft\OneNote",
    "$env:APPDATA\Microsoft\Templates"
)
foreach ($f in $folders) {
    if (Test-Path $f) {
        Remove-Item -Path $f -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Deleted: $f"
    }
}

# ─── STEP 6: Clean registry keys ─────────────────────────────────────────────
Write-Header "Step 6: Clean Office registry keys"

$regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Office",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office",
    "HKCU:\Software\Microsoft\Office"
)
foreach ($k in $regKeys) {
    if (Test-Path $k) {
        Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Removed: $k"
    }
}

# ─── STEP 7: Remove shortcuts ────────────────────────────────────────────────
Write-Header "Step 7: Remove Office shortcuts"

$shortcutDirs = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Office",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Office 2016",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Office 2019",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Office 2021",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Office"
)
$officeApps = @("Word","Excel","PowerPoint","Outlook","OneNote","Publisher","Access")

foreach ($dir in $shortcutDirs) {
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Removed shortcut folder: $dir"
    }
}

$desktopDirs = @("$env:PUBLIC\Desktop","$env:USERPROFILE\Desktop")
foreach ($dir in $desktopDirs) {
    if (Test-Path $dir) {
        $lnks = Get-ChildItem -Path $dir -Filter "*.lnk" -ErrorAction SilentlyContinue
        foreach ($lnk in $lnks) {
            $isOffice = $false
            foreach ($app in $officeApps) {
                if ($lnk.Name -like "*$app*") { $isOffice = $true; break }
            }
            if ($isOffice) {
                Remove-Item -Path $lnk.FullName -Force -ErrorAction SilentlyContinue
                Write-Info "Removed shortcut: $($lnk.Name)"
            }
        }
    }
}

# ─── DONE – Always reboot automatically ───────────────────────────────────────
Write-Header "Done"
Write-Host ""
Write-Host "  Microsoft Office has been removed." -ForegroundColor Green
Write-Host "  Rebooting in 10 seconds..." -ForegroundColor Yellow
Write-Host ""

if ($KeepLogs) { Stop-Transcript }

Start-Sleep -Seconds 10
Restart-Computer -Force