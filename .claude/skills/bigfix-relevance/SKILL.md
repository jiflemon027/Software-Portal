---
name: bigfix-relevance
description: BigFix relevance, ActionScript, and dashboard (.ojo) quirks specific to this project's Dereso Software Portal family — three distinct relevance dialects, ActionScript brace escaping, SingleAction XML structure, MIME field patterns, prefetch rewriting, and known REST/POST gotchas. Use when writing or debugging .ojo dashboards, ActionScript, .bes Analysis/Task/Fixlet files, or anything that builds/parses BigFix relevance strings.
---

# BigFix Relevance & Dashboard Patterns (Dereso Software Portal)

Knowledge accumulated across this project's copier/modifier/dispatcher/role-assigner
dashboards and their supporting `.bes`/PowerShell files. Verify claims against current
code before treating them as fact — these are point-in-time observations, not a spec.

## 1. Three distinct relevance dialects — don't mix them up

This is the source of the most confusing bugs in this codebase. BigFix has (at least)
three separate places relevance-like expressions get evaluated, with different
capabilities and different syntax contexts:

| Dialect | Where it runs | Where it's written | Can it read files/registry? |
|---|---|---|---|
| **Session relevance** | BES root server, over the cached BES object model (computers, fixlets, actions, sites, properties) | `EvaluateRelevance(str)` calls from OJO dashboard JS | No raw OS inspectors (`file`, `folder`, `registry key`) — only the BES object model, including **retrieved property values** (`values of properties whose(...) of bes computer whose(...)`) |
| **Client/Fixlet relevance** | The individual BES Client agent, locally on its own machine | `<Relevance>` in Fixlets/Tasks/Analyses, `<CustomRelevance>` in SingleAction `<Target>`, and inline `{...}` substitutions inside ActionScript | Yes — `file`, `folder`, `registry key`, `client`, etc. all work here, because this dialect runs as the actual client agent on that machine |
| **`<?relevance ?>` tag substitution** | The BigFix **console**, at dashboard render time, before any JS runs | Directly inside OJO `<Head>`/`<HTML>` CDATA content — including inside JS string literals | Console-side session relevance semantics (same as `EvaluateRelevance`) |

**Practical fallout:**
- Wanting "does this file exist on the root server's disk right now" from a dashboard?
  You can't do it with `EvaluateRelevance()` directly — session relevance has no file
  inspector. The working pattern is a **retrieved property** on a BES Analysis assigned
  to the root server (client relevance, which *can* read files/registry), then read that
  property's last-reported value via session relevance:
  ```js
  // Session relevance: read a retrieved-property value for one computer, with a
  // guard for "no result yet" (results() tuple form — see §6).
  var rel = '(( if (exists results (item 0 of it, item 1 of it) and exists values of results (item 0 of it, item 1 of it)) '
    + 'then (concatenation "" of values of results (item 0 of it, item 1 of it)) else "") of it) '
    + 'of (bes computers whose (id of it as string = "' + safeId + '"), bes property "Some Property Name")';
  ```
  The property's own `<Property>` body in the `.bes` Analysis is client relevance and
  CAN use `file`/`folder`/`registry key` freely — see `Dashboard_4_samples/"Dereso SWD
  Repository Cache.bes"` for a working example.
- Need a **static-per-render** config value (e.g. "this console's root server's Computer
  ID")? Use a `<?relevance ?>` tag directly in the JS, not a runtime `EvaluateRelevance()`
  wrapper function — simpler, and confirmed working in this environment:
  ```js
  rootServerComputerId: '<?relevance concatenation "" of ((id of it as string) of bes computers '
    + 'whose(exists value whose (it = "BES Root Server") of result (it, bes property '
    + '"BES Relay Service Installed"))) ?>'
  ```
  This resolves once, at console render time — by the time IE9's JS engine sees it,
  it's already a plain string. Reserve runtime `EvaluateRelevance()` for values that
  must be recomputed after user interaction (per-selected-fixlet queries, etc.).
- Need a value from a **specific client** at deploy time, passed into an ActionScript?
  Use `{...}` inline substitution — client relevance, evaluated on that client when the
  action runs. E.g. the client's own Computer ID: `{computer id}` — **not**
  `{id of computer}`, which does not resolve correctly in ActionScript context (confirmed
  during Phase 4 UAT of `fixlet_role_assigner.ojo` — produced an empty/wrong value that
  broke CSV-matrix matching).

## 2. ActionScript brace escaping (embedding PowerShell via `createfile`)

Inside ActionScript, bare `{...}` is the client-relevance substitution syntax (§1). Any
PowerShell embedded via `createfile until _EOF_ ... _EOF_` that contains literal `{` or
`}` (scriptblocks, hashtables, `if`/`foreach`/`try`/`catch`) needs escaping — but the
rule is **asymmetric**, and getting it wrong in either direction breaks the script:

- **Opening `{` → double it: `{{`.** This is BigFix's escape for a literal `{`.
- **Closing `}` → leave it bare, single.** `{{` never opens a real substitution, so
  there's nothing for a later `}` to close — it just passes through as a literal
  character on its own.

```powershell
# Source (normal PowerShell)
if ($x -eq 1) { Write-Host "yes" }

# Correctly escaped for embedding in ActionScript
if ($x -eq 1) {{ Write-Host "yes" }
```

**Doubling `}` too is a bug, not "more correct."** `s.replace(/\{/g,"{{").replace(/\}/g,"}}")`
produces a visibly doubled `}}` at the end of every function/block in the output —
confirmed directly in `fixlet_dispatcher.ojo`'s staging-action script. The only correct
transform is `s.replace(/\{/g, "{{")` — nothing else. Verified against the one other
embedded-PS1 example in this codebase, `Dashboard_4_samples/"Init  Current User and
UserRole DB.bes"`, which consistently only doubles `{`.

Note: intentional relevance substitutions like `{parameter "Role"}` or `{computer id}`
must NOT be touched by this escaping — only literal PowerShell structural braces need it.

Alternative: prefetching the script as a file resource instead of inline `createfile`
avoids the escaping problem entirely, at the cost of needing a hosted URL for it.

## 3. Deployed-action architecture

**SingleAction vs SourcedFixletAction** — use `SingleAction` for any deployment that
targets a dynamic computer group:
- `SourcedFixletAction` evaluates `<CustomRelevance>` **server-side**. Group-membership
  expressions (`member of group X of site Y`) can't be resolved server-side, so it
  silently returns 0 relevant computers.
- `SingleAction` evaluates `<CustomRelevance>` **client-side**, on each endpoint —
  group membership resolves correctly. This matches BigFix's own Software Installer
  Library (`install.js confirmSelection`, `ActionTargetByCustomRelevance`).
- Use `SourcedFixletAction` only for static computer lists.

**SingleAction element order matters** (per ADFAPI.js `orderedFields`):
```
Title → Relevance → ActionScript → [SuccessCriteria] → Settings →
[SettingsLocks] → [IsUrgent] → Target → [MIMEFieldSingleAction]
```
`<Target>` must come **after** `<Settings>` — putting it before causes a 400 Bad Request.
For a fixed single computer (not a dynamic group), `<Target>` takes a plain
`<ComputerID>` instead of `<CustomRelevance>`:
```xml
<Target><ComputerID>1622424793</ComputerID></Target>
```

**Fixlets can have multiple `<Relevance>` elements** — a generic platform check plus one
or more app-specific conditions, all ANDed together. `getNodeText(xml, "Relevance")`
only returns the first and silently drops the rest. Always walk `childNodes` of
`<Fixlet>`/`<Task>` and collect every `nodeName === "Relevance"` node, then join as
`"(" + parts.join(") AND (") + ")"` when there's more than one.

**MIME fields don't carry over automatically** into a `SingleAction` the way they do for
`SourcedFixletAction`. Explicitly copy them via `<MIMEFieldSingleAction>` elements placed
after `<Target>`, before `</SingleAction>`:
```xml
<MIMEFieldSingleAction>
  <Name>field-name</Name>
  <Value>field value (XML-escaped)</Value>
</MIMEFieldSingleAction>
```
Extraction pattern (IE9/MSXML):
```javascript
var nodes = fxml.getElementsByTagName("MIMEField");
for(var i = 0; i < nodes.length; i++){
  var nameNode = nodes[i].selectSingleNode("Name");
  if(nameNode && nameNode.text.replace(/^\s+|\s+$/g,"") === "target-field-name"){
    var val = nodes[i].selectSingleNode("Value").text;
  }
}
```
`fixlet_dispatcher.ojo` currently carries: `action-ui-metadata` (icon/version/size JSON,
omitted if absent), `Associated_Roles` (pipe-delimited role list, omitted if absent),
and always emits `SmartRole_Source` — `{"id":"<fixlet-id>","sitename":"<site-name>","targetGroup":"<group-name>"}`
— for downstream role resolution and duplicate-deployment detection.

**Verifying a deployed action's actual content:** the client receives two files —
`_offer<ID>.html` (end-user display template, does NOT contain MIME field metadata —
its absence there doesn't mean the action lacks it) and `Action <ID>.fxf` (the
authoritative payload the client actually reads/evaluates, full XML including
`MIMEFieldSingleAction`, relevance, script). Always check the `.fxf`, not the offer HTML,
when confirming what actually got deployed.

## 4. Prefetch URL rewriting (local repository staging)

`rewritePrefetchUrls(script)` in `fixlet_dispatcher.ojo` redirects prefetch downloads to
a local managed repository on the root server at deploy time:
```js
return script.replace(
  /^(prefetch\s+(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:\d+\s+)\S+((?:\s+sha256:[0-9a-fA-F]+)?)$/gim,
  function(match, leader, filename, sha1, tail){
    var newLine = leader + 'http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/' + sha1 + '/' + filename + tail;
    return '// ' + match + '\r\n' + newLine;
  }
);
```
- Local URL: `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/{sha1}/{filename}`
- Directory name = the sha1 from the existing `sha1:` token; filename = the token right
  after `prefetch`.
- Original line is preserved as a `// prefetch ...` comment immediately above the rewrite.
- The on-disk path the root server serves that URL from is derived from the registry:
  `HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server` → value `wwwRootFolder`, then
  append `Uploads\CustomRepository\SoftwarePortal` (no extra leading `\` — `wwwRootFolder`
  already ends in one). `Invoke-PrefetchStage.ps1` (repo root) stages a file there given
  a raw prefetch line, idempotently (skips if already staged with a matching SHA1).
- `extractPrefetchLines(script)` (same file) parses the **unrewritten** script to recover
  the original internet URL(s) — needed when staging the file from its real source rather
  than the now-local rewritten URL.

## 5. Root-server / client folder conventions

- BES Client's own EC folder (used for staging ad hoc scripts, no site-specific
  subfolder): `pathname of folder "EC" of parent folder of client` →
  `C:\Program Files (x86)\BigFix Enterprise\BES Client\EC`.
- Site-specific persistent data folder (used for `RoleAwareness.db` and similar):
  `parent folder of parent folder of client folder of site "actionsite"`, then append
  `EC`, `SoftwarePortal` as path segments — the `Dereso SWD.bes` / `fixlet_modifier.ojo`
  convention:
  ```
  (concatenation (if windows of operating system then "\" else "/") of
    (item 0 of it; item 1 of it; item 2 of it) of
    ((pathname of parent folder of parent folder of client folder of site "actionsite")
      as string, "EC", "SoftwarePortal"))
  ```
- These two are **not the same folder** — don't conflate "the client's generic EC" with
  "this site's EC/SoftwarePortal data folder."

## 6. Session-relevance idioms worth reusing

- **Guarded property read for one computer** (avoids errors when the property hasn't
  reported yet): the `results(item0, item1)` tuple form shown in §1. Confirmed working
  pattern for reading a BES Analysis property's last value from a dashboard.
- **Registry access** (client relevance only, e.g. inside a `.bes` Property body):
  `value "wwwRootFolder" of key "HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\BigFix\Enterprise Server" of registry`
- **Escaping a literal double quote inside a relevance string literal:** use `""`
  (doubled), not `\"` — e.g. `'"__Group_0_' + safeName.replace(/"/g,'""') + '"'`.
- **JSON parsing inside relevance** (recent BigFix versions): `value of key "x" of (json of it)`
  works against a string containing JSON — used to pull `targetGroup` back out of the
  `SmartRole_Source` MIME field value for duplicate-deployment checks. Double-check any
  literal key name matches exactly what's written elsewhere (a typo like
  `"targetedGroup"` vs `"targetGroup"` silently makes the guard always false).

## 7. REST API gotchas

**Copying a Task's XML into `fixlets/custom/<site>` returns 400.** Don't modify Task XML
in place and try to strip offending elements one-by-one — there are multiple, and it
becomes a multi-round debugging loop (`<ID>`, `<MIMEField>` external-site metadata,
`<Delay>`, possibly `<SuccessCriteria>`, plus element ordering). Instead, **build the POST
XML from scratch**, extracting only the fields you need via `getElementsByTagName`, in
schema order:
```
Title → Description → Relevance(s) → Category → Source → SourceID →
SourceReleaseDate → SourceSeverity → CVENames → SANSID →
MIMEField(s) → Domain → DefaultAction / Action(s)
```
Reference implementation: `fixlet_copier.ojo`'s `buildXml()`.

## 8. `.beswrpt` Web Reports format

Raw HTML — no `<BESReport>` XML wrapper, no CDATA — is the confirmed working format on
this environment. A `<BESReport><Main><![CDATA[...]]></Main></BESReport>` wrapper gets
served with literal `]]>` text visible on the page, and `<![CDATA[` parses as a bogus
HTML comment that swallows `<!DOCTYPE html>`, breaking JS entirely. Use the async
`Relevance(queryString, { success, failure })` JS API for data loading, not server-side
`<Relevance>` injection tags. DataTables CSS/JS are served from `/JavaScript/datatables/`
on the Web Reports server itself (no CDN) — must be pre-loaded there or the table
silently fails to initialize. Include `<meta http-equiv="X-UA-Compatible" content="IE=9">`
as the first meta tag, matching every other dashboard in this family.

## Related, not duplicated here

- **SQLite from PowerShell:** `Dashboard_4_samples/Sqlite-Helper.ps1` wraps `sqlite3.exe`
  (CLI, not `System.Data.SQLite.dll`/`Add-Type`, which fails under Constrained Language
  Mode). See project memory `sqlite-helper-pattern` for usage.
- **RoleAwareness.db schema:** see project memory `bigfix-role-relevance-schema` for
  current columns/joins — schema has changed before (ID-based → Role-name joins) and may
  again; treat as point-in-time.
- **`.ojo` file editing safety:** never save `.ojo` files from inside VS Code while
  Claude has them open — a past incident overwrote one with error text. All edits should
  go through Claude's Edit/Write tools. See project memory `ojo-file-safety`.
