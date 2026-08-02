
#Requires -Version 5.1
<#
.SYNOPSIS
    CLM-safe SQLite access helper: invokes the bundled sqlite3.exe CLI via a stdin pipe,
    with injection-safe parameter substitution, busy-timeout parity, and a CLM-safe
    non-ASCII TEXT read-back decoder. Contains zero Add-Type / System.Data.SQLite usage.

.DESCRIPTION
    Dot-source this file once at the top of a caller script:

        . "$PSScriptRoot\Sqlite-Helper.ps1"

    Then call Invoke-SqliteCommand for every database operation (DDL, INSERT/UPDATE/DELETE,
    or SELECT). Parameters:

        -DatabasePath [string] (Mandatory)   Full path to the SQLite database file.
        -SQLDir       [string] (Mandatory)   Directory containing sqlite3.exe directly
                                              (no x64/x86 arch subfolder -- SCHEMA-06).
        -Sql          [string] (Mandatory)   One or more SQL statements. @name tokens are
                                              substituted from -Parameters before execution.
                                              WR-02: at most ONE of those statements may be
                                              result-returning (e.g. a single SELECT, or a
                                              single returning PRAGMA) -- a call with two or
                                              more result-returning statements throws a clear
                                              error instead of silently mis-parsing. DDL/
                                              INSERT/UPDATE/DELETE statements are not result-
                                              returning and may be freely combined.
        -Parameters   [hashtable] = @{}      Bare hashtable literal. Keys are bare names
                                              (no leading @); values are string-coerced and
                                              single-quote-doubled before substitution.

    Returns the raw parsed JSON array from sqlite3.exe's `.mode json` output (D-14/D-15) --
    every call returns an array, even for a single-row/single-column result such as
    COUNT(*). Access rows via $result[0].ColumnName, aliasing columns for readability
    (e.g. "SELECT COUNT(*) AS n").

    PRAGMA busy_timeout=30000 is automatically prepended to every invocation -- callers
    never need to request it (D-06/D-09).

    Non-ASCII TEXT read-back convention (D-16): PowerShell's decode of sqlite3.exe's
    stdout is unreliable for non-ASCII bytes under Constrained Language Mode (the fix,
    [Console]::OutputEncoding's setter, is CLM-blocked). Callers that need byte-exact
    non-ASCII TEXT column values back MUST select that column as:

        SELECT hex(SomeTextColumn) AS "SomeTextColumn__hex" FROM ...

    Invoke-SqliteCommand post-processes every returned row: any property whose name ends
    with the literal suffix "__hex" is hex-decoded (pure CLM-safe bitwise decode, no
    System.Text.Encoding / System.Convert calls) and re-exposed under the base property
    name (suffix stripped); the "__hex" property itself is removed. Properties without
    the suffix are returned unchanged. This applies to any TEXT column, not just a fixed
    set of column names.

.NOTES
    PowerShell 5.1 only. No external modules. Zero Add-Type / System.Data.SQLite usage --
    all database access goes through the bundled sqlite3.exe CLI via a stdin pipe (D-01).
#>

Set-StrictMode -Version Latest

# Module-level, set once when this file is dot-sourced.
# [System.Text.Encoding]::UTF8 is a static PROPERTY GET -- CLM-safe.
# New-Object System.Text.UTF8Encoding($false) / ::new($false) (no-BOM) are CLM-BLOCKED --
# do not use them. The BOM this introduces is harmless -- see Invoke-SqliteCommand's
# statement ordering below (PRAGMA busy_timeout is always the literal first line).
$OutputEncoding = [System.Text.Encoding]::UTF8

function ConvertTo-SqliteLiteral {
    <#
    .SYNOPSIS
        SAFE-01: the entire SQL-injection escaping surface. Single-quote-doubles a value
        and wraps it in single quotes, per SQLite string-literal escaping rules. Do NOT
        add semicolon-stripping or any other blacklist sanitization -- it is unnecessary
        (verified sufficient against the ROADMAP injection payload) and would corrupt
        legitimate data (e.g. a Role named "IT; Ops").
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )
    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertFrom-SqliteHexNibble {
    param(
        [Parameter(Mandatory)]
        [char]$Char
    )
    $code = [int]$Char
    if ($code -ge 48 -and $code -le 57)  { return $code - 48 }   # '0'-'9'
    if ($code -ge 65 -and $code -le 70)  { return $code - 55 }   # 'A'-'F'
    if ($code -ge 97 -and $code -le 102) { return $code - 87 }   # 'a'-'f'
    throw "ConvertFrom-SqliteHexUtf8: invalid hex character '$Char'"
}

function ConvertFrom-SqliteUtf8Bytes {
    # Private helper for ConvertFrom-SqliteHexUtf8
    param(
        [Parameter(Mandatory)]
        $Bytes
    )
    $result = ''
    $i = 0
    $len = $Bytes.Length
    while ($i -lt $len) {
        $b0 = [int]$Bytes[$i]
        if (($b0 -band 0x80) -eq 0) {
            $cp = $b0
            $seqLen = 1
        } elseif (($b0 -band 0xE0) -eq 0xC0) {
            $cp = $b0 -band 0x1F
            $seqLen = 2
        } elseif (($b0 -band 0xF0) -eq 0xE0) {
            $cp = $b0 -band 0x0F
            $seqLen = 3
        } elseif (($b0 -band 0xF8) -eq 0xF0) {
            $cp = $b0 -band 0x07
            $seqLen = 4
        } else {
            throw ("ConvertFrom-SqliteHexUtf8: invalid UTF-8 lead byte 0x{0:X2}" -f $b0)
        }

        for ($j = 1; $j -lt $seqLen; $j++) {
            $cb = [int]$Bytes[$i + $j]
            $cp = ($cp -shl 6) -bor ($cb -band 0x3F)
        }

        if ($cp -le 0xFFFF) {
            $result += [char]$cp
        } else {
            # Surrogate pair for codepoints beyond the BMP.
            $result += [char](0xD800 -bor (($cp - 0x10000) -shr 10))
            $result += [char](0xDC00 -bor (($cp - 0x10000) -band 0x3FF))
        }

        $i += $seqLen
    }
    return $result
}

function ConvertFrom-SqliteHexUtf8 {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Hex
    )
    if ($Hex.Length -eq 0) { return '' }

    $byteCount = [int]($Hex.Length / 2)
    $bytes = [byte[]]::new($byteCount)
    for ($i = 0; $i -lt $byteCount; $i++) {
        $hi = ConvertFrom-SqliteHexNibble -Char $Hex[$i * 2]
        $lo = ConvertFrom-SqliteHexNibble -Char $Hex[$i * 2 + 1]
        $bytes[$i] = [byte](($hi -shl 4) -bor $lo)
    }

    return (ConvertFrom-SqliteUtf8Bytes -Bytes $bytes)
}

function Invoke-SqliteCommand {
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath,

        [Parameter(Mandatory)]
        [string]$SQLDir,

        [Parameter(Mandatory)]
        [string]$Sql,

        [hashtable]$Parameters = @{}
    )

    # SCHEMA-06: -SQLDir resolves directly to sqlite3.exe 
    $sqlite3exe = Join-Path $SQLDir 'sqlite3.exe'
    if (-not (Test-Path $sqlite3exe)) {
        throw "sqlite3.exe not found at: $sqlite3exe`nSet -SQLDir to the directory containing sqlite3.exe."
    }

    $resolvedSql = $Sql
    if ($Parameters.Keys.Count -gt 0) {
        $sortedKeys = @($Parameters.Keys | Sort-Object -Property Length -Descending)
        $pattern = ($sortedKeys | ForEach-Object { [regex]::Escape("@$_") }) -join '|'
        $tokenMatches = [regex]::Matches($Sql, "(?:$pattern)(?![A-Za-z0-9_])")
        if ($tokenMatches.Count -gt 0) {
            $sb = ''
            $lastIndex = 0
            foreach ($tokenMatch in $tokenMatches) {
                $sb += $Sql.Substring($lastIndex, $tokenMatch.Index - $lastIndex)
                $matchedKey = $sortedKeys | Where-Object { $tokenMatch.Value -eq "@$_" } | Select-Object -First 1
                $sb += ConvertTo-SqliteLiteral -Value ([string]$Parameters[$matchedKey])
                $lastIndex = $tokenMatch.Index + $tokenMatch.Length
            }
            $sb += $Sql.Substring($lastIndex)
            $resolvedSql = $sb
        }
    }

    $fullSql = "PRAGMA busy_timeout=30000;`n.mode json`n$resolvedSql"

    $ErrorActionPreference = 'Continue'
    $raw = $fullSql | & $sqlite3exe $DatabasePath 2>&1
    $exitCode = $LASTEXITCODE

    $rawArr    = @($raw)
    $stdoutArr = @($rawArr | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderrArr = @($rawArr | Where-Object { $_ -is    [System.Management.Automation.ErrorRecord] } |
                    ForEach-Object { $_.Exception.Message })

    if ($exitCode -ne 0) {
        throw "sqlite3.exe failed (exit=$exitCode): $($stderrArr -join '; ')"
    }
    $jsonLines = @($stdoutArr | Select-Object -Skip 1)
    if ($jsonLines.Count -eq 0) {
        return @()   # write-only statement -- nothing after the busy_timeout echo
    }

    $topLevelArrayStarts = @($jsonLines | Where-Object { $_.StartsWith('[') })
    if ($topLevelArrayStarts.Count -gt 1) {
        throw "Invoke-SqliteCommand: -Sql produced $($topLevelArrayStarts.Count) result sets from a single call, but only one result-returning statement is supported per call. Split multi-SELECT (or SELECT + returning PRAGMA) calls into separate Invoke-SqliteCommand invocations."
    }

    # re-join before ConvertFrom-Json.
    $joined = $jsonLines -join "`n"
    $parsed = $joined | ConvertFrom-Json
    $rows   = @($parsed)

    for ($r = 0; $r -lt $rows.Count; $r++) {
        $row = $rows[$r]
        $hexPropNames = @($row.PSObject.Properties | Where-Object { $_.Name.EndsWith('__hex') } |
                            ForEach-Object { $_.Name })
        if ($hexPropNames.Count -eq 0) { continue }

        $decoded = @{}
        foreach ($hexName in $hexPropNames) {
            $baseName = $hexName.Substring(0, $hexName.Length - 5)  
            $hexVal = $row.$hexName
            $decoded[$baseName] = if ($null -eq $hexVal) { $null } else { ConvertFrom-SqliteHexUtf8 -Hex ([string]$hexVal) }
        }

        $newRow = $row | Select-Object -Property * -ExcludeProperty $hexPropNames
        foreach ($baseName in $decoded.Keys) {
            Add-Member -InputObject $newRow -MemberType NoteProperty -Name $baseName -Value $decoded[$baseName] -Force
        }
        $rows[$r] = $newRow
    }

    return @(, $rows) 
}

