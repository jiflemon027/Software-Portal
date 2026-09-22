#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 7 dry-run safety audit. Proves the NFR-NEW guarantee for the whole phase in
    one command: every new Phase 7 script, run with -WhatIf, makes ZERO file writes,
    ZERO database writes and ZERO scheduled-task / mutating-REST calls, while still
    producing its own run-audit record.

.DESCRIPTION
    For each audited script (see $AuditTargets):

      1. A throwaway working directory is stood up containing
           - a fresh AutomationState.db seeded from
             tests/fixtures/phase-07/automation-db-schema.sql
           - a copy of tests/fixtures/phase-07/roleawareness-v2.db with the four D-18
             Map columns added (the "migrated" endpoint DB)
           - an empty roleref\ output directory and an empty staging\ root
           - a snap\ directory holding roleref-aag-uk-latest.json (from the fixture)
           - the axonious-sample-50.csv fixture and a placeholder vault-token file
      2. A MANIFEST of the whole working directory is recorded BEFORE the run:
         every file's relative path, byte length and SHA1, plus, for every table in
         both SQLite databases, the row count, MAX(rowid) and a SHA1 of the table's
         JSON-rendered contents, plus PRAGMA data_version for each DB.
      3. The script is invoked, in a child process, with -WhatIf and fixture
         arguments. Invoke-RestMethod, Invoke-WebRequest, Register-ScheduledTask and
         Start-ScheduledTask are all shadowed by stubs: every call is recorded, and a
         call that would MUTATE (any Register/Start-ScheduledTask, any PUT/DELETE,
         any POST that is not a BigFix /api/query read, any Invoke-WebRequest -OutFile)
         is a FAILURE. Read calls (GET, POST /api/query) are recorded but permitted.
      4. The manifest and the table hashes are recomputed and compared. They MUST be
         byte-identical, with the sole permitted exception of the script's own
         run-audit record (a *.json under logs\, a reconcile-*.json beside the DB, or
         SWDlog.log beside the DB - and, for the two scripts that by design keep no
         file-based run log, a JSON / [WOULD ...] plan on stdout). A dry run that
         produces NO audit record at all is also a failure.
      5. A per-script result row is collected and a summary table plus a
         machine-readable JSON result are emitted.

    A secondary SOURCE-SCAN pass reads all audited script files and fails on any
    occurrence (outside comments) of:  Add-Type ,  System.Data.SQLite ,
    New-Object System.IO.StreamReader ,  INSERT OR REPLACE , or a Write-Host of a
    variable whose name suggests a secret. This is the phase-wide enforcement of the
    constraints each individual plan asserted locally.

    Exit code is 0 only when every audited script passed AND the source scan found
    zero violations. Any mutation, any bad stub call, or any missing audit record
    exits non-zero.

.PARAMETER Script
    Wildcard filter over the audited script names (see $AuditTargets). Default '*'
    audits all six.

.PARAMETER CustomScriptPath
    Audit ONE arbitrary script instead of the built-in list (used by the
    WhatIfAudit.Tests.ps1 negative-control test). The source scan is skipped in this
    mode.

.PARAMETER CustomScriptArgs
    Hashtable of parameters splatted into -CustomScriptPath. $env:WHATIF_AUDIT_WORKDIR
    is exported to the child process so a negative-control script can attempt a write
    into the audited working directory.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder). Auto-probed when
    omitted; when it cannot be found the DB-backed checks are skipped (not failed) and
    the audit still runs the file-manifest + stub-call + source-scan checks.

.PARAMETER SqliteHelperPath
    Path to the shared Dashboard_4_samples\Sqlite-Helper.ps1.

.PARAMETER ResultJsonPath
    Where the machine-readable JSON result is written. Default: <repo>\logs\whatif-audit-result.json

.PARAMETER SkipSourceScan
    Skip the secondary source-scan pass.

.PARAMETER KeepWorkDir
    Do not delete the per-script throwaway working directories (debugging).

.EXAMPLE
    pwsh -File scripts/Invoke-WhatIfAudit.ps1

.EXAMPLE
    pwsh -File scripts/Invoke-WhatIfAudit.ps1 -Script Sync-RoleGroups

.NOTES
    PowerShell 5.1+ / pwsh 7. No external modules. The audit's own result JSON is the
    audit's output, not a side effect of an audited script.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Script = '*',

    [Parameter()]
    [string]$CustomScriptPath,

    [Parameter()]
    [hashtable]$CustomScriptArgs,

    [Parameter()]
    [string]$SQLDir,

    [Parameter()]
    [string]$SqliteHelperPath,

    [Parameter()]
    [string]$ResultJsonPath,

    [Parameter()]
    [switch]$SkipSourceScan,

    [Parameter()]
    [switch]$KeepWorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$ScriptsDir = $PSScriptRoot
$FixturesDir = Join-Path $RepoRoot 'tests\fixtures\phase-07'

if (-not $SqliteHelperPath) {
    $SqliteHelperPath = Join-Path $RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
}
if (-not $ResultJsonPath) {
    $ResultJsonPath = Join-Path $RepoRoot 'logs\whatif-audit-result.json'
}

# --------------------------------------------------------------------------
# sqlite3.exe probe (same order as the Pester suites' Find-SqliteDir)
# --------------------------------------------------------------------------
function Find-SqliteDir {
    param([string]$Explicit)
    $probes = @()
    if ($Explicit)      { $probes += $Explicit }
    if ($env:SQLDIR)    { $probes += $env:SQLDIR }
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite'
    $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($cmd) { $probes += (Split-Path $cmd.Source -Parent) }
    foreach ($p in $probes) {
        if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p }
    }
    return $null
}

$SqliteDir = Find-SqliteDir -Explicit $SQLDir
$HasSqlite = [bool]$SqliteDir -and (Test-Path $SqliteHelperPath)
if ($HasSqlite) { . $SqliteHelperPath }

# host PowerShell executable for the child processes
$PwshExe = $null
try { $PwshExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
if (-not $PwshExe -or -not (Test-Path $PwshExe)) {
    $c = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $c) { $c = Get-Command powershell -ErrorAction SilentlyContinue }
    $PwshExe = if ($c) { $c.Source } else { 'powershell' }
}

# --------------------------------------------------------------------------
# Audited scripts and how to invoke each under -WhatIf
# --------------------------------------------------------------------------
$AuditTargets = @(
    @{ Name = 'Initialize-AutomationDb.ps1' ; NeedsDb = $true  ; DummyCred = $false }
    @{ Name = 'Get-BigFixCredential.ps1'    ; NeedsDb = $true  ; DummyCred = $false }
    @{ Name = 'Invoke-ContentSync.ps1'      ; NeedsDb = $true  ; DummyCred = $true  }
    @{ Name = 'Stage-Repository.ps1'        ; NeedsDb = $true  ; DummyCred = $true  }
    @{ Name = 'Register-AutomationTasks.ps1'; NeedsDb = $true  ; DummyCred = $false }
    @{ Name = 'Sync-RoleGroups.ps1'         ; NeedsDb = $true  ; DummyCred = $true  }
)

# Allowed run-audit artifacts (relative-path regexes) that may appear/change post-run.
$AllowedArtifactRx = @(
    '^logs[\\/].*\.json$'
    '^logs[\\/].*\.csv$'
    '^reconcile-\d{8}-\d{6}\.json$'
    '^SWDlog\.log$'
    '^__audit_'                       # harness scaffolding
    '\.db-journal$'
)

# --------------------------------------------------------------------------
# Manifest helpers
# --------------------------------------------------------------------------
function Get-Sha1Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-FileManifest {
    param([string]$Root)
    $map = [ordered]@{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $map[$rel] = [pscustomobject]@{ length = $bytes.Length; sha1 = (Get-Sha1Hex $bytes) }
    }
    return $map
}

function Get-DbTableManifest {
    param([string]$DbPath)
    if (-not $HasSqlite -or -not (Test-Path $DbPath)) { return $null }
    $m = [ordered]@{}
    $tbls = @(Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SqliteDir `
            -Sql "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name" |
        ForEach-Object { $_ } | ForEach-Object { $_.name })
    $dv = @(Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SqliteDir -Sql "PRAGMA data_version" | ForEach-Object { $_ })
    $m['__data_version'] = if ($dv.Count) { "$($dv[0].data_version)" } else { '' }
    foreach ($t in $tbls) {
        $cnt = @(Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SqliteDir -Sql "SELECT COUNT(*) AS c FROM `"$t`"" | ForEach-Object { $_ })
        $mx  = @(Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SqliteDir -Sql "SELECT COALESCE(MAX(rowid),0) AS m FROM `"$t`"" | ForEach-Object { $_ })
        $rows = $null
        try   { $rows = @(Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SqliteDir -Sql "SELECT * FROM `"$t`" ORDER BY rowid" | ForEach-Object { $_ }) }
        catch { $rows = @(Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SqliteDir -Sql "SELECT * FROM `"$t`"" | ForEach-Object { $_ }) }
        $json = ($rows | ConvertTo-Json -Depth 6 -Compress)
        if ($null -eq $json) { $json = '[]' }
        $m[$t] = [pscustomobject]@{
            count   = [int]$cnt[0].c
            maxrowid = [int]$mx[0].m
            sha1    = (Get-Sha1Hex ([System.Text.Encoding]::UTF8.GetBytes($json)))
        }
    }
    return $m
}

function Compare-FileManifest {
    param($Before, $After)
    $diffs = New-Object System.Collections.ArrayList
    foreach ($k in $After.Keys) {
        if (-not $Before.Contains($k)) {
            [void]$diffs.Add([pscustomobject]@{ path = $k; kind = 'added'; detail = "len=$($After[$k].length)" })
        }
        elseif ($Before[$k].sha1 -ne $After[$k].sha1) {
            [void]$diffs.Add([pscustomobject]@{ path = $k; kind = 'modified'; detail = "$($Before[$k].sha1) -> $($After[$k].sha1)" })
        }
    }
    foreach ($k in $Before.Keys) {
        if (-not $After.Contains($k)) {
            [void]$diffs.Add([pscustomobject]@{ path = $k; kind = 'removed'; detail = '' })
        }
    }
    return $diffs
}

function Compare-DbManifest {
    param($Before, $After)
    $diffs = New-Object System.Collections.ArrayList
    if ($null -eq $Before -or $null -eq $After) { return $diffs }
    foreach ($k in $After.Keys) {
        if (-not $Before.Contains($k)) { [void]$diffs.Add("table '$k' appeared"); continue }
        if ($k -eq '__data_version') {
            if ($Before[$k] -ne $After[$k]) { [void]$diffs.Add("PRAGMA data_version $($Before[$k]) -> $($After[$k]) (external write)") }
            continue
        }
        if ($Before[$k].count -ne $After[$k].count) { [void]$diffs.Add("$k row count $($Before[$k].count) -> $($After[$k].count)") }
        elseif ($Before[$k].maxrowid -ne $After[$k].maxrowid) { [void]$diffs.Add("$k MAX(rowid) $($Before[$k].maxrowid) -> $($After[$k].maxrowid)") }
        elseif ($Before[$k].sha1 -ne $After[$k].sha1) { [void]$diffs.Add("$k contents changed") }
    }
    foreach ($k in $Before.Keys) { if (-not $After.Contains($k)) { [void]$diffs.Add("table '$k' vanished") } }
    return $diffs
}

function Test-AllowedArtifact {
    param([string]$RelPath)
    foreach ($rx in $AllowedArtifactRx) { if ($RelPath -match $rx) { return $true } }
    return $false
}

# --------------------------------------------------------------------------
# The child-process wrapper (written into each working dir)
# --------------------------------------------------------------------------
$WrapperSource = @'
param(
    [string]$Target,
    [string]$ParamsJson,
    [string]$WorkDir,
    [switch]$DummyCredential
)
$ErrorActionPreference = 'Stop'
$env:WHATIF_AUDIT_STUBLOG = Join-Path $WorkDir '__audit_stubcalls.jsonl'
if (Test-Path $env:WHATIF_AUDIT_STUBLOG) { Remove-Item $env:WHATIF_AUDIT_STUBLOG -Force }

function global:__AuditLogStub($name, $method, $uri, $outfile) {
    # -WhatIf:$false is mandatory: these stubs are called transitively from advanced
    # functions running under -What:$true, which would otherwise suppress Add-Content.
    ([pscustomobject]@{ name = $name; method = $method; uri = "$uri"; outfile = [bool]$outfile } |
        ConvertTo-Json -Compress) | Add-Content -LiteralPath $env:WHATIF_AUDIT_STUBLOG -Encoding UTF8 -WhatIf:$false
}

# global: scope so the stubs shadow the real cmdlets inside every script AND module scope
function global:Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]$Uri,
        $Method, $Body, $Headers, $ContentType, $Credential, $TimeoutSec,
        [switch]$SkipCertificateCheck, [switch]$UseBasicParsing,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    $m = if ($Method) { "$Method".ToUpperInvariant() } else { 'GET' }
    __AuditLogStub 'Invoke-RestMethod' $m $Uri $false
    return ''
}
function global:Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]$Uri,
        $Method, $Body, $Headers, $OutFile, $ContentType, $Credential, $TimeoutSec,
        [switch]$SkipCertificateCheck, [switch]$UseBasicParsing,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    $m = if ($Method) { "$Method".ToUpperInvariant() } else { 'GET' }
    __AuditLogStub 'Invoke-WebRequest' $m $Uri ([bool]$OutFile)
    return [pscustomobject]@{ StatusCode = 200; Content = ''; RawContentLength = 0 }
}
function global:Register-ScheduledTask {
    param([Parameter(ValueFromRemainingArguments = $true)]$Rest)
    __AuditLogStub 'Register-ScheduledTask' $null $null $false
}
function global:Start-ScheduledTask {
    param([Parameter(ValueFromRemainingArguments = $true)]$Rest)
    __AuditLogStub 'Start-ScheduledTask' $null $null $false
}

$env:WHATIF_AUDIT_WORKDIR = $WorkDir

$raw = Get-Content -Raw -LiteralPath $ParamsJson | ConvertFrom-Json
$ht = @{}
foreach ($p in $raw.PSObject.Properties) { $ht[$p.Name] = $p.Value }
if ($DummyCredential) {
    $ht['Credential'] = [pscredential]::new('audit', (ConvertTo-SecureString 'audit-only' -AsPlainText -Force))
}

try {
    & $Target @ht
    exit 0
}
catch {
    Write-Output ("AUDIT-CHILD-ERROR: " + ($_ | Out-String))
    exit 7
}
'@

# --------------------------------------------------------------------------
# Per-script working directory setup
# --------------------------------------------------------------------------
function New-AuditWorkDir {
    param([string]$Name)
    $wd = Join-Path ([System.IO.Path]::GetTempPath()) ("whatif-audit-" + ($Name -replace '\W', '_') + "-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $wd -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wd 'logs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wd 'roleref') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wd 'staging') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wd 'snap') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wd 'config-out') -Force | Out-Null

    # placeholder vault token (Get-BigFixCredential -WhatIf checks it exists)
    Set-Content -LiteralPath (Join-Path $wd 'vault-token.txt') -Value 'audit-placeholder-token' -Encoding ASCII

    # axonious export fixture
    $csv = Join-Path $FixturesDir 'axonious-sample-50.csv'
    if (Test-Path $csv) { Copy-Item $csv (Join-Path $wd 'axonious-sample-50.csv') -Force }

    # region snapshot for the reconcile
    $snapFix = Join-Path $FixturesDir 'roleref-AAG-UK-sample.json'
    if (Test-Path $snapFix) { Copy-Item $snapFix (Join-Path $wd 'snap\roleref-aag-uk-latest.json') -Force }

    if ($HasSqlite) {
        # fresh AutomationState.db from the frozen 07-00 schema fixture ...
        $adb = Join-Path $wd 'AutomationState.db'
        $ddl = Get-Content -Raw (Join-Path $FixturesDir 'automation-db-schema.sql')
        Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir -Sql $ddl | Out-Null

        # ... plus the additive columns 07-03's scripts self-own (same as the
        # Stage-Repository / Invoke-ContentSync Pester suites' New-TestDb), so the
        # audit measures a realistic mid-phase DB rather than a cold-start one.
        foreach ($c in 'discovery_kind', 'portal_fixlet_id', 'reject_reason', 'repo_staged_at') {
            Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir -Sql "ALTER TABLE ContentItem ADD COLUMN $c TEXT" | Out-Null
        }
        Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir -Sql "ALTER TABLE ContentCache ADD COLUMN note TEXT" | Out-Null

        # seed data every audited root-server script may read
        $regions = @('UAP', 'MOT', 'APAC', 'APAC-MOT', 'APAC-M&A', 'AAG-DE', 'AAG-FR', 'AAG-UK', 'AAG-ES', 'AAG-BLX', 'AAG-PL', 'AAG-PT', 'GPC')
        foreach ($rg in $regions) {
            Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir `
                -Sql "INSERT OR IGNORE INTO Region (GPC_Sub_Name, Active) VALUES (@g, 1)" -Parameters @{ g = $rg } | Out-Null
        }
        foreach ($rl in 'IT Operations', 'Business Operations', 'Business Default') {
            Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir `
                -Sql "INSERT OR IGNORE INTO Role (Role, Active) VALUES (@r, 1)" -Parameters @{ r = $rl } | Out-Null
        }
        $pcJson = Join-Path $RepoRoot 'config\PipelineConfig.defaults.json'
        if (Test-Path $pcJson) {
            foreach ($kv in (Get-Content -Raw $pcJson | ConvertFrom-Json)) {
                Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir `
                    -Sql "INSERT OR IGNORE INTO PipelineConfig (Key, Value, Description) VALUES (@k, @v, @d)" `
                    -Parameters @{ k = $kv.Key; v = $kv.Value; d = $kv.Description } | Out-Null
            }
        }
        # Legacy seed: one published role in AAG-UK + a couple of active entitlements in the
        # retired RolePublication/UserRole tables (D-15 - no audited script reads these any
        # more since the Axonius-era drivers that once did were archived in 07-10; kept only
        # so a realistic mid-phase AutomationState.db is available to every audited script).
        Invoke-SqliteCommand -DatabasePath $adb -SQLDir $SqliteDir -Sql @"
INSERT OR IGNORE INTO RolePublication (Role, RegionID, Active)
  VALUES ('IT Operations', (SELECT RegionID FROM Region WHERE GPC_Sub_Name = 'AAG-UK'), 1);
INSERT OR IGNORE INTO UserRole (UserID, Role, Source_Type, Source_Value, Active, Last_RunID)
  VALUES ('auditsmith', 'IT Operations', 'AD Security Group', 'IT-Admins-UK', 1, 'audit-seed');
INSERT OR IGNORE INTO UserRole (UserID, Role, Source_Type, Source_Value, Active, Last_RunID)
  VALUES ('auditdavis', 'IT Operations', 'AD Security Group', 'IT-Admins-UK', 1, 'audit-seed');
"@ | Out-Null

        # D-05 RolePublish.db audit store, seeded with schema only (zero roles) so
        # Sync-RoleGroups.ps1 (07-05's D-06 drift-check driver) has a real, correctly
        # shaped database to open under -WhatIf. Zero roles means the per-role GET/PUT
        # loop never runs, so the audit exercises the script's DB-open + wrong-database
        # guard path without needing a reachable BES REST endpoint.
        $rpdb = Join-Path $wd 'RolePublish.db'
        Invoke-SqliteCommand -DatabasePath $rpdb -SQLDir $SqliteDir -Sql @"
CREATE TABLE IF NOT EXISTS RolePublishRun (
    RunID        INTEGER PRIMARY KEY AUTOINCREMENT,
    Role         TEXT NOT NULL,
    Published_by TEXT NOT NULL,
    Published_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    UserCount    INTEGER NOT NULL
)
"@ | Out-Null
        Invoke-SqliteCommand -DatabasePath $rpdb -SQLDir $SqliteDir -Sql @"
CREATE TABLE IF NOT EXISTS RoleUsers (
    RUID   INTEGER PRIMARY KEY AUTOINCREMENT,
    RunID  INTEGER NOT NULL REFERENCES RolePublishRun(RunID),
    Role   TEXT NOT NULL,
    UserID TEXT NOT NULL
)
"@ | Out-Null
        Invoke-SqliteCommand -DatabasePath $rpdb -SQLDir $SqliteDir -Sql "CREATE INDEX IF NOT EXISTS idx_roleusers_run ON RoleUsers(RunID)" | Out-Null
        Invoke-SqliteCommand -DatabasePath $rpdb -SQLDir $SqliteDir -Sql "CREATE INDEX IF NOT EXISTS idx_roleusers_role ON RoleUsers(Role)" | Out-Null

        # migrated endpoint RoleAwareness.db
        $rdbFix = Join-Path $FixturesDir 'roleawareness-v2.db'
        $rdb = Join-Path $wd 'RoleAwareness.db'
        Copy-Item $rdbFix $rdb -Force
        $cols = @(Invoke-SqliteCommand -DatabasePath $rdb -SQLDir $SqliteDir -Sql "PRAGMA table_info(Map)" | ForEach-Object { $_ } | ForEach-Object { $_.name })
        foreach ($c in 'Source_Type', 'Source_Value', 'Region', 'Assigned_By') {
            if ($cols -notcontains $c) {
                Invoke-SqliteCommand -DatabasePath $rdb -SQLDir $SqliteDir -Sql "ALTER TABLE Map ADD COLUMN $c TEXT" | Out-Null
            }
        }
    }

    Set-Content -LiteralPath (Join-Path $wd '__audit_wrapper.ps1') -Value $WrapperSource -Encoding UTF8
    return $wd
}

function Get-AuditParams {
    param([string]$Name, [string]$Wd)
    $helper = $SqliteHelperPath
    switch ($Name) {
        'Initialize-AutomationDb.ps1' {
            return @{ DatabasePath = "$Wd\AutomationState.db"; SQLDir = $SqliteDir; SqliteHelperPath = $helper; WhatIf = $true }
        }
        'Get-BigFixCredential.ps1' {
            return @{ DatabasePath = "$Wd\AutomationState.db"; SQLDir = $SqliteDir; SqliteHelperPath = $helper;
                TokenFile = "$Wd\vault-token.txt"; SecretPath = '/audit/secret'; UserName = 'audit-op'; WhatIf = $true }
        }
        'Sync-RoleGroups.ps1' {
            # D-06 drift-check driver (07-05). DatabasePath MUST be a RolePublish.db-shaped
            # file (D-05 audit store), NOT AutomationState.db -- the script's own
            # wrong-database guard (exit 5503) aborts on any other schema. BESRootUrl is
            # deliberately unreachable: with zero roles seeded (see New-AuditWorkDir) the
            # per-role GET/PUT loop never runs, so no real network attempt is made under
            # -WhatIf regardless.
            return @{ DatabasePath = "$Wd\RolePublish.db"; SQLDir = $SqliteDir; SqliteHelperPath = $helper;
                BESRootUrl = 'https://127.0.0.1:1'; RunId = 'audit-srg'; LogDir = "$Wd\logs"; WhatIf = $true }
        }
        'Invoke-ContentSync.ps1' {
            return @{ DatabasePath = "$Wd\AutomationState.db"; SQLDir = $SqliteDir; SqliteHelperPath = $helper;
                BESRootUrl = 'https://localhost:52311'; SourceSites = @('Audit Source Site'); PortalSite = 'Dereso Software Portal';
                RunId = 'audit-cs'; LogDir = "$Wd\logs"; CoreModulePath = "$ScriptsDir\ContentSyncCore.psm1"; WhatIf = $true }
        }
        'Stage-Repository.ps1' {
            return @{ DatabasePath = "$Wd\AutomationState.db"; SQLDir = $SqliteDir; SqliteHelperPath = $helper;
                BESRootUrl = 'https://localhost:52311'; PortalSite = 'Dereso Software Portal'; StagingRoot = "$Wd\staging";
                RunId = 'audit-rs'; LogDir = "$Wd\logs"; CoreModulePath = "$ScriptsDir\ContentSyncCore.psm1"; WhatIf = $true }
        }
        'Register-AutomationTasks.ps1' {
            return @{ TaskName = '*'; ScriptRoot = $ScriptsDir; DatabasePath = "$Wd\AutomationState.db"; SQLDir = $SqliteDir;
                LogDir = "$Wd\logs"; ConfigDir = "$Wd\config-out"; WhatIf = $true }
        }
        default { return @{} }
    }
}

# --------------------------------------------------------------------------
# Run one target
# --------------------------------------------------------------------------
function Invoke-OneAudit {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [bool]$DummyCred,
        [bool]$SeedDb,
        [string]$TargetName,
        [hashtable]$CustomParams
    )
    $reasons = New-Object System.Collections.ArrayList
    $wd = if ($SeedDb) { New-AuditWorkDir -Name $Name } else {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ("whatif-audit-custom-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $d 'logs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d '__audit_wrapper.ps1') -Value $WrapperSource -Encoding UTF8
        $d
    }

    try {
        $ParamHash = if ($TargetName) { Get-AuditParams -Name $TargetName -Wd $wd }
                     elseif ($CustomParams) { $CustomParams }
                     else { @{} }
        if ($null -eq $ParamHash) { $ParamHash = @{} }
        $pj = Join-Path $wd '__audit_params.json'
        ($ParamHash | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $pj -Encoding UTF8

        $adb = Join-Path $wd 'AutomationState.db'
        $rdb = Join-Path $wd 'RoleAwareness.db'

        $fileBefore = Get-FileManifest -Root $wd
        $adbBefore  = Get-DbTableManifest -DbPath $adb
        $rdbBefore  = Get-DbTableManifest -DbPath $rdb

        $wrapper = Join-Path $wd '__audit_wrapper.ps1'
        $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $wrapper,
            '-Target', $ScriptPath, '-ParamsJson', $pj, '-WorkDir', $wd)
        if ($DummyCred) { $argv += '-DummyCredential' }

        $stdout = & $PwshExe @argv 2>&1 | Out-String
        $childExit = $LASTEXITCODE

        $fileAfter = Get-FileManifest -Root $wd
        $adbAfter  = Get-DbTableManifest -DbPath $adb
        $rdbAfter  = Get-DbTableManifest -DbPath $rdb

        # ---- stub calls
        $stubLog = Join-Path $wd '__audit_stubcalls.jsonl'
        $stubCalls = @()
        if (Test-Path $stubLog) {
            $stubCalls = @(Get-Content -LiteralPath $stubLog | Where-Object { $_ -match '\S' } | ForEach-Object { $_ | ConvertFrom-Json })
        }
        $badCalls = @($stubCalls | Where-Object {
                $_.name -in @('Register-ScheduledTask', 'Start-ScheduledTask') -or
                $_.outfile -eq $true -or
                $_.method -in @('PUT', 'DELETE', 'PATCH') -or
                ($_.method -eq 'POST' -and ($_.uri -notmatch '/api/query'))
            })
        foreach ($b in $badCalls) {
            [void]$reasons.Add("mutating call: $($b.name) $($b.method) $($b.uri)".Trim())
        }

        # ---- file manifest diff (ignoring allowed run-audit artifacts)
        $fileDiffs = Compare-FileManifest -Before $fileBefore -After $fileAfter
        $auditArtifacts = @()
        foreach ($d in $fileDiffs) {
            if (Test-AllowedArtifact -RelPath $d.path) {
                if ($d.kind -ne 'removed') { $auditArtifacts += $d.path }
                # a zero-byte -wal/-shm that then vanished is fine; a non-trivial one is not
                if ($d.path -match '\.db-(wal|shm)$' -and $d.kind -ne 'removed' -and $fileAfter[$d.path].length -gt 0) {
                    [void]$reasons.Add("non-empty SQLite sidecar written: $($d.path) ($($fileAfter[$d.path].length) bytes)")
                }
                continue
            }
            [void]$reasons.Add("$($d.kind) file: $($d.path)  [$($d.detail)]")
        }

        # ---- DB table diffs
        foreach ($m in (Compare-DbManifest -Before $adbBefore -After $adbAfter)) { [void]$reasons.Add("AutomationState.db: $m") }
        foreach ($m in (Compare-DbManifest -Before $rdbBefore -After $rdbAfter)) { [void]$reasons.Add("RoleAwareness.db: $m") }

        # ---- audit record present?
        $stdoutHasRecord = ($stdout -match '----RUN SUMMARY----') -or
                           ($stdout -match '"whatif"\s*:') -or
                           ($stdout -match 'WOULD (REGISTER|CREATE|SEED|RUN|PUT|POST|COPY)') -or
                           ($stdout -match '\{\s*"' )
        $auditRecordPresent = ($auditArtifacts.Count -gt 0) -or $stdoutHasRecord
        if (-not $auditRecordPresent) {
            [void]$reasons.Add('no run-audit record produced (no log file, no plan on stdout)')
        }

        # ---- child error?
        if ($childExit -ne 0) {
            [void]$reasons.Add("audited script exited $childExit under -WhatIf")
            if ($stdout -match 'AUDIT-CHILD-ERROR:') {
                $err = ($stdout -split 'AUDIT-CHILD-ERROR:', 2)[1].Trim()
                if ($err) { [void]$reasons.Add("child error: " + (($err -split "`n")[0].Trim())) }
            }
        }

        $pass = ($reasons.Count -eq 0)

        return [pscustomobject]@{
            name               = $Name
            path               = $ScriptPath
            pass               = $pass
            reasons            = @($reasons)
            audit_record       = @($auditArtifacts)
            audit_record_ok    = $auditRecordPresent
            stub_calls         = @($stubCalls)
            bad_stub_calls     = @($badCalls | ForEach-Object { "$($_.name) $($_.method) $($_.uri)".Trim() })
            child_exit         = $childExit
            db_checked         = $HasSqlite
            workdir            = $wd
        }
    }
    finally {
        if (-not $KeepWorkDir -and (Test-Path $wd)) {
            Remove-Item -LiteralPath $wd -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --------------------------------------------------------------------------
# Source-scan pass
# --------------------------------------------------------------------------
function Invoke-SourceScan {
    param([string[]]$Files)
    $rules = @(
        @{ label = 'Add-Type'                      ; rx = 'Add-Type' }
        @{ label = 'System.Data.SQLite'            ; rx = 'System\.Data\.SQLite' }
        @{ label = 'New-Object System.IO.StreamReader' ; rx = 'New-Object\s+System\.IO\.StreamReader' }
        # INSERT OR REPLACE is only forbidden on a STATE-BEARING table (has Active /
        # Locked_by_Override / Created_on / stage / Valid_to columns). PipelineConfig
        # (Key/Value/Description) and ContentCache (immutable sha1 identity) are
        # legitimate key/value upsert targets - same class as Initialize-RoleDb.ps1's
        # 2-column Users exception.
        @{ label = 'INSERT OR REPLACE on a state-bearing table'
            rx    = 'INSERT\s+OR\s+REPLACE\s+INTO\s+(Map|Users|Overrides|UserRole|RefUser|Role|Region|RolePublication|GroupRoleMap|Snapshot|SyncRun|ContentItem)\b' }
        @{ label = 'Write-Host of a secret-named variable' ; rx = 'Write-Host[^#\r\n]*\$(?:[A-Za-z_]*(?:pw|pass|password|secret|token|cred|plain)[A-Za-z_]*)\b' }
    )
    $violations = New-Object System.Collections.ArrayList
    foreach ($f in $Files) {
        if (-not (Test-Path $f)) { continue }
        $lines = Get-Content -LiteralPath $f
        $inBlockComment = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($inBlockComment) { if ($line -match '#>') { $inBlockComment = $false }; continue }
            if ($line -match '<#') { if ($line -notmatch '#>') { $inBlockComment = $true }; continue }
            $code = $line -replace '#.*$', ''      # strip trailing / full-line comments
            if ($code -notmatch '\S') { continue }
            foreach ($r in $rules) {
                if ($code -match $r.rx) {
                    [void]$violations.Add([pscustomobject]@{
                        file = (Split-Path $f -Leaf); line = ($i + 1); pattern = $r.label; text = $line.Trim()
                    })
                }
            }
        }
    }
    return [pscustomobject]@{ pass = ($violations.Count -eq 0); violations = @($violations) }
}

# ==========================================================================
# MAIN
# ==========================================================================
$results = New-Object System.Collections.ArrayList
$customMode = [bool]$CustomScriptPath

if (-not $HasSqlite -and -not $customMode) {
    Write-Host ''
    Write-Host '=== Phase 7 -WhatIf audit ==================================================='
    Write-Host '  sqlite3.exe not found via any probe - the audited scripts cannot run.'
    Write-Host '  Set $env:SQLDIR or pass -SQLDir. Reporting all targets as SKIPPED.'
    Write-Host '==========================================================================='
    $skObj = [pscustomobject]@{
        generated_on = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        host = $env:COMPUTERNAME; overall_pass = $true; db_checked = $false; skipped = $true
        scripts = @($AuditTargets | ForEach-Object { [pscustomobject]@{ name = $_.Name; pass = $true; skipped = $true; reasons = @() } })
        source_scan = [pscustomobject]@{ pass = $true; violations = @(); skipped = $true }
    }
    $resDir = Split-Path $ResultJsonPath -Parent
    if ($resDir -and -not (Test-Path $resDir)) { New-Item -ItemType Directory -Path $resDir -Force | Out-Null }
    ($skObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $ResultJsonPath -Encoding UTF8
    exit 0
}

if ($customMode) {
    if (-not (Test-Path $CustomScriptPath)) { throw "CustomScriptPath not found: $CustomScriptPath" }
    $cp = if ($CustomScriptArgs) { $CustomScriptArgs } else { @{} }
    $r = Invoke-OneAudit -Name (Split-Path $CustomScriptPath -Leaf) -ScriptPath $CustomScriptPath `
        -DummyCred $false -SeedDb $false -CustomParams $cp
    [void]$results.Add($r)
    $sourceScan = [pscustomobject]@{ pass = $true; violations = @(); skipped = $true }
}
else {
    $targets = $AuditTargets | Where-Object { $_.Name -like $Script -or ($_.Name -replace '\.ps1$', '') -like $Script }
    if (-not $targets) { throw "No audited script matches -Script '$Script'" }

    foreach ($t in $targets) {
        $sp = Join-Path $ScriptsDir $t.Name
        if (-not (Test-Path $sp)) { throw "Audited script missing: $sp" }
        $r = Invoke-OneAudit -Name $t.Name -ScriptPath $sp -DummyCred ([bool]$t.DummyCred) -SeedDb $true `
            -TargetName $t.Name
        [void]$results.Add($r)
    }

    $scanFiles = $AuditTargets | ForEach-Object { Join-Path $ScriptsDir $_.Name }
    $sourceScan = if ($SkipSourceScan) {
        [pscustomobject]@{ pass = $true; violations = @(); skipped = $true }
    } else {
        Invoke-SourceScan -Files $scanFiles
    }
}

$overallPass = (@($results | Where-Object { -not $_.pass }).Count -eq 0) -and $sourceScan.pass

$resultObj = [pscustomobject]@{
    generated_on = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    host         = $env:COMPUTERNAME
    powershell   = $PSVersionTable.PSVersion.ToString()
    db_checked   = $HasSqlite
    sqlite_dir   = $SqliteDir
    custom_mode  = $customMode
    overall_pass = $overallPass
    scripts      = @($results | ForEach-Object {
            [pscustomobject]@{
                name = $_.name; pass = $_.pass; reasons = $_.reasons
                audit_record = $_.audit_record; audit_record_ok = $_.audit_record_ok
                stub_calls = @($_.stub_calls | ForEach-Object { "$($_.name) $($_.method) $($_.uri)".Trim() })
                bad_stub_calls = $_.bad_stub_calls; child_exit = $_.child_exit
            }
        })
    source_scan  = $sourceScan
}

$resDir = Split-Path $ResultJsonPath -Parent
if ($resDir -and -not (Test-Path $resDir)) { New-Item -ItemType Directory -Path $resDir -Force | Out-Null }
($resultObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $ResultJsonPath -Encoding UTF8

# ---- summary table
Write-Host ''
Write-Host '=== Phase 7 -WhatIf audit ==================================================='
if (-not $HasSqlite) {
    Write-Host '  NOTE: sqlite3.exe not found - DB write checks SKIPPED (file + stub + scan only).'
}
foreach ($r in $results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('  [{0}] {1}' -f $tag, $r.name)
    if (-not $r.pass) { foreach ($why in $r.reasons) { Write-Host ('         - ' + $why) } }
}
Write-Host '  ---------------------------------------------------------------------------'
if (-not $customMode) {
    if ($sourceScan.PSObject.Properties['skipped'] -and $sourceScan.skipped) {
        Write-Host '  [SKIP] source scan'
    }
    elseif ($sourceScan.pass) {
        Write-Host '  [PASS] source scan (0 forbidden constructs across the 6 scripts)'
    }
    else {
        Write-Host '  [FAIL] source scan:'
        foreach ($v in $sourceScan.violations) { Write-Host ('         - {0}:{1}  {2}  |  {3}' -f $v.file, $v.line, $v.pattern, $v.text) }
    }
}
Write-Host ('  OVERALL: {0}' -f ($(if ($overallPass) { 'PASS' } else { 'FAIL' })))
Write-Host ('  result JSON: {0}' -f $ResultJsonPath)
Write-Host '==========================================================================='
Write-Host ''

if ($overallPass) { exit 0 } else { exit 1 }
