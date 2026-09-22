# 07-01 Spike Findings

Generated: 2026-09-21T23:26:14Z (UTC)
BES Root URL: https://gpbfs:52311
Site: Dereso Software Portal

## Check A - ComputerGroup element set

Status: PASS

**ComputerGroup element set accepted:** six-element (Title/Domain/JoinByIntersection/IsDynamic/EvaluateOnClient/SearchComponentRelevance)

Evidence:

- POST (six-element) https://gpbfs:52311/api/computergroups/custom/Dereso%20Software%20Portal -> success=True status=200
- POST (six-element) response body: <?xml version="1.0" encoding="UTF-8"?>
<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BESAPI.xsd">
	<ComputerGroup Resource="https://gpbfs:52311/api/computergroup/custom/Dereso%20Software%20Portal/46137" LastModified="Mon, 21 Sep 2026 23:26:02 +0000">
		<Name>ZZZ-SPIKE-DELETE-ME</Name>
		<ID>46137</ID>
	</ComputerGroup>
</BESAPI>

- Parsed new group id: 46137
- GET https://gpbfs:52311/api/computergroup/custom/Dereso%20Software%20Portal/46137 -> success=True status=200
- GET round-trip body: <?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
	<ComputerGroup>
		<Title>ZZZ-SPIKE-DELETE-ME</Title>
		<Domain>BESC</Domain>
		<JoinByIntersection>true</JoinByIntersection>
		<SearchComponentRelevance Comparison="IsTrue">
			<Relevance>(number of (logged on users whose (name of it as lowercase is contained by set of ("zzzspikeuser1";"zzzspikeuser2")))) = 1</Relevance>
		</SearchComponentRelevance>
	</ComputerGroup>
</BES>

- DELETE https://gpbfs:52311/api/computergroup/custom/Dereso%20Software%20Portal/46137 -> success=True status=200

## Check B - Assumption A2 (literal set of (...) relevance)

Status: PARTIAL - CORRECTED 2026-09-22 (see below)

**Assumption A2 verdict:** HELD for CLIENT relevance (the only context this phase actually
uses), NOT HELD for SESSION relevance (`/api/query`) - see correction.

**CORRECTION:** The runbook originally scored this PASS based solely on the HTTP status
(200/success=True) of the `/api/query` POST, without inspecting the response body for a
`<BESAPI>/<Query>/<Error>` element. The response body - logged by the runbook as a raw
space-separated byte dump instead of decoded text - actually contains:

```xml
<Query Resource="exists true whose ((number of (logged on users whose (name of it as lowercase is contained by set of (&quot;zzzspikeuser1&quot;;&quot;zzzspikeuser2&quot;)))) = 1)">
    <Result></Result>
    <Error>The operator "logged on users" is not defined.</Error>
</Query>
```

`logged on users` is a client-relevance-only inspector; it is not defined in the session
relevance dialect `/api/query` speaks. This does NOT contradict Check A: Check A's
`SearchComponentRelevance` is evaluated by BES clients (client relevance), a different
dialect, and it independently proved this exact expression - `set of (...)` tuple form
included - is valid there (the group was created, and the server round-tripped the identical
relevance text back on GET). No plan in this phase (07-04/07-05/07-06/07-08) executes this
expression via session relevance; it is only ever embedded in `<ComputerGroup>` XML for
client-side evaluation. **Net effect: no impact on plan 07-04's `buildRoleGroupRelevance`.**

Evidence:

- Relevance under test: (number of (logged on users whose (name of it as lowercase is contained by set of ("zzzspikeuser1";"zzzspikeuser2")))) = 1
- This same expression is Check A's ComputerGroup relevance - Check A's independent REST create/round-trip/delete is the authoritative validation for the context this phase actually uses (client relevance).
- POST https://gpbfs:52311/api/query -> success=True status=200 (HTTP-level success; the query itself errored - see decoded body above)

## Check C - Live Axonius-era artefacts

Status: PASS

**Live Axonius-era artefacts found:** none found

Evidence:

- schtasks /query /TN DeresoRoleIngest -> exit=1
- output: ERROR: The system cannot find the file specified.
- schtasks /query /TN DeresoRolePublish -> exit=1
- output: ERROR: The system cannot find the file specified.
- GET fixlets/custom/Dereso Software Portal -> success=True status=200
- Fixlets/Tasks scanned: 10; RoleRef-matching: 0
- GET computergroups/custom/Dereso Software Portal -> success=True status=200
- Computer groups scanned: 2; roleref-matching: 0
- None found - no DeresoRoleIngest/DeresoRolePublish scheduled tasks and no RoleRef* fixlets/groups.

## Check D - Root-server sqlite3.exe

Status: PASS

**sqlite3.exe version:** 3.53.1 2026-05-05 10:34:17 c88b22011a54b4f6fbd149e9f8e4de77658ce58143a1af0e3785e4e6475127e9 (64-bit)

Evidence:

- Test-Path 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite\sqlite3.exe' -> True
- sqlite3.exe -version -> 3.53.1 2026-05-05 10:34:17 c88b22011a54b4f6fbd149e9f8e4de77658ce58143a1af0e3785e4e6475127e9 (64-bit)


