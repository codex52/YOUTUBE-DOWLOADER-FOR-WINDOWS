# ==============================================================================
# Made by Tarek X ChatGPT
# Terminal YouTube Downloader (Windows Native Version)
# ==============================================================================

# Enable Virtual Terminal Processing for ANSI colors
try {
    $MemberDefinition = @'
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
    $type = Add-Type -MemberDefinition $MemberDefinition -Name "Win32Utils" -Namespace "Win32" -PassThru
    $stdOut = $type::GetStdHandle(-11) # STD_OUTPUT_HANDLE
    $mode = 0
    if ($type::GetConsoleMode($stdOut, [ref]$mode)) {
        $type::SetConsoleMode($stdOut, $mode -bor 0x0004) | Out-Null # ENABLE_VIRTUAL_TERMINAL_PROCESSING
    }
} catch {}

# ANSI 256 Colors
$Esc = [char]27
$C_Green = "$Esc[38;5;46m"
$C_Cyan = "$Esc[38;5;51m"
$C_Blue = "$Esc[38;5;39m"
$C_Purple = "$Esc[38;5;129m"
$C_Magenta = "$Esc[38;5;201m"
$C_Orange = "$Esc[38;5;208m"
$C_White = "$Esc[38;5;255m"
$C_Gray = "$Esc[38;5;244m"
$C_Yellow = "$Esc[38;5;226m"
$C_Red = "$Esc[38;5;196m"
$C_Reset = "$Esc[0m"
$C_BG_Green = "$Esc[48;5;46m$Esc[38;5;16m"

# Ensure clean exit and cursor restoration
function Hide-Cursor { Write-Host -NoNewline "$Esc[?25l" }
function Show-Cursor { Write-Host -NoNewline "$Esc[?25h" }

# Safe cleanup block
function Cleanup-Exit {
    Show-Cursor
    Write-Host -NoNewline $C_Reset
    exit 0
}

# Trap Ctrl+C (pipeline break) to clean up terminal state
$global:PROGRESS_DRAWN = $false
$global:MENU_DRAWN = $false

function Get-TermWidth {
    try {
        $w = [Console]::WindowWidth
        if ($w -lt 10) { return 80 }
        return $w
    } catch {
        return 80
    }
}

function Write-Centered {
    param([string]$Text)
    $width = Get-TermWidth
    # Strip ANSI sequences to count clean length
    $cleanText = $Text -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
    $len = $cleanText.Length
    $pad = [math]::Floor(($width - $len) / 2)
    if ($pad -lt 0) { $pad = 0 }
    Write-Host -NoNewline (" " * $pad)
    Write-Host $Text
}

function Draw-BoxHeader {
    param([string]$Title)
    $width = 64
    $termW = Get-TermWidth
    $pad = [math]::Floor(($termW - $width) / 2)
    if ($pad -lt 0) { $pad = 0 }
    
    $line = "─" * ($width - 2)
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Green}╭${line}╮${C_Reset}"
    
    $cleanTitle = $Title -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
    $tLen = $cleanTitle.Length
    $maxTLen = $width - 4
    if ($tLen -gt $maxTLen) {
        $Title = $Title.Substring(0, $maxTLen - 3) + "..."
        $cleanTitle = $Title -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
        $tLen = $cleanTitle.Length
    }
    
    $tPadLeft = [math]::Floor(($width - 2 - $tLen) / 2)
    if ($tPadLeft -lt 0) { $tPadLeft = 0 }
    $tPadRight = $width - 2 - $tLen - $tPadLeft
    if ($tPadRight -lt 0) { $tPadRight = 0 }
    
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Green}│${C_Reset}$(" " * $tPadLeft)${Title}$(" " * $tPadRight)${C_Green}│${C_Reset}"
    
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Green}├${line}┤${C_Reset}"
}

function Draw-BoxLine {
    param([string]$Content)
    $width = 64
    $termW = Get-TermWidth
    $pad = [math]::Floor(($termW - $width) / 2)
    if ($pad -lt 0) { $pad = 0 }
    
    $cleanContent = $Content -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
    $len = $cleanContent.Length
    
    $maxW = $width - 4
    if ($len -gt $maxW) {
        $ansiLen = $Content.Length - $cleanContent.Length
        $rawLimit = $maxW + $ansiLen - 3
        if ($rawLimit -lt 3) { $rawLimit = 3 }
        if ($Content.Length -gt $rawLimit) {
            $Content = $Content.Substring(0, $rawLimit) + "..."
        }
        $cleanContent = $Content -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
        $len = $cleanContent.Length
    }
    
    $padRight = $width - 2 - $len - 1
    if ($padRight -lt 0) { $padRight = 0 }
    
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Green}│${C_Reset} ${Content}$(" " * $padRight)${C_Green}│${C_Reset}"
}

function Draw-BoxFooter {
    $width = 64
    $termW = Get-TermWidth
    $pad = [math]::Floor(($termW - $width) / 2)
    if ($pad -lt 0) { $pad = 0 }
    
    $line = "─" * ($width - 2)
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Green}╰${line}╯${C_Reset}"
}

function Wrap-AndDrawBoxLines {
    param(
        [string]$Label,
        [string]$Text
    )
    $width = 64
    $maxW = $width - 2 - $Label.Length - 2
    $len = $Text.Length
    if ($len -le $maxW) {
        Draw-BoxLine "${Label}${Text}"
    } else {
        $start = 0
        $first = $true
        while ($start -lt $len) {
            $chunkLength = [math]::Min($maxW, $len - $start)
            $chunk = $Text.Substring($start, $chunkLength)
            if ($first) {
                Draw-BoxLine "${Label}${chunk}"
                $first = $false
            } else {
                Draw-BoxLine "$(" " * $Label.Length)${chunk}"
            }
            $start += $maxW
        }
    }
}

$BannerLines = @(
    "╭──────────────────────────────────────────────────────────────╮",
    "│        ████████╗  █████╗  ██████╗  ███████╗ ██╗  ██╗         │",
    "│        ╚══██╔══╝ ██╔══██╗ ██╔══██╗ ██╔════╝ ██║ ██╔╝         │",
    "│           ██║    ███████║ ██████╔╝ █████╗   █████╔╝          │",
    "│           ██║    ██╔══██║ ██╔══██╗ ██╔══╝   ██╔═██╗          │",
    "│           ██║    ██║  ██║ ██║  ██╗ ███████╗ ██║  ██╗         │",
    "│           ╚═╝    ╚═╝  ╚═╝ ╚═╝  ╚═╝ ╚══════╝ ╚═╝  ╚═╝         │",
    "│                                                              │",
    "│                TERMINAL YOUTUBE DOWNLOADER                   │",
    "│                  MADE BY TAREK X ANTIGRAVITY                     │",
    "╰──────────────────────────────────────────────────────────────╯"
)

function Show-HeaderBanner {
    Write-Host -NoNewline "${C_Green}"
    foreach ($line in $BannerLines) {
        Write-Centered $line
    }
    Write-Host ""
}

function Show-Footer {
    $width = 64
    $termW = Get-TermWidth
    $pad = [math]::Floor(($termW - $width) / 2)
    if ($pad -lt 0) { $pad = 0 }
    
    $line = "─" * $width
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Gray}${line}${C_Reset}"
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Gray}                     Made by Tarek X ChatGPT${C_Reset}"
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Gray}                  Powered by yt-dlp + ffmpeg${C_Reset}"
    Write-Host -NoNewline (" " * $pad)
    Write-Host "${C_Gray}${line}${C_Reset}"
}

function Show-StartupAnimation {
    Clear-Host
    Write-Host -NoNewline "${C_Cyan}"
    
    foreach ($line in $BannerLines) {
        Write-Centered $line
        Start-Sleep -Milliseconds 30
    }
    
    Write-Host ""
    Write-Centered "${C_White}[+] INITIALIZING SECURE CYBER-DOWNLINK...${C_Reset}"
    Start-Sleep -Milliseconds 200
    
    Draw-BoxHeader "${C_Green}SYSTEM PORT DEPLOYMENT STATUS${C_Reset}"
    
    # OS Version retrieval (Cross-PS version compatible)
    $osVersion = "Windows"
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $os = Get-CimInstance Win32_OperatingSystem
            $osVersion = "$($os.Caption) ($($os.Version))"
        } else {
            $os = Get-WmiObject Win32_OperatingSystem
            $osVersion = "$($os.Caption) ($($os.Version))"
        }
    } catch {
        $osVersion = [System.Environment]::OSVersion.VersionString
    }
    
    $toolsDir = Join-Path $PSScriptRoot "tools"
    $ytdlpPath = Join-Path $toolsDir "yt-dlp.exe"
    $ffmpegPath = Join-Path $toolsDir "ffmpeg.exe"
    
    $ytdlpVer = "Unknown"
    if (Test-Path $ytdlpPath) {
        try {
            $ytdlpVer = (& $ytdlpPath --version) | Out-String
            $ytdlpVer = $ytdlpVer.Trim()
        } catch {}
    }
    
    $ffmpegVer = "Unknown"
    if (Test-Path $ffmpegPath) {
        try {
            $ffmpegOut = (& $ffmpegPath -version) | Out-String
            if ($ffmpegOut -match 'ffmpeg version ([^\s]+)') {
                $ffmpegVer = $Matches[1]
            }
        } catch {}
    }
    
    $psVersion = $PSVersionTable.PSVersion.ToString()
    
    Draw-BoxLine " Core Architecture: Windows OS ($osVersion)"
    Draw-BoxLine " PowerShell:        v$psVersion"
    Draw-BoxLine " Downloader Daemon: yt-dlp (v$ytdlpVer)"
    Draw-BoxLine " Encoder Protocol:  ffmpeg (v$ffmpegVer)"
    Draw-BoxLine " System Timeframe:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Draw-BoxFooter
    
    Write-Host ""
    Write-Centered "${C_Green}SYSTEM DEPLOYED. PRESS ANY KEY TO DOCK PROTOCOL...${C_Reset}"
    try {
        $null = [Console]::ReadKey($true)
    } catch {
        $null = Read-Host
    }
}

function Show-Spinner {
    param(
        [System.Diagnostics.Process]$Process
    )
    
    $delay = 80
    $spinstr = @('▖', '▘', '▝', '▗')
    $idx = 0
    
    Hide-Cursor
    try {
        while (-not $Process.HasExited) {
            $char = $spinstr[$idx]
            $idx = ($idx + 1) % $spinstr.Length
            Write-Host -NoNewline "${C_Cyan} [$char] Connecting to YouTube mainframe...${C_Reset} `r"
            Start-Sleep -Milliseconds $delay
        }
        Write-Host -NoNewline (" " * 50) + "`r"
    } finally {
        Show-Cursor
    }
}

function Show-DepErrorScreen {
    param([string]$Err)
    Clear-Host
    Show-HeaderBanner
    
    Draw-BoxHeader "${C_Red}✖ DEPLOYMENT FAILURE DETECTED${C_Reset}"
    Draw-BoxLine ""
    Draw-BoxLine "      ${C_Red}╭─────────────────────────────────╮${C_Reset}"
    Draw-BoxLine "      ${C_Red}│        INSTALLATION FAIL        │${C_Reset}"
    Draw-BoxLine "      ${C_Red}│             [ ✖ ] FAIL          │${C_Reset}"
    Draw-BoxLine "      ${C_Red}╰─────────────────────────────────╯${C_Reset}"
    Draw-BoxLine ""
    Wrap-AndDrawBoxLines "Error Detail: " $Err
    Draw-BoxLine "Action Required: Choose Retry to scan again"
    Draw-BoxLine "                 or Exit to terminate."
    Draw-BoxFooter
    Write-Host ""
    Write-Host " Choose an option:"
    Write-Host "  1) Retry scanning and installation"
    Write-Host "  0) Exit"
    Write-Host ""
    
    $choice = ""
    while ($choice -notin @("0", "1")) {
        $choice = (Read-Host " Select option").Trim()
    }
    
    if ($choice -eq "0") {
        Show-CancelScreen
    } else {
        return
    }
}

function Download-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Label
    )
    $webClient = New-Object System.Net.WebClient
    $uri = New-Object System.Uri($Url)
    
    # First, get the total file size via HEAD request
    $totalBytes = -1
    try {
        $headReq = [System.Net.HttpWebRequest]::Create($Url)
        $headReq.Method = "HEAD"
        $headReq.AllowAutoRedirect = $true
        $headReq.UserAgent = "Mozilla/5.0"
        $headResp = $headReq.GetResponse()
        $totalBytes = $headResp.ContentLength
        $headResp.Close()
    } catch {}
    
    $totalMB = if ($totalBytes -gt 0) { "{0:N1} MB" -f ($totalBytes / 1MB) } else { "Unknown" }
    
    # Use HttpWebRequest for streaming download with progress
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.AllowAutoRedirect = $true
    $request.UserAgent = "Mozilla/5.0"
    $response = $request.GetResponse()
    $responseStream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Create($OutFile)
    
    $buffer = New-Object byte[] 65536
    $downloadedBytes = 0
    $lastUpdate = [DateTime]::UtcNow
    
    try {
        while ($true) {
            $bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -eq 0) { break }
            $fileStream.Write($buffer, 0, $bytesRead)
            $downloadedBytes += $bytesRead
            
            $now = [DateTime]::UtcNow
            if (($now - $lastUpdate).TotalMilliseconds -ge 250) {
                $dlMB = "{0:N2} MB" -f ($downloadedBytes / 1MB)
                if ($totalBytes -gt 0) {
                    $pct = [math]::Floor(($downloadedBytes / $totalBytes) * 100)
                    Write-Host -NoNewline "`r ${C_Cyan}[$Label]${C_Reset} ${C_White}${dlMB} / ${totalMB}${C_Reset} (${C_Green}${pct}%${C_Reset})   "
                } else {
                    Write-Host -NoNewline "`r ${C_Cyan}[$Label]${C_Reset} ${C_White}${dlMB}${C_Reset} downloaded...   "
                }
                $lastUpdate = $now
            }
        }
        # Final line
        $dlMB = "{0:N2} MB" -f ($downloadedBytes / 1MB)
        Write-Host "`r ${C_Green}[$Label]${C_Reset} ${C_White}${dlMB} / ${dlMB}${C_Reset} (${C_Green}100%${C_Reset}) - Done!          "
    } finally {
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()
    }
}

function Check-Dependencies {
    $toolsDir = Join-Path $PSScriptRoot "tools"
    if (-not (Test-Path $toolsDir)) {
        New-Item -Path $toolsDir -ItemType Directory | Out-Null
    }
    
    $ytdlpPath = Join-Path $toolsDir "yt-dlp.exe"
    $ffmpegPath = Join-Path $toolsDir "ffmpeg.exe"
    
    $ytdlpStatus = if (Test-Path $ytdlpPath) { "[  ${C_Green}✓ FOUND${C_Reset}  ]" } else { "[ ${C_Red}✗ MISSING${C_Reset} ]" }
    $ffmpegStatus = if (Test-Path $ffmpegPath) { "[  ${C_Green}✓ FOUND${C_Reset}  ]" } else { "[ ${C_Red}✗ MISSING${C_Reset} ]" }
    
    if ((Test-Path $ytdlpPath) -and (Test-Path $ffmpegPath)) {
        return $true
    }
    
    Clear-Host
    Show-HeaderBanner
    Draw-BoxHeader "${C_Cyan}DEPENDENCY SCANNER${C_RESET}"
    Draw-BoxLine " The system requires the following protocols:"
    Draw-BoxLine ""
    Draw-BoxLine "  yt-dlp:    $ytdlpStatus"
    Draw-BoxLine "  ffmpeg:    $ffmpegStatus"
    Draw-BoxLine ""
    Draw-BoxFooter
    Write-Host ""
    
    Write-Host " Install missing packages now?"
    Write-Host "  1) Yes"
    Write-Host "  0) Exit"
    Write-Host ""
    
    $choice = ""
    while ($choice -notin @("0", "1")) {
        $choice = (Read-Host " Select option [0-1]").Trim()
    }
    
    if ($choice -eq "0") {
        Show-CancelScreen
    }
    
    Clear-Host
    Show-HeaderBanner
    Draw-BoxHeader "${C_Cyan}INSTALLATION PROTOCOLS ACTIVE${C_RESET}"
    Draw-BoxLine " Deploying missing dependencies..."
    Draw-BoxLine ""
    
    $totalInstalls = 0
    if (-not (Test-Path $ytdlpPath)) { $totalInstalls++ }
    if (-not (Test-Path $ffmpegPath)) { $totalInstalls++ }
    
    $currentStep = 1
    
    if (-not (Test-Path $ytdlpPath)) {
        Draw-BoxLine "  [$currentStep/$totalInstalls] Downloading yt-dlp.exe..."
        Draw-BoxFooter
        Write-Host ""
        
        $ytdlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        try {
            Write-Host "${C_Cyan}Connecting to GitHub release server...${C_Reset}"
            Download-FileWithProgress -Url $ytdlpUrl -OutFile $ytdlpPath -Label "yt-dlp"
            Write-Host "${C_Green}✔ yt-dlp installation complete.${C_Reset}"
        } catch {
            Show-DepErrorScreen "Failed to download yt-dlp: $_"
            return $false
        }
        $currentStep++
        
        Clear-Host
        Show-HeaderBanner
        Draw-BoxHeader "${C_Cyan}INSTALLATION PROTOCOLS ACTIVE${C_RESET}"
        Draw-BoxLine " Deploying missing dependencies..."
        Draw-BoxLine ""
        Draw-BoxLine "  ✔ yt-dlp installation complete."
    }
    
    if (-not (Test-Path $ffmpegPath)) {
        Draw-BoxLine "  [$currentStep/$totalInstalls] Downloading ffmpeg binaries..."
        Draw-BoxFooter
        Write-Host ""
        
        $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        $zipPath = Join-Path $toolsDir "ffmpeg.zip"
        $extractDir = Join-Path $toolsDir "ffmpeg_temp"
        
        try {
            Write-Host "${C_Cyan}Downloading ffmpeg archive (this might take a moment)...${C_Reset}"
            Download-FileWithProgress -Url $ffmpegUrl -OutFile $zipPath -Label "ffmpeg"
            
            Write-Host "${C_Cyan}Extracting ffmpeg binaries...${C_Reset}"
            if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force | Out-Null }
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
            
            $foundFfmpeg = Get-ChildItem -Path $extractDir -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
            if ($foundFfmpeg) {
                Copy-Item -Path $foundFfmpeg.FullName -Destination $ffmpegPath -Force
            } else {
                throw "ffmpeg.exe not found inside the downloaded archive."
            }
            
            $foundFfprobe = Get-ChildItem -Path $extractDir -Filter "ffprobe.exe" -Recurse | Select-Object -First 1
            if ($foundFfprobe) {
                Copy-Item -Path $foundFfprobe.FullName -Destination (Join-Path $toolsDir "ffprobe.exe") -Force
            }
            
            Remove-Item -Path $zipPath -Force | Out-Null
            Remove-Item -Path $extractDir -Recurse -Force | Out-Null
            
            Write-Host "${C_Green}✔ ffmpeg installation complete.${C_Reset}"
        } catch {
            if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force | Out-Null }
            if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force | Out-Null }
            Show-DepErrorScreen "Failed to download/install ffmpeg: $_"
            return $false
        }
    }
    
    Draw-BoxLine ""
    Draw-BoxLine " All dependencies installed successfully."
    Draw-BoxLine " Restarting Downloader..."
    Draw-BoxFooter
    Write-Host ""
    Start-Sleep -Seconds 2
    return $true
}

function Check-ForYtdlpUpdates {
    $toolsDir = Join-Path $PSScriptRoot "tools"
    $ytdlpPath = Join-Path $toolsDir "yt-dlp.exe"
    
    if (-not (Test-Path $ytdlpPath)) { return }
    
    Write-Host -NoNewline " Checking for yt-dlp updates..."
    
    $latestVer = ""
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest" -TimeoutSec 3 -UseBasicParsing
        $latestVer = $response.tag_name
    } catch {
        Write-Host " [Skipped: Network Offline]"
        Start-Sleep -Seconds 1
        return
    }
    
    if ([string]::IsNullOrEmpty($latestVer)) {
        Write-Host " [Skipped: Version Check Failed]"
        Start-Sleep -Seconds 1
        return
    }
    
    $currentVer = ""
    try {
        $currentVer = (& $ytdlpPath --version) | Out-String
        $currentVer = $currentVer.Trim()
    } catch {}
    
    $cleanLatest = $latestVer -replace "^v", ""
    $cleanCurrent = $currentVer -replace "^v", ""
    
    if ($cleanLatest -ne $cleanCurrent) {
        Clear-Host
        Show-HeaderBanner
        Draw-BoxHeader "${C_Cyan}SOFTWARE UPDATE PROTOCOL${C_Reset}"
        Draw-BoxLine " A new yt-dlp version is available."
        Draw-BoxLine ""
        Draw-BoxLine "  Installed version: v${cleanCurrent}"
        Draw-BoxLine "  Latest release:    v${cleanLatest}"
        Draw-BoxLine ""
        Draw-BoxFooter
        Write-Host ""
        Write-Host " Update yt-dlp now?"
        Write-Host "  1) Yes (Recommended)"
        Write-Host "  2) Skip"
        Write-Host ""
        
        $choice = ""
        while ($choice -notin @("1", "2")) {
            $choice = (Read-Host " Select option [1-2]").Trim()
        }
        
        if ($choice -eq "2") {
            return
        }
        
        Clear-Host
        Show-HeaderBanner
        Draw-BoxHeader "${C_Cyan}UPGRADING YT-DLP DAEMON${C_Reset}"
        Draw-BoxLine " Running upgrade protocols..."
        Draw-BoxFooter
        Write-Host ""
        
        try {
            Write-Host "${C_Cyan}Downloading latest yt-dlp release...${C_Reset}"
            $ytdlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
            $tempYtdlp = Join-Path $toolsDir "yt-dlp.tmp"
            Invoke-WebRequest -Uri $ytdlpUrl -OutFile $tempYtdlp -UseBasicParsing
            
            if (Test-Path $ytdlpPath) { Remove-Item -Path $ytdlpPath -Force }
            Rename-Item -Path $tempYtdlp -NewName "yt-dlp.exe" -Force
            
            $newVer = (& $ytdlpPath --version) | Out-String
            $newVer = $newVer.Trim()
            
            Clear-Host
            Show-HeaderBanner
            Draw-BoxHeader "${C_Green}✔ UPGRADE COMPLETE${C_Reset}"
            Draw-BoxLine " yt-dlp successfully updated to v${newVer}."
            Draw-BoxLine " Resuming main protocols..."
            Draw-BoxFooter
            Write-Host ""
            Start-Sleep -Milliseconds 1500
        } catch {
            Show-DepErrorScreen "Failed to upgrade yt-dlp: $_"
        }
    } else {
        Write-Host " [Up-to-date]"
        Start-Sleep -Milliseconds 500
    }
}

function Display-VideoInfoPanel {
    param(
        [string]$Title,
        [string]$Uploader,
        [string]$Duration,
        [string]$Views,
        [string]$UploadDate,
        [string]$Resolution,
        [string]$Thumbnail
    )
    
    $formattedViews = $Views
    if ($Views -match '^\d+$') {
        $vVal = [double]$Views
        if ($vVal -ge 1000000) {
            $formattedViews = "{0:N1}M views" -f ($vVal / 1000000)
        } elseif ($vVal -ge 1000) {
            $formattedViews = "{0:N1}k views" -f ($vVal / 1000)
        } else {
            $formattedViews = "$Views views"
        }
    }
    
    $formattedDate = "Unknown"
    if ($UploadDate.Length -eq 8) {
        $formattedDate = "$($UploadDate.Substring(0,4))-$($UploadDate.Substring(4,2))-$($UploadDate.Substring(6,2))"
    } else {
        $formattedDate = $UploadDate
    }
    
    Clear-Host
    Show-HeaderBanner
    
    Draw-BoxHeader "${C_Cyan}TARGET ACQUIRED: VIDEO METADATA${C_Reset}"
    Wrap-AndDrawBoxLines "Title:  " $Title
    Draw-BoxLine "Channel:    $Uploader"
    Draw-BoxLine "Duration:   $Duration"
    Draw-BoxLine "Views:      $formattedViews"
    Draw-BoxLine "Released:   $formattedDate"
    Draw-BoxLine "Source Res: $Resolution"
    
    $cleanThumb = $Thumbnail
    if ($cleanThumb.Length -gt 48) {
        $cleanThumb = $cleanThumb.Substring(0, 45) + "..."
    }
    Draw-BoxLine "Thumbnail:  $cleanThumb"
    Draw-BoxFooter
    Write-Host ""
}

function Draw-MenuState {
    param(
        [int]$Selected,
        [int]$TotalOptions,
        [array]$HeightArr
    )
    
    global:variable MENU_DRAWN
    if ($global:MENU_DRAWN) {
        $linesToMove = 4 + $TotalOptions
        Write-Host -NoNewline "$Esc[$(${linesToMove})A"
    }
    $global:MENU_DRAWN = $true
    
    Draw-BoxHeader "${C_Cyan}AVAILABLE RESOLUTIONS${C_Reset}"
    
    for ($idx = 0; $idx -lt $TotalOptions; $idx++) {
        $lineContent = ""
        if ($idx -eq ($TotalOptions - 1)) {
            $lineContent = " 0) Cancel"
        } elseif ($idx -eq ($TotalOptions - 2)) {
            $lineContent = " $($idx + 1)) Best Audio (MP3)"
        } else {
            $h = $HeightArr[$idx]
            $label = "${h}p"
            if ($h -eq 2160) {
                $label = "2160p (4K)"
            } elseif ($h -eq 1440) {
                $label = "1440p"
            }
            $lineContent = " $($idx + 1)) $label"
        }
        
        if ($idx -eq $Selected) {
            Draw-BoxLine "${C_BG_Green}  ${lineContent}  ${C_Reset}"
        } else {
            Draw-BoxLine "  ${lineContent}"
        }
    }
    
    Draw-BoxFooter
}

function Select-Menu {
    param(
        [int]$TotalOptions,
        [array]$HeightArr
    )
    
    $selected = 0
    $global:MENU_DRAWN = $false
    
    Hide-Cursor
    try {
        while ($true) {
            Draw-MenuState -Selected $selected -TotalOptions $TotalOptions -HeightArr $HeightArr
            
            $keyInfo = $null
            $readFailed = $false
            try {
                $keyInfo = [Console]::ReadKey($true)
            } catch {
                $readFailed = $true
            }
            
            if ($readFailed) {
                Show-Cursor
                Write-Host -NoNewline "${C_Cyan} Enter Selection (e.g. 1, 2, 0 for cancel): ${C_Reset}"
                $inputVal = Read-Host
                if ($null -eq $inputVal) { return $TotalOptions - 1 }
                $inputVal = $inputVal.Trim()
                $num = 0
                if ([int]::TryParse($inputVal, [ref]$num)) {
                    if ($num -eq 0) {
                        return $TotalOptions - 1
                    } elseif ($num -gt 0 -and $num -lt $TotalOptions) {
                        return $num - 1
                    }
                }
                return $TotalOptions - 1
            }
            
            $key = $keyInfo.Key
            
            if ($key -eq [ConsoleKey]::UpArrow) {
                $selected = ($selected - 1 + $TotalOptions) % $TotalOptions
            } elseif ($key -eq [ConsoleKey]::DownArrow) {
                $selected = ($selected + 1) % $TotalOptions
            } elseif ($key -eq [ConsoleKey]::Enter) {
                Show-Cursor
                return $selected
            } elseif ($key -ge [ConsoleKey]::D0 -and $key -le [ConsoleKey]::D9) {
                $num = [int]$key - [int][ConsoleKey]::D0
                if ($num -eq 0) {
                    $selected = $TotalOptions - 1
                } else {
                    $idx = $num - 1
                    if ($idx -lt ($TotalOptions - 1)) {
                        $selected = $idx
                    }
                }
                Draw-MenuState -Selected $selected -TotalOptions $TotalOptions -HeightArr $HeightArr
                Start-Sleep -Milliseconds 150
                Show-Cursor
                return $selected
            } elseif ($key -ge [ConsoleKey]::NumPad0 -and $key -le [ConsoleKey]::NumPad9) {
                $num = [int]$key - [int][ConsoleKey]::NumPad0
                if ($num -eq 0) {
                    $selected = $TotalOptions - 1
                } else {
                    $idx = $num - 1
                    if ($idx -lt ($TotalOptions - 1)) {
                        $selected = $idx
                    }
                }
                Draw-MenuState -Selected $selected -TotalOptions $TotalOptions -HeightArr $HeightArr
                Start-Sleep -Milliseconds 150
                Show-Cursor
                return $selected
            }
        }
    } finally {
        Show-Cursor
    }
}

function Generate-Blocks {
    param(
        [char]$Char,
        [int]$Count
    )
    if ($Count -le 0) { return "" }
    return [string]$Char * $Count
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -lt 0) { return "Unknown" }
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes B"
    }
}

function Draw-ProgressUI {
    param(
        [string]$Percent,
        [string]$Speed,
        [string]$Eta,
        [string]$TotalSize,
        [string]$DlSize,
        [string]$RemainingSize,
        [string]$Filename,
        [string]$Resolution
    )
    
    global:variable PROGRESS_DRAWN
    if ($global:PROGRESS_DRAWN) {
        Write-Host -NoNewline "$Esc[8A"
    }
    $global:PROGRESS_DRAWN = $true
    
    Draw-BoxHeader "${C_Cyan}DOWNLOADING MEDIA PROTOCOL${C_Reset}"
    
    $cleanFn = $Filename
    if ($cleanFn.Length -gt 40) {
        $cleanFn = $cleanFn.Substring(0, 37) + "..."
    }
    Draw-BoxLine " File:       $cleanFn"
    Draw-BoxLine " Res/Type:   $Resolution   Speed: $Speed"
    
    $percentVal = 0.0
    if ($Percent -match '^\d+(\.\d+)?$') {
        $percentVal = [double]$Percent
    }
    $percentInt = [int][math]::Floor($percentVal)
    
    $filled = [int][math]::Floor($percentInt * 30 / 100)
    $empty = 30 - $filled
    
    $barFilled = Generate-Blocks -Char "█" -Count $filled
    $barEmpty = Generate-Blocks -Char "░" -Count $empty
    
    $barColor = $C_Orange
    if ($percentInt -ge 70) {
        $barColor = $C_Green
    } elseif ($percentInt -ge 30) {
        $barColor = $C_Cyan
    }
    
    Draw-BoxLine " [${barColor}${barFilled}${C_Gray}${barEmpty}${C_Reset}] ${barColor}${Percent}%${C_Reset}"
    Draw-BoxLine " Bytes info: $DlSize of $TotalSize (Remaining: $RemainingSize)   ETA: $Eta"
    Draw-BoxFooter
}

function Draw-StatusMsg {
    param([string]$Line)
    if ($Line -match 'Merging|Merging formats|\[Merger\]') {
        global:variable PROGRESS_DRAWN
        if ($global:PROGRESS_DRAWN) {
            Write-Host -NoNewline "$Esc[8A"
        }
        $global:PROGRESS_DRAWN = $true
        
        Draw-BoxHeader "${C_Purple}POST-PROCESSING PROTOCOL${C_RESET}"
        Draw-BoxLine "  ${C_Yellow}⚡ Merging video and audio streams via FFMPEG...${C_Reset}"
        Draw-BoxLine "  Please wait, compiling final MP4 container..."
        Draw-BoxLine ""
        Draw-BoxLine ""
        Draw-BoxFooter
    }
}

function Show-SuccessScreen {
    param(
        [string]$TargetTitle,
        [string]$Res,
        [string]$DlTime,
        [bool]$IsAudio,
        [string]$TargetFolder
    )
    
    $ext = if ($IsAudio) { "mp3" } else { "mp4" }
    $finalPath = ""
    $fSize = "Unknown"
    $fName = $TargetTitle
    
    try {
        $files = Get-ChildItem -Path $TargetFolder -Filter "*.$ext" | Sort-Object LastWriteTime -Descending
        foreach ($f in $files) {
            $finalPath = $f.FullName
            $fName = $f.Name
            $sizeInBytes = $f.Length
            if ($sizeInBytes -ge 1GB) {
                $fSize = "{0:N2} GB" -f ($sizeInBytes / 1GB)
            } elseif ($sizeInBytes -ge 1MB) {
                $fSize = "{0:N2} MB" -f ($sizeInBytes / 1MB)
            } else {
                $fSize = "{0:N2} KB" -f ($sizeInBytes / 1KB)
            }
            break
        }
    } catch {}
    
    Clear-Host
    Show-HeaderBanner
    
    Draw-BoxHeader "${C_Green}✔ DOWNLOAD COMPLETED SUCCESSFULLY${C_Reset}"
    Draw-BoxLine ""
    Draw-BoxLine "      ${C_Green}╭─────────────────────────────────╮${C_Reset}"
    Draw-BoxLine "      ${C_Green}│          DOWNLOAD COMPLETE      │${C_Reset}"
    Draw-BoxLine "      ${C_Green}│             [ ✔ ] SUCCESS       │${C_Reset}"
    Draw-BoxLine "      ${C_Green}╰─────────────────────────────────╯${C_Reset}"
    Draw-BoxLine ""
    Wrap-AndDrawBoxLines "File Name:  " $fName
    Draw-BoxLine "Location:   Downloads\SUPER HUMAN"
    Draw-BoxLine "Final Size: $fSize"
    Draw-BoxLine "Resolution: $Res"
    Draw-BoxLine "Time Taken: $DlTime"
    Draw-BoxFooter
    
    Show-Footer
    Write-Host ""
    Write-Host -NoNewline " Press ENTER to return to Main Menu..."
    $null = [Console]::ReadLine()
}

function Show-ErrorScreen {
    param([string]$Err)
    Clear-Host
    Show-HeaderBanner
    
    Draw-BoxHeader "${C_Red}✖ SYSTEM EXCEPTION DETECTED${C_Reset}"
    Draw-BoxLine ""
    Draw-BoxLine "      ${C_Red}╭─────────────────────────────────╮${C_Reset}"
    Draw-BoxLine "      ${C_Red}│          CRITICAL ERROR         │${C_Reset}"
    Draw-BoxLine "      ${C_Red}│             [ ✖ ] FAIL          │${C_Reset}"
    Draw-BoxLine "      ${C_Red}╰─────────────────────────────────╯${C_Reset}"
    Draw-BoxLine ""
    Wrap-AndDrawBoxLines "Error Msg:  " $Err
    Draw-BoxLine "Suggestion: Check connection, URL validity,"
    Draw-BoxLine "            or video privacy settings."
    Draw-BoxFooter
    
    Show-Footer
    Write-Host ""
    Write-Host -NoNewline " Press ENTER to return to Main Menu..."
    $null = [Console]::ReadLine()
}

function Show-CancelScreen {
    Clear-Host
    Show-HeaderBanner
    
    Draw-BoxHeader "${C_Cyan}TERMINATING DOWNLINK PROTOCOL${C_Reset}"
    Draw-BoxLine ""
    Draw-BoxLine "      [+] Disconnecting core downloads..."
    Draw-BoxLine "      [+] Reclaiming system memory buffers..."
    Draw-BoxLine "      [+] YouTube downloader offline."
    Draw-BoxLine ""
    Draw-BoxFooter
    Write-Host ""
    Start-Sleep -Milliseconds 800
    Cleanup-Exit
}

function Show-UrlPrompt {
    Clear-Host
    Show-HeaderBanner
    
    Draw-BoxHeader "${C_Green}INITIALIZE SECURE DOWNLINK${C_Reset}"
    Draw-BoxLine " Paste video URL below to fetch metadata."
    Draw-BoxLine " Enter '0' to exit the downloader."
    Draw-BoxFooter
    Write-Host ""
    Write-Host -NoNewline " ${C_Cyan}⚡ SYSTEM-URL > ${C_Reset}"
}

# Ensure tools directory & execute checks
$toolsDir = Join-Path $PSScriptRoot "tools"
$ytdlpPath = Join-Path $toolsDir "yt-dlp.exe"
$ffmpegPath = Join-Path $toolsDir "ffmpeg.exe"

# Execution policy status check
$policy = Get-ExecutionPolicy -ErrorAction SilentlyContinue
if ($policy -eq "Restricted") {
    Write-Host "${C_Yellow}Friendly Guide: PowerShell scripts are currently blocked on this machine (ExecutionPolicy Restricted).${C_Reset}"
    Write-Host "${C_Yellow}To solve this, double click the 'run.bat' wrapper file, which bypasses this restriction automatically.${C_Reset}"
    Write-Host "${C_Yellow}Or run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass to execute scripts this session.${C_Reset}"
    Write-Host ""
}

try {
    Show-StartupAnimation
    
    while (-not (Check-Dependencies)) {
        Start-Sleep -Milliseconds 500
    }
    
    Check-ForYtdlpUpdates
    
    $downloadsFolder = [System.IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'Downloads')
    $targetFolder = [System.IO.Path]::Combine($downloadsFolder, 'SUPER HUMAN')
    if (-not (Test-Path $targetFolder)) {
        New-Item -Path $targetFolder -ItemType Directory | Out-Null
    }
    
    while ($true) {
        Show-UrlPrompt
        $url = Read-Host
        if ($null -eq $url) { continue }
        $url = $url.Trim()
        
        if ([string]::IsNullOrEmpty($url)) {
            continue
        }
        
        if ($url -eq "0") {
            Show-CancelScreen
        }
        
        if ($url -notmatch '(youtube\.com|youtu\.be)') {
            Show-ErrorScreen "Invalid YouTube URL format."
            continue
        }
        
        Clear-Host
        Show-HeaderBanner
        
        # Start fetch metadata process asynchronously with spinner
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ytdlpPath
        $psi.Arguments = "--skip-download --print ""%(title)s###YT_DELIM###%(uploader)s###YT_DELIM###%(duration_string)s###YT_DELIM###%(view_count)s###YT_DELIM###%(upload_date)s###YT_DELIM###%(resolution)s###YT_DELIM###%(thumbnail)s###YT_DELIM###%(formats.:.height)s"" ""$url"""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        
        try {
            $proc.Start() | Out-Null
        } catch {
            Show-ErrorScreen "Failed to launch yt-dlp engine."
            continue
        }
        
        Show-Spinner -Process $proc
        
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $status = $proc.ExitCode
        
        if ($status -ne 0 -or [string]::IsNullOrEmpty($stdout)) {
            $errMsg = "Failed connection or private video."
            if ($stderr -match "ERROR:\s*(.*)") {
                $errMsg = $Matches[1].Trim()
            } elseif ($stdout -match "ERROR:\s*(.*)") {
                $errMsg = $Matches[1].Trim()
            }
            Show-ErrorScreen $errMsg
            continue
        }
        
        $parts = $stdout -split "###YT_DELIM###"
        if ($parts.Length -lt 8) {
            Show-ErrorScreen "Failed parsing metadata response."
            continue
        }
        
        $title = $parts[0].Trim()
        $uploader = $parts[1].Trim()
        $duration = $parts[2].Trim()
        $views = $parts[3].Trim()
        $uploadDate = $parts[4].Trim()
        $resolution = $parts[5].Trim()
        $thumbnail = $parts[6].Trim()
        $heightsRaw = $parts[7].Trim()
        
        # Parse heights cleanly
        $heightsRawClean = $heightsRaw -replace '[\[\]\s]', ''
        $heightsList = $heightsRawClean -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Descending -Unique
        
        if ($heightsList.Count -eq 0) {
            Show-ErrorScreen "No video heights/resolutions found."
            continue
        }
        
        Display-VideoInfoPanel -Title $title -Uploader $uploader -Duration $duration -Views $views -UploadDate $uploadDate -Resolution $resolution -Thumbnail $thumbnail
        
        $numHeights = $heightsList.Count
        $totalOptions = $numHeights + 2
        
        $choiceIdx = Select-Menu -TotalOptions $totalOptions -HeightArr $heightsList
        
        if ($choiceIdx -eq ($totalOptions - 1)) {
            # Cancel option
            continue
        }
        
        Clear-Host
        Show-HeaderBanner
        
        $outTemplate = Join-Path $targetFolder "%(title)s.%(ext)s"
        $isAudio = $false
        $selectedRes = ""
        $argsList = @()
        
        if ($choiceIdx -eq ($totalOptions - 2)) {
            $selectedRes = "MP3 Audio"
            $isAudio = $true
            $argsList = @(
                "--newline",
                "--progress-template", "PROG:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress.total_bytes)s|%(progress.downloaded_bytes)s|%(progress.total_bytes_estimate)s",
                "-x", "--audio-format", "mp3", "--audio-quality", "0",
                "-o", $outTemplate,
                $url
            )
        } else {
            $selectedHeight = $heightsList[$choiceIdx]
            $selectedRes = "${selectedHeight}p"
            $argsList = @(
                "--newline",
                "--progress-template", "PROG:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress.total_bytes)s|%(progress.downloaded_bytes)s|%(progress.total_bytes_estimate)s",
                "-f", "bestvideo[height=$selectedHeight][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height=$selectedHeight]+bestaudio/best[height=$selectedHeight]",
                "--merge-output-format", "mp4", "--remux-video", "mp4",
                "-o", $outTemplate,
                $url
            )
        }
        
        # Escape arguments for Windows CommandLine
        $escapedArgs = @()
        foreach ($arg in $argsList) {
            if ($arg -match '\s') {
                $escapedArgs += """$arg"""
            } else {
                $escapedArgs += $arg
            }
        }
        $argsString = $escapedArgs -join " "
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ytdlpPath
        $psi.Arguments = $argsString
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        
        $startTime = [DateTime]::UtcNow
        $global:PROGRESS_DRAWN = $false
        $currentFile = "Starting download..."
        
        try {
            $proc.Start() | Out-Null
        } catch {
            Show-ErrorScreen "Failed to launch download stream."
            continue
        }
        
        $reader = $proc.StandardOutput
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($line)) { continue }
            
            if ($line -match 'Destination:\s*(.*)') {
                $currentFile = [System.IO.Path]::GetFileName($Matches[1])
            } elseif ($line -match 'PROG:(.*)') {
                $data = $Matches[1]
                $fields = $data -split '\|'
                if ($fields.Length -ge 6) {
                    $percent = $fields[0] -replace '[\s%]', ''
                    $speed = $fields[1].Trim()
                    $eta = $fields[2].Trim()
                    $totalBytesRaw = $fields[3].Trim()
                    $dlBytesRaw = $fields[4].Trim()
                    $estBytesRaw = $fields[5].Trim()
                    
                    $totalBytes = -1
                    if ($totalBytesRaw -match '^\d+$') {
                        $totalBytes = [double]$totalBytesRaw
                    } elseif ($estBytesRaw -match '^\d+$') {
                        $totalBytes = [double]$estBytesRaw
                    }
                    
                    $dlBytes = 0.0
                    if ($dlBytesRaw -match '^\d+$') {
                        $dlBytes = [double]$dlBytesRaw
                    }
                    
                    $remainingBytes = -1
                    if ($totalBytes -gt 0) {
                        $remainingBytes = $totalBytes - $dlBytes
                    }
                    
                    $totalSizeStr = if ($totalBytes -gt 0) { Format-Bytes $totalBytes } else { "Unknown" }
                    $dlSizeStr = Format-Bytes $dlBytes
                    $remainingStr = if ($remainingBytes -ge 0) { Format-Bytes $remainingBytes } else { "Unknown" }
                    
                    Draw-ProgressUI -Percent $percent -Speed $speed -Eta $eta -TotalSize $totalSizeStr -DlSize $dlSizeStr -RemainingSize $remainingStr -Filename $currentFile -Resolution $selectedRes
                }
            } else {
                Draw-StatusMsg -Line $line
            }
        }
        
        $proc.WaitForExit()
        $dlStatus = $proc.ExitCode
        
        $endTime = [DateTime]::UtcNow
        $durationSec = [math]::Round(($endTime - $startTime).TotalSeconds)
        if ($durationSec -lt 1) { $durationSec = 1 }
        $downloadTime = "$durationSec seconds"
        
        if ($dlStatus -eq 0) {
            Show-SuccessScreen -TargetTitle $title -Res $selectedRes -DlTime $downloadTime -IsAudio $isAudio -TargetFolder $targetFolder
        } else {
            Show-ErrorScreen "Download protocol interrupted (Exit code $dlStatus)."
        }
    }
} catch {
    Write-Host ""
    Write-Host "${C_Red}✖ CRITICAL ENGINE EXCEPTION DETECTED${C_Reset}"
    Write-Host "${C_Red}$_${C_Reset}"
    Write-Host ""
    Write-Host "Stack Trace:"
    Write-Host $_.ScriptStackTrace
    Write-Host ""
    Write-Host "Press ENTER to terminate protocol..."
    $null = [Console]::ReadLine()
} finally {
    Cleanup-Exit
}
