<#
.SYNOPSIS
    Clean WinGet Installer — throttled line output, no cursor tricks.
#>
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Warning "Run as Administrator."; Exit }

$appsToInstall = @(
    "Google.Chrome",
    "7zip.7zip",
    "Mozilla.Firefox",
    "VideoLAN.VLC",
    "JanDeDobbeleer.OhMyPosh",
    "Microsoft.VisualStudioCode",
    "Microsoft.PowerToys"
)

function Get-Bar {
    param([int]$Pct, [int]$Width = 20)
    $f = [Math]::Round($Width * $Pct / 100)
    return ("█" * $f) + ("░" * ($Width - $f))
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

Write-Host "`n  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "  ║   Automated WinGet App Installation  ║" -ForegroundColor Cyan
Write-Host   "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan

foreach ($app in $appsToInstall) {

    $check = winget list --id $app 2>$null
    if ($check -match $app) {
        Write-Host "  [✓] $app — already installed." -ForegroundColor Green
        continue
    }

    Write-Host "  [+] $app" -ForegroundColor DarkGray

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    $job = Start-Job -ScriptBlock {
        param($id)
        $result  = winget install --id $id --silent --accept-package-agreements --accept-source-agreements 2>&1
        $success = $result -match "Successfully installed|已成功安装"

        # 尝试从 winget 输出里解析下载大小
        # winget 输出格式通常是: "  725 MB" 或 "  1.1 GB"
        $sizeBytes = 0L
        foreach ($line in $result) {
            if ($line -match "([\d\.]+)\s*(GB|MB|KB)") {
                $num  = [double]$Matches[1]
                $unit = $Matches[2]
                $sizeBytes = switch ($unit) {
                    "GB" { [long]($num * 1GB) }
                    "MB" { [long]($num * 1MB) }
                    "KB" { [long]($num * 1KB) }
                }
                # 取最大的那个数值（通常是总大小）
            }
        }

        # 如果 winget 没输出大小，从缓存目录找安装包文件大小
        if ($sizeBytes -eq 0) {
            $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalCache\Microsoft.Winget.Source*"
            $tempPath  = "$env:TEMP"
            $recent = Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Extension -in @(".exe",".msi",".msix") } |
                         Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) } |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1
            if ($recent) { $sizeBytes = $recent.Length }
        }

        return @{ Success = $success; SizeBytes = $sizeBytes }
    } -ArgumentList $app

    $lastPct = -1
    $phase   = "Downloading"
    $fakePct = 0
    $dlDone  = $false

    while ($job.State -eq "Running") {
        if (-not $dlDone) {
            $fakePct = [Math]::Min(100, $fakePct + (Get-Random -Min 2 -Max 6))
            if ($fakePct -ge 100) { $dlDone = $true; $fakePct = 0 }
            $phase = "Downloading"
        } else {
            $fakePct = [Math]::Min(99, $fakePct + (Get-Random -Min 3 -Max 8))
            $phase   = "Installing "
        }

        $bucket = [Math]::Floor($fakePct / 10) * 10
        if ($bucket -ne $lastPct -and $bucket -in @(10, 30, 50, 70, 90)) {
            $lastPct = $bucket
            $bar     = Get-Bar -Pct $bucket
            $color   = if ($phase -eq "Downloading") { "Yellow" } else { "Cyan" }
            Write-Host ("      {0,-12} [{1}] {2,3}%" -f $phase, $bar, $bucket) -ForegroundColor $color
        }

        Start-Sleep -Milliseconds 1200
    }

    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed

    # 补全未显示的阶段
    if (-not $dlDone) {
        $bar = Get-Bar -Pct 100
        Write-Host ("      {0,-12} [{1}] 100%" -f "Downloading", $bar) -ForegroundColor Yellow
    }
    $bar = Get-Bar -Pct 100
    Write-Host ("      {0,-12} [{1}] 100%" -f "Installing ", $bar) -ForegroundColor Cyan

    $result    = Receive-Job $job
    Remove-Job $job

    $success   = $result.Success
    $sizeBytes = $result.SizeBytes

    # 格式化时间
    $timeStr = if ($elapsed.TotalMinutes -ge 1) {
        "{0}m {1}s" -f [int]$elapsed.Minutes, [int]$elapsed.Seconds
    } else {
        "{0}s" -f [int]$elapsed.Seconds
    }

    # 格式化大小
    $sizeStr = if ($sizeBytes -gt 0) {
        Format-Bytes $sizeBytes
    } else {
        "unknown"
    }

    if ($success) {
        Write-Host "  [✓] $app — installed successfully. " -NoNewline -ForegroundColor Green
        Write-Host "(Size: $sizeStr, Time: $timeStr)" -ForegroundColor DarkGray
        Write-Host ""
    } else {
        Write-Host "  [✗] $app — installation failed. " -NoNewline -ForegroundColor Red
        Write-Host "(Time: $timeStr)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       All installations complete.    ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan