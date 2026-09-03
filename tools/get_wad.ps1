# ============================================================================
# File: get_wad.ps1
# Description: Downloads legal DOOM Shareware IWAD (doom1.wad) for bare-metal play
# ============================================================================

$DestinationDir = "$PSScriptRoot/../sw/doom"
$DestinationFile = "$DestinationDir/doom1.wad"

if (-not (Test-Path $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
}

if (Test-Path $DestinationFile) {
    Write-Host "doom1.wad already exists at: $DestinationFile" -ForegroundColor Green
    exit 0
}

Write-Host "=================================================================="
Write-Host "  Fetching DOOM Shareware IWAD (doom1.wad, ~4.19 MB)...           "
Write-Host "=================================================================="

$Urls = @(
    "https://distro.ibiblio.org/pub/linux/distributions/gentoo/distfiles/doom1.wad",
    "https://archive.org/download/doom-1-shareware/DOOM1.WAD",
    "https://www.jbserver.com/downloads/games/doom/misc/shareware/doom1.wad"
)

$Downloaded = $false
foreach ($Url in $Urls) {
    try {
        Write-Host "Attempting download from: $Url"
        Invoke-WebRequest -Uri $Url -OutFile $DestinationFile -TimeoutSec 30
        if ((Get-Item $DestinationFile).Length -ge 4000000) {
            $Downloaded = $true
            break
        }
    } catch {
        Write-Warning "Download from $Url failed: $_"
    }
}

if ($Downloaded) {
    $Size = (Get-Item $DestinationFile).Length
    Write-Host "=================================================================="
    Write-Host "  Successfully downloaded doom1.wad ($Size bytes)                 "
    Write-Host "  Saved to: $DestinationFile                                      "
    Write-Host "=================================================================="
} else {
    Write-Error "Failed to download doom1.wad automatically. Please manually place doom1.wad into $DestinationDir"
    exit 1
}
