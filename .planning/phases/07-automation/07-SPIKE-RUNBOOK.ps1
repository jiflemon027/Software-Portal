#Requires -Version 5.1
<#
.SYNOPSIS
    Wave-1 spike + audit runbook (07-01). Establishes ground truth, against the live BigFix
    root server, for three assumptions the rest of Phase 7 is otherwise built on: the exact
    <ComputerGroup> REST shape (RESEARCH Assumptions A1/A6), the literal `set of ("a";"b")`
    relevance form (A2), and whether any live artefact of the retired Axonius pipeline still
    exists on gpbfs (A4) - plus whether sqlite3.exe is staged at the configured SQLDir (A5).

.DESCRIPTION
    Four independently-wrapped checks. Each writes PASS/FAIL plus raw evidence into a markdown
    findings file (-OutputPath). A failure in one check never aborts the others, and an
    unreachable root server degrades every REST-dependent check to a FAIL row with the raw
    error text instead of an unhandled terminating error - this script always exits 0.

      Check A - ComputerGroup create/read/delete (six-element body, reduced-body retry)
      Check B - literal `set of ("a";"b")` client + query relevance
      Check C - retired Axonius pipeline artefact audit (schtasks + fixlets + computer groups)
      Check D - sqlite3.exe presence/version at -SQLDir

.PARAMETER BESRootUrl
    BigFix root server REST base URL.

.PARAMETER SiteName
    Custom site the throwaway Computer Group / query checks run against.

.PARAMETER Credential
    BigFix console-operator credential. Mandatory - never defaulted, never logged, never
    written to the findings file.

.PARAMETER SQLDir
    Directory expected to contain sqlite3.exe on the root server.

.PARAMETER OutputPath
    Markdown findings file this script writes (overwrites on every run).

.PARAMETER SkipDelete
    Leave the throwaway ZZZ-SPIKE-DELETE-ME group in place after Check A for console
    inspection. The checkpoint's acceptance criteria then require deleting it manually before
    approving.

.NOTES
    PowerShell 5.1+. No CLR type-loading helper calls, no System.Data.SQLite. PS7 uses
    -SkipCertificateCheck; 5.1 falls back to the ServicePointManager trust-all shim also used
    by Publish-RoleSnapshot.ps1 / Get-BigFixCredential.ps1's callers.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$BESRootUrl = 'https://localhost:52311',

    [Parameter()]
    [string]$SiteName = 'Dereso Software Portal',

    [Parameter(Mandatory)]
    [pscredential]$Credential,

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$OutputPath = '.planning/phases/07-automation/07-SPIKE-FINDINGS.md',

    [Parameter()]
    [switch]$SkipDelete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$besRootTrimmed = $BESRootUrl.TrimEnd('/')
$siteEnc = [uri]::EscapeDataString($SiteName)

# The literal relevance under test for Assumption A2 - also used as Check A's group relevance
# (two nonexistent usernames so the throwaway group can never admit a real device).
$spikeRelevance = '(number of (logged on users whose (name of it as lowercase is contained by set of ("zzzspikeuser1";"zzzspikeuser2")))) = 1'

# --- TLS / cert-check convention (Publish-RoleSnapshot.ps1 / Get-BigFixCredential.ps1) ------
$irmExtra = @{}
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $irmExtra['SkipCertificateCheck'] = $true
} else {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

# --- basic-auth header, built from -Credential, never logged --------------------------------
$authHeader = @{}
try {
    $plainPw = $Credential.GetNetworkCredential().Password
    $pair = '{0}:{1}' -f $Credential.UserName, $plainPw
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    $authHeader = @{ Authorization = "Basic $b64" }
    $plainPw = $null
} catch {
    $authHeader = @{}
}

function Invoke-BesRequest {
    <# Wraps Invoke-WebRequest; never throws - always returns a result object so a single
       failed call can be recorded as a FAIL row without aborting the calling Check. #>
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Uri,
        [string]$Body,
        [string]$ContentType = 'application/xml'
    )
    $result = [pscustomobject]@{
        Success    = $false
        StatusCode = $null
        Content    = $null
        Error      = $null
    }
    try {
        $wrArgs = @{
            Method          = $Method
            Uri             = $Uri
            Headers         = $authHeader
            UseBasicParsing = $true
        }
        if ($Body) {
            $wrArgs['Body'] = $Body
            $wrArgs['ContentType'] = $ContentType
        }
        foreach ($k in $irmExtra.Keys) { $wrArgs[$k] = $irmExtra[$k] }
        $resp = Invoke-WebRequest @wrArgs
        $result.Success = $true
        $result.StatusCode = [int]$resp.StatusCode
        $result.Content = [string]$resp.Content
    } catch {
        if ($_.Exception.Response) {
            try { $result.StatusCode = [int]$_.Exception.Response.StatusCode } catch { }
        }
        $result.Error = $_.Exception.Message
    }
    return $result
}

function New-ComputerGroupXml {
    <# Builds the <BES><ComputerGroup> POST/PUT body. When -SixElement is set, emits all six
       schema-documented elements in order (Title/Domain/JoinByIntersection/IsDynamic/
       EvaluateOnClient/SearchComponentRelevance - RESEARCH Pattern 1 "belt-and-suspenders").
       Otherwise omits IsDynamic/EvaluateOnClient (the jgstew real-world four-element shape). #>
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$Relevance,
        [switch]$SixElement
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.Append('<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">')
    [void]$sb.Append('<ComputerGroup>')
    [void]$sb.Append("<Title>$Title</Title>")
    [void]$sb.Append('<Domain>BESC</Domain>')
    [void]$sb.Append('<JoinByIntersection>true</JoinByIntersection>')
    if ($SixElement) {
        [void]$sb.Append('<IsDynamic>true</IsDynamic>')
        [void]$sb.Append('<EvaluateOnClient>true</EvaluateOnClient>')
    }
    [void]$sb.Append('<SearchComponentRelevance Comparison="IsTrue">')
    [void]$sb.Append('<Relevance><![CDATA[' + $Relevance + ']]></Relevance>')
    [void]$sb.Append('</SearchComponentRelevance>')
    [void]$sb.Append('</ComputerGroup>')
    [void]$sb.Append('</BES>')
    return $sb.ToString()
}

# ==============================================================================================
# Check A - ComputerGroup create/read/delete
# ==============================================================================================
$checkA = [ordered]@{
    Status             = 'FAIL'
    Evidence           = New-Object System.Collections.Generic.List[string]
    ElementSetAccepted = 'UNKNOWN'
}
try {
    $groupTitle = 'ZZZ-SPIKE-DELETE-ME'
    $postUri = "$besRootTrimmed/api/computergroups/custom/$siteEnc"

    $sixElementXml = New-ComputerGroupXml -Title $groupTitle -Relevance $spikeRelevance -SixElement
    $r1 = Invoke-BesRequest -Method Post -Uri $postUri -Body $sixElementXml -ContentType 'application/xml'
    $checkA.Evidence.Add("POST (six-element) $postUri -> success=$($r1.Success) status=$($r1.StatusCode)")
    $checkA.Evidence.Add("POST (six-element) response body: $($r1.Content)")
    if ($r1.Error) { $checkA.Evidence.Add("POST (six-element) error: $($r1.Error)") }

    $acceptedShape = $null
    $createResponse = $null
    if ($r1.Success -and $r1.StatusCode -ge 200 -and $r1.StatusCode -lt 300) {
        $acceptedShape = 'six-element (Title/Domain/JoinByIntersection/IsDynamic/EvaluateOnClient/SearchComponentRelevance)'
        $createResponse = $r1.Content
    } else {
        $reducedXml = New-ComputerGroupXml -Title $groupTitle -Relevance $spikeRelevance
        $r2 = Invoke-BesRequest -Method Post -Uri $postUri -Body $reducedXml -ContentType 'application/xml'
        $checkA.Evidence.Add("POST (reduced, retry) $postUri -> success=$($r2.Success) status=$($r2.StatusCode)")
        $checkA.Evidence.Add("POST (reduced, retry) response body: $($r2.Content)")
        if ($r2.Error) { $checkA.Evidence.Add("POST (reduced, retry) error: $($r2.Error)") }
        if ($r2.Success -and $r2.StatusCode -ge 200 -and $r2.StatusCode -lt 300) {
            $acceptedShape = 'reduced four-element (no IsDynamic/EvaluateOnClient - jgstew real-world shape)'
            $createResponse = $r2.Content
        }
    }

    $checkA.ElementSetAccepted = if ($acceptedShape) { $acceptedShape } else { 'NEITHER - both the six-element and reduced POST bodies failed' }

    if ($createResponse) {
        $newId = $null
        $m = [regex]::Match($createResponse, '<ComputerGroup[^>]*\bID="(\d+)"')
        if (-not $m.Success) { $m = [regex]::Match($createResponse, '<ID>(\d+)</ID>') }
        if ($m.Success) { $newId = $m.Groups[1].Value }
        $checkA.Evidence.Add("Parsed new group id: $(if ($newId) { $newId } else { '(none found in response body)' })")

        if ($newId) {
            $getUri = "$besRootTrimmed/api/computergroup/custom/$siteEnc/$newId"
            $rGet = Invoke-BesRequest -Method Get -Uri $getUri
            $checkA.Evidence.Add("GET $getUri -> success=$($rGet.Success) status=$($rGet.StatusCode)")
            $checkA.Evidence.Add("GET round-trip body: $($rGet.Content)")
            if ($rGet.Error) { $checkA.Evidence.Add("GET error: $($rGet.Error)") }

            if ($SkipDelete) {
                $checkA.Status = 'PASS'
                $checkA.Evidence.Add('-SkipDelete set: throwaway group left in place for console inspection - delete it manually before approving the checkpoint.')
            } else {
                $delUri = "$besRootTrimmed/api/computergroup/custom/$siteEnc/$newId"
                $rDel = Invoke-BesRequest -Method Delete -Uri $delUri
                $checkA.Evidence.Add("DELETE $delUri -> success=$($rDel.Success) status=$($rDel.StatusCode)")
                if ($rDel.Error) { $checkA.Evidence.Add("DELETE error: $($rDel.Error)") }
                if ($rDel.Success -and $rDel.StatusCode -ge 200 -and $rDel.StatusCode -lt 300) {
                    $checkA.Status = 'PASS'
                } else {
                    $checkA.Status = 'FAIL'
                    $checkA.Evidence.Add('Create/read succeeded but DELETE failed - the throwaway group may still be live; delete it manually before approving the checkpoint.')
                }
            }
        } else {
            $checkA.Status = 'FAIL'
            $checkA.Evidence.Add('Group appeared to create but no id could be parsed from the response body - cannot GET/DELETE.')
        }
    } else {
        $checkA.Status = 'FAIL'
        $checkA.Evidence.Add('Neither the six-element nor the reduced body was accepted by POST computergroups/custom/<site> - the entire generator step blocks until this is resolved.')
    }
} catch {
    $checkA.Status = 'FAIL'
    $checkA.Evidence.Add("Unhandled exception in Check A: $($_.Exception.Message)")
}

# ==============================================================================================
# Check B - literal set of ("a";"b") relevance (Assumption A2)
# ==============================================================================================
$checkB = [ordered]@{
    Status   = 'FAIL'
    Evidence = New-Object System.Collections.Generic.List[string]
    Verdict  = 'UNKNOWN'
}
try {
    $checkB.Evidence.Add("Relevance under test: $spikeRelevance")
    $checkB.Evidence.Add("This same expression is Check A's ComputerGroup relevance - see Check A evidence for whether the group create request as a whole was accepted (a rejected POST does not, by itself, prove this expression fails to parse; a 400 body quoting a relevance parse error is the strongest signal there).")

    $queryUri = "$besRootTrimmed/api/query"
    $wrapped = 'exists true whose (' + $spikeRelevance + ')'
    $bodyStr = 'relevance=' + [uri]::EscapeDataString($wrapped)
    $r = Invoke-BesRequest -Method Post -Uri $queryUri -Body $bodyStr -ContentType 'application/x-www-form-urlencoded'
    $checkB.Evidence.Add("POST $queryUri -> success=$($r.Success) status=$($r.StatusCode)")
    $checkB.Evidence.Add("POST /api/query response body: $($r.Content)")
    if ($r.Error) { $checkB.Evidence.Add("POST /api/query error: $($r.Error)") }

    if ($r.Success -and $r.StatusCode -ge 200 -and $r.StatusCode -lt 300 -and $r.Content -notmatch '(?i)parse\s*error|ParseException|QnA.*error') {
        $checkB.Status = 'PASS'
        $checkB.Verdict = 'HELD - the literal set of ("a";"b") tuple form parsed without error'
    } elseif ($r.Content -and $r.Content -match '(?i)parse\s*error|ParseException') {
        $checkB.Status = 'FAIL'
        $checkB.Verdict = 'DID NOT HOLD - the server returned a relevance parse error, see evidence'
    } else {
        $checkB.Status = 'FAIL'
        $checkB.Verdict = 'UNKNOWN - the /api/query request did not succeed; see evidence'
    }
} catch {
    $checkB.Status = 'FAIL'
    $checkB.Verdict = 'UNKNOWN - unhandled exception'
    $checkB.Evidence.Add("Unhandled exception in Check B: $($_.Exception.Message)")
}

# ==============================================================================================
# Check C - retired Axonius pipeline orphan audit
# ==============================================================================================
$checkC = [ordered]@{
    Status         = 'FAIL'
    Evidence       = New-Object System.Collections.Generic.List[string]
    ArtefactsFound = New-Object System.Collections.Generic.List[string]
}
try {
    foreach ($taskName in @('DeresoRoleIngest', 'DeresoRolePublish')) {
        try {
            $out = & schtasks /query /TN $taskName 2>&1
            $ec = $LASTEXITCODE
            $outStr = ($out | Out-String).Trim()
            $checkC.Evidence.Add("schtasks /query /TN $taskName -> exit=$ec")
            $checkC.Evidence.Add("output: $outStr")
            if ($ec -eq 0) {
                $checkC.ArtefactsFound.Add("Scheduled task '$taskName' EXISTS on this host")
            }
        } catch {
            $checkC.Evidence.Add("schtasks /query /TN $taskName -> exception: $($_.Exception.Message)")
        }
    }

    $rFix = Invoke-BesRequest -Method Get -Uri "$besRootTrimmed/api/fixlets/custom/$siteEnc"
    $checkC.Evidence.Add("GET fixlets/custom/$SiteName -> success=$($rFix.Success) status=$($rFix.StatusCode)")
    if ($rFix.Error) { $checkC.Evidence.Add("GET fixlets error: $($rFix.Error)") }
    if ($rFix.Success -and $rFix.Content) {
        $nameMatches = [regex]::Matches($rFix.Content, '<Name>([^<]*)</Name>') | ForEach-Object { $_.Groups[1].Value }
        $hits = @($nameMatches | Where-Object { $_ -match '(?i)roleref|dereso role ref' })
        foreach ($h in $hits) { $checkC.ArtefactsFound.Add("Fixlet/Task named '$h'") }
        $checkC.Evidence.Add("Fixlets/Tasks scanned: $($nameMatches.Count); RoleRef-matching: $($hits.Count)")
    }

    $rGrp = Invoke-BesRequest -Method Get -Uri "$besRootTrimmed/api/computergroups/custom/$siteEnc"
    $checkC.Evidence.Add("GET computergroups/custom/$SiteName -> success=$($rGrp.Success) status=$($rGrp.StatusCode)")
    if ($rGrp.Error) { $checkC.Evidence.Add("GET computergroups error: $($rGrp.Error)") }
    if ($rGrp.Success -and $rGrp.Content) {
        $grpMatches = [regex]::Matches($rGrp.Content, '<Name>([^<]*)</Name>') | ForEach-Object { $_.Groups[1].Value }
        $grpHits = @($grpMatches | Where-Object { $_ -match '(?i)roleref' })
        foreach ($h in $grpHits) { $checkC.ArtefactsFound.Add("Computer group named '$h'") }
        $checkC.Evidence.Add("Computer groups scanned: $($grpMatches.Count); roleref-matching: $($grpHits.Count)")
    }

    $restOk = $rFix.Success -and $rGrp.Success
    if (-not $restOk) {
        $checkC.Status = 'FAIL'
        $checkC.Evidence.Add('Could not complete the fixlet/computergroup REST scan (root server unreachable or auth failed) - Check C is inconclusive for those two probes; only the local schtasks results above are usable.')
    } else {
        $checkC.Status = 'PASS'
        if ($checkC.ArtefactsFound.Count -gt 0) {
            $checkC.Evidence.Add('One or more live Axonius-era artefacts found - see ArtefactsFound list. 07-09 archival must also stop/delete these, not just move files.')
        } else {
            $checkC.Evidence.Add('None found - no DeresoRoleIngest/DeresoRolePublish scheduled tasks and no RoleRef* fixlets/groups.')
        }
    }
} catch {
    $checkC.Status = 'FAIL'
    $checkC.Evidence.Add("Unhandled exception in Check C: $($_.Exception.Message)")
}

# ==============================================================================================
# Check D - root-server sqlite3.exe
# ==============================================================================================
$checkD = [ordered]@{
    Status   = 'FAIL'
    Evidence = New-Object System.Collections.Generic.List[string]
    Version  = 'UNKNOWN'
}
try {
    $sqlitePath = Join-Path $SQLDir 'sqlite3.exe'
    $exists = Test-Path $sqlitePath
    $checkD.Evidence.Add("Test-Path '$sqlitePath' -> $exists")
    if ($exists) {
        try {
            $verOut = & $sqlitePath '-version' 2>&1
            $verStr = ($verOut | Out-String).Trim()
            $checkD.Evidence.Add("sqlite3.exe -version -> $verStr")
            $checkD.Version = $verStr
            $checkD.Status = 'PASS'
        } catch {
            $checkD.Evidence.Add("sqlite3.exe found but '-version' failed: $($_.Exception.Message)")
            $checkD.Status = 'FAIL'
        }
    } else {
        $checkD.Status = 'FAIL'
        $checkD.Evidence.Add("sqlite3.exe NOT found at $SQLDir")
    }
} catch {
    $checkD.Status = 'FAIL'
    $checkD.Evidence.Add("Unhandled exception in Check D: $($_.Exception.Message)")
}

# ==============================================================================================
# Write findings file
# ==============================================================================================
try {
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# 07-01 Spike Findings')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Generated: $timestamp (UTC)")
    [void]$sb.AppendLine("BES Root URL: $BESRootUrl")
    [void]$sb.AppendLine("Site: $SiteName")
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Check A - ComputerGroup element set')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Status: $($checkA.Status)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**ComputerGroup element set accepted:** $($checkA.ElementSetAccepted)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Evidence:')
    [void]$sb.AppendLine()
    foreach ($line in $checkA.Evidence) { [void]$sb.AppendLine("- $line") }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Check B - Assumption A2 (literal set of (...) relevance)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Status: $($checkB.Status)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Assumption A2 verdict:** $($checkB.Verdict)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Evidence:')
    [void]$sb.AppendLine()
    foreach ($line in $checkB.Evidence) { [void]$sb.AppendLine("- $line") }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Check C - Live Axonius-era artefacts')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Status: $($checkC.Status)")
    [void]$sb.AppendLine()
    if ($checkC.ArtefactsFound.Count -gt 0) {
        [void]$sb.AppendLine('**Live Axonius-era artefacts found:**')
        [void]$sb.AppendLine()
        foreach ($a in $checkC.ArtefactsFound) { [void]$sb.AppendLine("- $a") }
    } else {
        [void]$sb.AppendLine('**Live Axonius-era artefacts found:** none found')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Evidence:')
    [void]$sb.AppendLine()
    foreach ($line in $checkC.Evidence) { [void]$sb.AppendLine("- $line") }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Check D - Root-server sqlite3.exe')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Status: $($checkD.Status)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**sqlite3.exe version:** $($checkD.Version)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Evidence:')
    [void]$sb.AppendLine()
    foreach ($line in $checkD.Evidence) { [void]$sb.AppendLine("- $line") }
    [void]$sb.AppendLine()

    $outDirPath = Split-Path -Parent $OutputPath
    if ($outDirPath -and -not (Test-Path $outDirPath)) { New-Item -ItemType Directory -Path $outDirPath -Force | Out-Null }
    Set-Content -Path $OutputPath -Value $sb.ToString() -Encoding UTF8

    Write-Host "----RUN SUMMARY----"
    Write-Host ("Check A: {0} (element set: {1})" -f $checkA.Status, $checkA.ElementSetAccepted)
    Write-Host ("Check B: {0} (A2: {1})" -f $checkB.Status, $checkB.Verdict)
    Write-Host ("Check C: {0} (artefacts found: {1})" -f $checkC.Status, $checkC.ArtefactsFound.Count)
    Write-Host ("Check D: {0} (version: {1})" -f $checkD.Status, $checkD.Version)
    Write-Host "Findings written to: $OutputPath"
} catch {
    Write-Warning "Failed to write findings file to '$OutputPath': $($_.Exception.Message)"
}

exit 0
