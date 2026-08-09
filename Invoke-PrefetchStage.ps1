<#
.SYNOPSIS
    Downloads and stages a file described by a BigFix prefetch statement.

.DESCRIPTION
    Parses a prefetch line, downloads the file, verifies SHA1, SHA256 (optional),
    and size, then places the file at <DestinationRoot>\<sha1>\<filename> — matching
    the layout expected by CustomRepository / rewritePrefetchUrls() in fixlet_dispatcher.ojo.

    If -DestinationRoot is not supplied, it is resolved from the registry:
        HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server -> wwwRootFolder
        + "\Uploads\CustomRepository\SoftwarePortal"
    matching the path the BES root server serves at
        http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/<sha1>/<filename>

    Safe to re-run: if the destination file already exists and its SHA1 matches the
    expected hash, the download is skipped (exit 0).

.PARAMETER PrefetchLine
    A BigFix prefetch statement, e.g.:
        prefetch Setup.exe sha1:abc123 size:1048576 https://example.com/Setup.exe sha256:def456

.PARAMETER DestinationRoot
    Optional. Overrides the registry-derived CustomRepository path — mainly for manual
    testing away from the BES root server.

.EXAMPLE
    .\Invoke-PrefetchStage.ps1 "prefetch Setup.exe sha1:abc123 size:1048576 https://example.com/Setup.exe sha256:def456"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
    [string]$PrefetchLine,

    [Parameter(Position = 1)]
    [string]$DestinationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Parse — 'prefetch' keyword is optional so the script accepts a raw matched line too
$pattern = '^(?:prefetch\s+)?(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:(\d+)\s+(\S+)(?:\s+sha256:([0-9a-fA-F]+))?'
if ($PrefetchLine -notmatch $pattern) {
    Write-Error "Cannot parse prefetch line.`nExpected: prefetch <file> sha1:<hash> size:<bytes> <url> [sha256:<hash>]"
    exit 1
}

$fileName       = $Matches[1]
$sha1Expected   = $Matches[2].ToUpper()
$sizeExpected   = [long]$Matches[3]
$url            = $Matches[4]
$sha256Expected = if ($Matches[5]) { $Matches[5].ToUpper() } else { $null }

Write-Host "File   : $fileName"
Write-Host "SHA1   : $sha1Expected"
Write-Host "Size   : $sizeExpected bytes"
Write-Host "URL    : $url"
if ($sha256Expected) { Write-Host "SHA256 : $sha256Expected" }

# Resolve destination root — explicit override wins, otherwise derive from the BES
# web root registered by the Enterprise Server (matches the path it serves over HTTP).
if (-not $DestinationRoot) {
    $regPath = 'HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server'
    $regProp = Get-ItemProperty -Path $regPath -Name 'wwwRootFolder' -ErrorAction Stop
    $wwwRoot = $regProp.wwwRootFolder
    if (-not $wwwRoot) {
        Write-Error "Registry value 'wwwRootFolder' at '$regPath' is empty."
        exit 1
    }
    $DestinationRoot = Join-Path $wwwRoot 'Uploads\CustomRepository\SoftwarePortal'
}
Write-Host "Target : $DestinationRoot"

# Create <sha1>/<filename> directory structure (sha1 in lowercase — BigFix CustomRepository paths use lowercase)
$sha1Dir  = $sha1Expected.ToLower()
$outDir   = Join-Path $DestinationRoot $sha1Dir
$destPath = Join-Path $outDir $fileName

# Idempotent: if it's already staged and verified, there's nothing to do.
if (Test-Path $destPath) {
    $existingSha1 = (Get-FileHash $destPath -Algorithm SHA1).Hash
    if ($existingSha1 -eq $sha1Expected) {
        Write-Host "`n[SKIP] Already staged and verified: $destPath"
        exit 0
    }
    Write-Host "`n[STALE] Existing file hash mismatch — re-downloading."
    Remove-Item $destPath -Force
}

# Download to a temp path
$tempPath = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
Write-Host "`nDownloading..."
try {
    Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing
} catch {
    Write-Error "Download failed: $_"
    exit 1
}

# Size check
$actualSize = (Get-Item $tempPath).Length
if ($actualSize -ne $sizeExpected) {
    Remove-Item $tempPath -Force
    Write-Error "Size mismatch: expected $sizeExpected bytes, got $actualSize bytes."
    exit 1
}
Write-Host "Size   : OK ($actualSize bytes)"

# SHA1 check
$sha1Actual = (Get-FileHash $tempPath -Algorithm SHA1).Hash
if ($sha1Actual -ne $sha1Expected) {
    Remove-Item $tempPath -Force
    Write-Error "SHA1 mismatch:`n  expected : $sha1Expected`n  actual   : $sha1Actual"
    exit 1
}
Write-Host "SHA1   : OK"

# SHA256 check (optional)
if ($sha256Expected) {
    $sha256Actual = (Get-FileHash $tempPath -Algorithm SHA256).Hash
    if ($sha256Actual -ne $sha256Expected) {
        Remove-Item $tempPath -Force
        Write-Error "SHA256 mismatch:`n  expected : $sha256Expected`n  actual   : $sha256Actual"
        exit 1
    }
    Write-Host "SHA256 : OK"
}

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

Move-Item -Path $tempPath -Destination $destPath -Force
Write-Host "`nStaged : $destPath"
exit 0
