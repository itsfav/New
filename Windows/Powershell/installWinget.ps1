<#
.SYNOPSIS
    Automated WinGet Installer & Repair Script for Windows 11.
.DESCRIPTION
    Checks for WinGet, attempts to re-register the App Installer, 
    deploys via official Microsoft modules, and falls back to GitHub if needed.
#>

# 1. Ensure the script is running with Administrative privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script MUST be run as an Administrator. Please restart PowerShell as Administrator."
    Exit
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Windows 11 WinGet Auto-Installer & Repair" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Function to verify if WinGet is responsive
function Test-WinGet {
    $command = Get-Command winget -ErrorAction SilentlyContinue
    if ($command) {
        try {
            $test = Invoke-Expression "winget --version" 2>$null
            if ($test) { return $true }
        } catch {}
    }
    return $false
}

# Check if already installed
if (Test-WinGet) {
    Write-Host "[✓] WinGet is already installed and working!" -ForegroundColor Green
    winget --version
    Exit
}

Write-Host "[!] WinGet not found or broken. Starting deployment methods..." -ForegroundColor Yellow

# --- METHOD 1: Re-register App Installer Package ---
Write-Host "`n[Method 1] Attempting to re-register Windows App Installer..." -ForegroundColor Cyan
try {
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
    Start-Sleep -Seconds 2
    if (Test-WinGet) {
        Write-Host "[✓] Success! WinGet fixed via Package Registration." -ForegroundColor Green
        Exit
    }
} catch {
    Write-Host "[-] Method 1 skipped or failed." -ForegroundColor Gray
}

# --- METHOD 2: Official Microsoft Bootstrap Tool ---
Write-Host "`n[Method 2] Attempting install via Microsoft.WinGet.Client module..." -ForegroundColor Cyan
try {
    # Configure TLS for secure download
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Install NuGet provider if missing
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Find-PackageProvider -Name NuGet -ForceBootstrap | Out-Null
    }

    # Install and run official WinGet repair toolkit
    Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Scope CurrentUser -Repository PSGallery -ErrorAction Stop
    Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
    
    Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop
    Start-Sleep -Seconds 3
    
    if (Test-WinGet) {
        Write-Host "[✓] Success! WinGet installed via Microsoft Client Module." -ForegroundColor Green
        Exit
    }
} catch {
    Write-Host "[-] Method 2 skipped or failed: $_" -ForegroundColor Gray
}

# --- METHOD 3: GitHub Fallback Download (Enterprise/LTSC bypass) ---
Write-Host "`n[Method 3] Falling back to direct GitHub Release download..." -ForegroundColor Cyan
try {
    $repo = "microsoft/winget-cli"
    $url = "https://api.github.com/repos/$repo/releases/latest"
    
    Write-Host "Fetching latest release data from GitHub..." -ForegroundColor Gray
    $release = Invoke-RestMethod -Uri $url -UseBasicParsing
    
    # Filter for the .msixbundle asset
    $asset = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
    
    if ($asset) {
        $downloadUrl = $asset.browser_download_url
        $tempPath = Join-Path $env:TEMP $asset.name
        
        Write-Host "Downloading $($asset.name)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
        
        Write-Host "Installing package bundle..." -ForegroundColor Gray
        Add-AppxPackage -Path $tempPath -ErrorAction Stop
        
        # Cleanup
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        if (Test-WinGet) {
            Write-Host "[✓] Success! WinGet manually installed via GitHub release bundle." -ForegroundColor Green
            Exit
        }
    } else {
        throw "Could not find a valid .msixbundle file in the latest GitHub release assets."
    }
} catch {
    Write-Host "[X] Method 3 failed: $_" -ForegroundColor Red
}

# --- FINAL VERIFICATION ---
if (Test-WinGet) {
    Write-Host "`n[✓] WinGet installation completed successfully!" -ForegroundColor Green
    winget --version
} else {
    Write-Host "`n[X] All installation methods exhausted. Please verify your internet connection or Microsoft Store settings." -ForegroundColor Red
}