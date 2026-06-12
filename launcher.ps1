#Requires -Version 5.1
<#
    GamingOptimizer launcher / updater stub
    ---------------------------------------
    Downloads YOUR compiled GamingOptimizer.exe from YOUR GitHub Release, verifies its
    SHA-256, and only runs it if the hash matches. Nothing runs unverified.

    Edit the two values in CONFIG. Get the hash from your build (the GitHub Action prints it
    and saves GamingOptimizer.exe.sha256 next to the exe), or on a Mac:  shasum -a 256 file
#>

# ===================== CONFIG (edit these two) =====================
$ReleaseUrl     = 'https://github.com/aaa1243/optimizer/releases/latest/download/GamingOptimizer.exe'
$ExpectedSha256 = '48c360942125ac65f88584fde4914e47f78eb23e701905d295ac6e389833de05'
# ==================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest much faster on PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Fail($m) { Write-Host "ERROR: $m" -ForegroundColor Red; Write-Host "Press Enter to exit..."; [void](Read-Host); exit 1 }

if ([string]::IsNullOrWhiteSpace($ExpectedSha256) -or $ExpectedSha256 -eq 'PUT_THE_SHA256_OF_YOUR_EXE_HERE') {
    Fail "Set `$ExpectedSha256 to your exe's real SHA-256 first - this stub refuses to run anything unverified."
}
$ExpectedSha256 = $ExpectedSha256.Trim().ToUpper()

$dir  = Join-Path $env:LOCALAPPDATA 'GamingOptimizer'
$dest = Join-Path $dir 'GamingOptimizer.exe'
New-Item -ItemType Directory -Path $dir -Force | Out-Null

# Skip the download if a verified copy is already on disk
$haveGood = $false
if (Test-Path $dest) {
    if ((Get-FileHash $dest -Algorithm SHA256).Hash.ToUpper() -eq $ExpectedSha256) {
        $haveGood = $true
        Write-Host "Existing copy verified - skipping download." -ForegroundColor Green
    }
}

if (-not $haveGood) {
    Write-Host "Downloading: $ReleaseUrl" -ForegroundColor Cyan
    $tmp = "$dest.download"
    try { Invoke-WebRequest -Uri $ReleaseUrl -OutFile $tmp -UseBasicParsing }
    catch { Fail "Download failed: $($_.Exception.Message)" }

    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToUpper()
    if ($actual -ne $ExpectedSha256) {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Fail "HASH MISMATCH - the downloaded file is not what you published. Expected $ExpectedSha256, got $actual. Not running it."
    }
    Move-Item -Path $tmp -Destination $dest -Force
    Write-Host "Downloaded and verified (SHA-256 OK)." -ForegroundColor Green
}

# It's your own verified file, so clear the mark-of-the-web for a clean launch
try { Unblock-File -Path $dest -ErrorAction SilentlyContinue } catch {}

Write-Host "Launching GamingOptimizer.exe ..." -ForegroundColor Cyan
Start-Process -FilePath $dest
