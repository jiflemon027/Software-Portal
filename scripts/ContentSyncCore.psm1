#Requires -Version 5.1
<#
.SYNOPSIS
    Pure, side-effect-free building blocks for the content pipeline (07-03):
    Invoke-ContentSync.ps1 (source-site scan, version diff, 4-step copy, X-Superseded-By
    stamp) and Stage-Repository.ps1 (prefetch-line parse, SHA1-verified staging).

.DESCRIPTION
    This module contains ONLY pure functions - it performs no REST calls, no web
    requests, no database access, no content writes and no host output, and it touches
    neither the file system nor the registry. Every input is a parameter and every
    output is a return value, so the version-parity regexes and the supersede-stamp
    idempotence are unit-testable without a BigFix server or a database.

    Exported functions:

      Get-StrippedName      product key: removes ' v<digits>[.digits]' globally. Byte-for-
                            byte parity with fixlet_update_tracker.ojo stripVersion (L987)
                            so the pipeline and the dashboard key products identically.
      Get-ExtractedVersion  the version substring, or $null. Parity with extractVersion
                            (fixlet_update_tracker.ojo L992).
      Compare-FixletVersion -1 / 0 / 1, numeric segment comparison (NOT lexical); a
                            missing segment counts as 0.
      Get-FixletPathType    'task' or 'fixlet' - the SINGULAR REST path segment for a
                            get / update of one item.
      New-SupersededXml     idempotent X-Superseded-By MIMEField stamp: strips every
                            existing one first, then inserts exactly one before <Domain>.
                            Two applications produce byte-identical output.
      Read-PrefetchLine     parses one action-script line into { FileName; Sha1; Size;
                            Url; Sha256 } or returns $null. Regex parity with
                            fixlet_dispatcher.ojo extractPrefetchLines (L606-620).

.NOTES
    PowerShell 5.1+. Constrained Language Mode safe (no dynamic .NET type loading).
#>

Set-StrictMode -Version Latest

# The one authoritative version token. IDENTICAL to fixlet_update_tracker.ojo L987
# (' v\d[\d.]+' with a global replace) - a leading space, one digit, then one-or-more
# of [digit or dot]. Keeps a product-family label like the 'v2' in "AWS CLI v2".
$script:VersionStripRegex   = [regex]' v\d[\d.]+'
$script:VersionExtractRegex = [regex]' v(\d[\d.]+)'

# Parity with fixlet_dispatcher.ojo extractPrefetchLines() L608 and rewritePrefetchUrls()
# L591 - optional leading 'prefetch ', a filename token, sha1:, size:, a URL token, an
# optional trailing sha256:.
$script:PrefetchRegex = [regex]'^(?:prefetch\s+)?(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:(\d+)\s+(\S+)(?:\s+sha256:([0-9a-fA-F]+))?'

# Idempotence hinge: strip EVERY existing X-Superseded-By MIMEField before inserting one.
# Mirrors fixlet_update_tracker.ojo buildSupersededXml() L1501-1502.
$script:SupersededStripRegex = [regex]::new(
    '<MIMEField>\s*<Name>\s*X-Superseded-By\s*</Name>[\s\S]*?</MIMEField>',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function Get-StrippedName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    return $script:VersionStripRegex.Replace($Name, '')
}

function Get-ExtractedVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    $m = $script:VersionExtractRegex.Match($Name)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Compare-FixletVersion {
    <#
      Segment-by-segment NUMERIC comparison (parity with fixlet_update_tracker.ojo
      compareVersions L989-1000). "1.2" sorts BEFORE "1.10"; a missing / non-numeric
      segment is treated as 0. A $null / empty side is treated as "0".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Left,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Right
    )
    $pa = @(([string]$Left).Split('.'))
    $pb = @(([string]$Right).Split('.'))
    $len = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $na = 0; $nb = 0
        if ($i -lt $pa.Count) { [void][int]::TryParse($pa[$i], [ref]$na) }
        if ($i -lt $pb.Count) { [void][int]::TryParse($pb[$i], [ref]$nb) }
        if ($na -gt $nb) { return 1 }
        if ($na -lt $nb) { return -1 }
    }
    return 0
}

function Get-FixletPathType {
    <#
      The SINGULAR REST path segment for GET / PUT of one item:
      GET|PUT /api/<task|fixlet>/custom/<site>/<id>. BigFix infers Task vs Fixlet from
      the body on the PLURAL create path, but the single-item path must name it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$IsTask)
    if ($IsTask) { return 'task' }
    return 'fixlet'
}

function New-SupersededXml {
    <#
      Stamp the OLD portal item's XML with an X-Superseded-By MIMEField pointing at the
      new fixlet id. Idempotent by construction: every pre-existing X-Superseded-By
      MIMEField is stripped first, then exactly one is inserted immediately before the
      first <Domain> element (falling back to </Fixlet> / </Task>). Running it twice with
      the same -SupersededByValue yields byte-identical output.

      String manipulation only - does NOT depend on Msxml2.DOMDocument.6.0 (the OJO's
      mechanism) and does NOT round-trip through [xml] (which would reorder / reformat and
      break the byte-identical guarantee).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FixletXml,
        [Parameter(Mandatory)][string]$SupersededByValue
    )

    $cleaned = $script:SupersededStripRegex.Replace($FixletXml, '')

    $valEsc = [System.Security.SecurityElement]::Escape([string]$SupersededByValue)
    $mime = "<MIMEField><Name>X-Superseded-By</Name><Value>$valEsc</Value></MIMEField>"

    $idx = $cleaned.IndexOf('<Domain>', [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -lt 0) { $idx = $cleaned.IndexOf('</Fixlet>', [System.StringComparison]::OrdinalIgnoreCase) }
    if ($idx -lt 0) { $idx = $cleaned.IndexOf('</Task>',   [System.StringComparison]::OrdinalIgnoreCase) }
    if ($idx -lt 0) { return $cleaned }   # nowhere sensible to place it - return stripped input unchanged

    return $cleaned.Substring(0, $idx) + $mime + $cleaned.Substring($idx)
}

function Read-PrefetchLine {
    <#
      Parse ONE action-script line. Returns an object with FileName, Sha1 (lower-cased),
      Size (long), Url and Sha256 (null when the optional sha256: suffix is absent), or
      $null when the line is not a prefetch line (an action script has many such lines).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $m = $script:PrefetchRegex.Match($Line.Trim())
    if (-not $m.Success) { return $null }

    $size = [long]0
    [void][long]::TryParse($m.Groups[3].Value, [ref]$size)

    $sha256 = $null
    if ($m.Groups[5].Success -and $m.Groups[5].Value) { $sha256 = $m.Groups[5].Value.ToLowerInvariant() }

    return [pscustomobject]@{
        FileName = $m.Groups[1].Value
        Sha1     = $m.Groups[2].Value.ToLowerInvariant()
        Size     = $size
        Url      = $m.Groups[4].Value
        Sha256   = $sha256
    }
}

Export-ModuleMember -Function Get-StrippedName, Get-ExtractedVersion, Compare-FixletVersion,
    Get-FixletPathType, New-SupersededXml, Read-PrefetchLine
