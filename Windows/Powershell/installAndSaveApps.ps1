<#
.SYNOPSIS
    Stable WinGet Installer with C:\App installer cache only.
    Cache exists  -> install from local installer
    Cache missing -> winget download + delete yaml + rename installer + winget install
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Warning "Run as Administrator."
    Exit
}

$cacheDir = "C:\App"

if (-not (Test-Path $cacheDir)) {
    New-Item -Path $cacheDir -ItemType Directory | Out-Null
}

$appsToInstall = @(
    "7zip.7zip",
    "JanDeDobbeleer.OhMyPosh"
    #"Google.Chrome",
    #"Mozilla.Firefox",
    #"VideoLAN.VLC",
    #"Microsoft.PowerToys",
    "Microsoft.VisualStudioCode"
)

function Get-SafeName {
    param([string]$AppId)

    $namePart = ($AppId -split "\.")[-1]
    return $namePart -replace "[^\w]", "_"
}

function Format-Bytes {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }

    return "$Bytes B"
}

function Get-LatestVersion {
    param([string]$AppId)

    $info = winget show --id $AppId --accept-source-agreements 2>$null

    foreach ($line in $info) {
        if ($line -match "Version\s*:\s*(.+)$") {
            return $Matches[1].Trim()
        }
    }

    return "unknown"
}

function Test-AppInstalled {
    param([string]$AppId)

    $result = winget list --id $AppId 2>$null
    return $result -match [regex]::Escape($AppId)
}

function Find-CachedInstaller {
    param(
        [string]$AppId,
        [string]$Version
    )

    $safeName = Get-SafeName $AppId
    $baseName = "${safeName}_${Version}"

    return Get-ChildItem -Path $cacheDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.BaseName -eq $baseName -and
            $_.Extension.ToLower() -in @(".exe", ".msi", ".msix", ".msixbundle")
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Remove-DownloadedYaml {
    param([datetime]$StartTime)

    Get-ChildItem -Path $cacheDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -ge $StartTime.AddSeconds(-10) -and
            $_.Extension.ToLower() -in @(".yaml", ".yml")
        } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Rename-DownloadedInstaller {
    param(
        [string]$AppId,
        [string]$Version,
        [datetime]$StartTime
    )

    $safeName = Get-SafeName $AppId
    $baseName = "${safeName}_${Version}"

    $downloaded = Get-ChildItem -Path $cacheDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -ge $StartTime.AddSeconds(-10) -and
            $_.Extension.ToLower() -in @(".exe", ".msi", ".msix", ".msixbundle")
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $downloaded) {
        return $null
    }

    $newName = "${baseName}$($downloaded.Extension.ToLower())"
    $newPath = Join-Path $cacheDir $newName

    if (Test-Path $newPath) {
        Remove-Item $newPath -Force
    }

    Rename-Item -Path $downloaded.FullName -NewName $newName -Force

    return Get-Item $newPath -ErrorAction SilentlyContinue
}

function Install-CachedInstaller {
    param([string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLower()

    if ($ext -eq ".msi") {
        return & msiexec /i $Path /quiet /norestart 2>&1
    }

    if ($ext -in @(".msix", ".msixbundle")) {
        return Add-AppxPackage -Path $Path 2>&1
    }

    if ($ext -eq ".exe") {
        $output = & $Path /S 2>&1

        if ($LASTEXITCODE -ne 0) {
            $output = & $Path /silent /quiet /norestart 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            $output = & $Path /quiet /norestart 2>&1
        }

        return $output
    }

    return "Unsupported installer type: $ext"
}

Write-Host "`n  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "  ║   Automated WinGet App Installation  ║" -ForegroundColor Cyan
Write-Host   "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan

foreach ($app in $appsToInstall) {

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    Write-Host "  [?] $app — checking latest version..." -NoNewline -ForegroundColor DarkGray
    $version = Get-LatestVersion -AppId $app
    Write-Host "`r  [i] $app — latest version: $version          " -ForegroundColor DarkGray

    if (Test-AppInstalled -AppId $app) {
        $stopwatch.Stop()
        Write-Host "  [✓] $app — already installed." -ForegroundColor Green
        Write-Host ""
        continue
    }

    $installer = Find-CachedInstaller -AppId $app -Version $version
    $source = "downloaded"
    $output = $null

    if ($installer) {
        Write-Host "  [c] $app — found cache: $($installer.Name)" -ForegroundColor Cyan
        Write-Host "      Installing from cache..." -ForegroundColor DarkGray

        $source = "cache"
        $output = Install-CachedInstaller -Path $installer.FullName
    }
    else {
        Write-Host "  [+] $app — no cache found, downloading installer..." -ForegroundColor DarkGray

        $downloadStart = Get-Date

        $downloadOutput = winget download --id $app `
            --download-directory $cacheDir `
            --accept-source-agreements `
            --accept-package-agreements 2>&1

        Remove-DownloadedYaml -StartTime $downloadStart

        $installer = Rename-DownloadedInstaller -AppId $app -Version $version -StartTime $downloadStart

        if ($installer) {
            Write-Host "  [c] $app — saved cache: $($installer.Name)" -ForegroundColor Cyan
        } else {
            Write-Host "  [!] $app — installer cache not found after download." -ForegroundColor Yellow
        }

        Write-Host "      Installing with winget..." -ForegroundColor DarkGray

        $output = winget install --id $app `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements 2>&1
    }

    Start-Sleep -Seconds 2

    $success = Test-AppInstalled -AppId $app

    $stopwatch.Stop()

    $elapsed = $stopwatch.Elapsed
    $timeStr = if ($elapsed.TotalMinutes -ge 1) {
        "{0}m {1}s" -f [int]$elapsed.Minutes, [int]$elapsed.Seconds
    } else {
        "{0}s" -f [int]$elapsed.Seconds
    }

    $sizeStr = if ($installer -and (Test-Path $installer.FullName)) {
        Format-Bytes ((Get-Item $installer.FullName).Length)
    } else {
        "unknown"
    }

    if ($success) {
        Write-Host "  [✓] $app — installed successfully. " -NoNewline -ForegroundColor Green
        Write-Host "(Source: $source, Size: $sizeStr, Time: $timeStr)" -ForegroundColor DarkGray

        if ($installer) {
            Write-Host "      Cache file: $($installer.FullName)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  [✗] $app — installation failed. " -NoNewline -ForegroundColor Red
        Write-Host "(Time: $timeStr)" -ForegroundColor DarkGray

        if ($output) {
            Write-Host "      Output:" -ForegroundColor DarkGray
            Write-Host ($output | Out-String) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
}

Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       All installations complete.    ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan