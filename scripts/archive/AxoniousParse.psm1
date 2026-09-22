#Requires -Version 5.1
<#
.SYNOPSIS
    Pure, side-effect-free transforms for the Axonius ingest (07-01 Task 2 / Task 3).

.DESCRIPTION
    These functions are the designated test seams (07-RESEARCH  Seams). They perform no
    file I/O, no database calls, no host output, no web requests, and hold no module-scope
    mutable state, so tests can import this module and exercise them in isolation.

    Public contract (07-01 <interfaces>):
      Resolve-UserName  - username coalesce -> lowercased match key + Username_Src (D-06)
      Get-GroupViews    - one group value -> { dn ; cn ; display } (Pitfall 10)
      Get-SourceType    - Group Type + Email presence -> Source_Type label (D-08)
      Resolve-Roles     - GroupRoleMap matcher, all-matches-apply (D-08)

    Also exported as the D-07 splitter test seam:
      Get-GroupRows     - defensive positional-best-effort combine of the loosely-aligned
                          "Assigned Groups: *" multi-value cells (no index-zip)
#>

Set-StrictMode -Version Latest

# ---- internal helpers (not exported) -----------------------------------

function Split-AxMultiValue {
    # Split one Axonius cell on CR / LF / CRLF. Blanks are preserved IN PLACE so sibling
    # arrays stay aligned; only trailing blank elements are trimmed. Each surviving element
    # is .Trim()'d.
    param([AllowNull()][AllowEmptyString()][string]$Raw)
    if ($null -eq $Raw -or $Raw -eq '') { return @() }
    $parts = [regex]::Split($Raw, "\r\n|\r|\n")
    $end = $parts.Length - 1
    while ($end -ge 0 -and [string]::IsNullOrWhiteSpace($parts[$end])) { $end-- }
    if ($end -lt 0) { return @() }
    return @($parts[0..$end] | ForEach-Object { $_.Trim() })
}

function Get-AxAt {
    # Bounds-safe read: '' when the index is out of range or the slot is $null.
    param($Arr, [int]$Index)
    if ($null -eq $Arr) { return '' }
    $count = @($Arr).Count
    if ($Index -lt 0 -or $Index -ge $count) { return '' }
    $v = @($Arr)[$Index]
    if ($null -eq $v) { return '' }
    return [string]$v
}

# ---- public functions -------------------------------------------------

function Resolve-UserName {
    <#
    .SYNOPSIS
        Coalesce a match key from sAMAccountName -> UPN local-part -> Aggregated: User Name,
        lowercased. Returns [pscustomobject] @{ UserID ; Username_Src } or $null when every
        candidate is blank (D-06).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Sam,
        [AllowNull()][AllowEmptyString()][string]$Upn,
        [AllowNull()][AllowEmptyString()][string]$UserName,
        [string]$Priority = 'sam,upn,username'
    )

    $order = @($Priority -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    if ($order.Count -eq 0) { $order = @('sam', 'upn', 'username') }

    foreach ($src in $order) {
        switch ($src) {
            'sam' {
                if (-not [string]::IsNullOrWhiteSpace($Sam)) {
                    return [pscustomobject]@{ UserID = $Sam.Trim().ToLower(); Username_Src = 'sam' }
                }
            }
            'upn' {
                if (-not [string]::IsNullOrWhiteSpace($Upn)) {
                    $local = ($Upn.Trim() -split '@', 2)[0]
                    if (-not [string]::IsNullOrWhiteSpace($local)) {
                        return [pscustomobject]@{ UserID = $local.ToLower(); Username_Src = 'upn' }
                    }
                }
            }
            'username' {
                if (-not [string]::IsNullOrWhiteSpace($UserName)) {
                    $first = @([regex]::Split($UserName, "\r\n|\r|\n") |
                            ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    if ($first.Count -gt 0) {
                        return [pscustomobject]@{ UserID = $first[0].ToLower(); Username_Src = 'username' }
                    }
                }
            }
        }
    }
    return $null
}

function Get-GroupViews {
    <#
    .SYNOPSIS
        One group value -> three views. dn = trimmed raw; cn = the first CN= RDN (honouring
        backslash-escaped commas) when the value looks like a DN, else the raw string;
        display = the supplied -Display if non-blank, else the raw string. Never throws.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Raw,
        [AllowNull()][AllowEmptyString()][string]$Display
    )

    $r  = if ($null -eq $Raw) { '' } else { $Raw.Trim() }
    $cn = $r

    if ($r -match '^\s*CN=') {
        $rest = $r.Substring($r.IndexOf('=') + 1)
        $buf  = ''
        for ($i = 0; $i -lt $rest.Length; $i++) {
            $ch = $rest[$i]
            if ($ch -eq '\' -and ($i + 1) -lt $rest.Length) {
                $buf += $rest[$i + 1]
                $i++
                continue
            }
            if ($ch -eq ',') { break }
            $buf += $ch
        }
        $cn = $buf
    }

    $disp = if (-not [string]::IsNullOrWhiteSpace($Display)) { $Display.Trim() } else { $r }
    return [pscustomobject]@{ dn = $r; cn = $cn; display = $disp }
}

function Get-SourceType {
    <#
    .SYNOPSIS
        Derive Source_Type. Email present -> 'Mailing List'. Otherwise a normalised label
        from Group Type. Never returns $null/'' (UserRole.Source_Type is NOT NULL).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$GroupType,
        [AllowNull()][AllowEmptyString()][string]$Email
    )

    if (-not [string]::IsNullOrWhiteSpace($Email)) { return 'Mailing List' }

    $gt = if ($null -eq $GroupType) { '' } else { $GroupType.Trim().ToLower() }
    if ($gt -match 'security')                 { return 'AD Security Group' }
    if ($gt -match 'distribution')             { return 'Distribution Group' }
    if ($gt -match 'mailing')                  { return 'Mailing List' }
    if ($gt -match 'unified|microsoft 365|azure') { return 'Azure AD Group' }
    return 'Unknown'
}

function Get-GroupRows {
    <#
    .SYNOPSIS
        D-07 defensive combine. Splits the five loosely-aligned "Assigned Groups: *" cells,
        then iterates the LONGEST array by index reading each sibling with a bounds check.
        Emits one row per index of the longest array (surplus entries of the longest array
        are NOT discarded); never index-zips, never drops a group because a sibling slot is
        empty, never throws on a ragged shape.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Display,
        [AllowNull()][AllowEmptyString()][string]$GroupType,
        [AllowNull()][AllowEmptyString()][string]$Email,
        [AllowNull()][AllowEmptyString()][string]$Source
    )

    $n = @(Split-AxMultiValue $Name)
    $d = @(Split-AxMultiValue $Display)
    $t = @(Split-AxMultiValue $GroupType)
    $e = @(Split-AxMultiValue $Email)
    $s = @(Split-AxMultiValue $Source)

    $max = @($n.Count, $d.Count, $t.Count, $e.Count, $s.Count) |
        Measure-Object -Maximum | ForEach-Object { $_.Maximum }
    if (-not $max -or $max -lt 1) { return @() }

    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $max; $i++) {
        [void]$out.Add([pscustomobject]@{
            Name      = (Get-AxAt $n $i)
            Display   = (Get-AxAt $d $i)
            GroupType = (Get-AxAt $t $i)
            Email     = (Get-AxAt $e $i)
            Source    = (Get-AxAt $s $i)
        })
    }
    return @($out)
}

function Resolve-Roles {
    <#
    .SYNOPSIS
        GroupRoleMap matcher (D-08). $GroupViews has keys cn / display / dn (hashtable or
        object). For each rule: Active=0 never fires; a rule whose Match_On names an
        absent/blank view is skipped; Pattern ending '*' is an ordinal case-insensitive
        prefix test, otherwise ordinal case-insensitive equality. ALL matching rules apply
        (Priority is advisory ordering only). Returns zero or more
        [pscustomobject] @{ Role ; GRMID ; Match_On ; Matched_View ; Priority }, sorted by
        Priority ascending. A rule that cannot be evaluated is skipped, never thrown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$GroupViews,
        [AllowNull()]$Rules
    )

    $results = New-Object System.Collections.ArrayList
    if ($null -eq $Rules) { return @() }

    foreach ($rule in @($Rules)) {
        if ($null -eq $rule) { continue }
        try {
            $active = 1
            if ($null -ne $rule.PSObject.Properties['Active'] -and $null -ne $rule.Active) {
                $active = [int]$rule.Active
            }
            if ($active -eq 0) { continue }

            $matchOn = 'cn'
            if ($null -ne $rule.PSObject.Properties['Match_On'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Match_On)) {
                $matchOn = ([string]$rule.Match_On).Trim().ToLower()
            }
            if ($matchOn -ne 'cn' -and $matchOn -ne 'display' -and $matchOn -ne 'dn') { continue }

            $view = $null
            if ($GroupViews -is [System.Collections.IDictionary]) {
                $view = [string]$GroupViews[$matchOn]
            } else {
                $p = $GroupViews.PSObject.Properties[$matchOn]
                if ($null -ne $p) { $view = [string]$p.Value }
            }
            if ([string]::IsNullOrWhiteSpace($view)) { continue }

            $pattern = [string]$rule.Pattern
            if ($null -eq $pattern -or $pattern -eq '') { continue }

            $isMatch = $false
            if ($pattern.EndsWith('*')) {
                $prefix  = $pattern.Substring(0, $pattern.Length - 1)
                $isMatch = $view.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
            } else {
                $isMatch = [string]::Equals($view, $pattern, [System.StringComparison]::OrdinalIgnoreCase)
            }
            if (-not $isMatch) { continue }

            $priority = 100
            if ($null -ne $rule.PSObject.Properties['Priority'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.Priority)) {
                $priority = [int]$rule.Priority
            }
            $grmid = $null
            if ($null -ne $rule.PSObject.Properties['GRMID']) { $grmid = $rule.GRMID }

            [void]$results.Add([pscustomobject]@{
                Role         = [string]$rule.Role
                GRMID        = $grmid
                Match_On     = $matchOn
                Matched_View = $view
                Priority     = $priority
            })
        } catch {
            continue
        }
    }

    return @($results | Sort-Object Priority)
}

Export-ModuleMember -Function Resolve-UserName, Get-GroupViews, Get-SourceType, Resolve-Roles, Get-GroupRows
