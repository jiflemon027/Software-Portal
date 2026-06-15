---
document_type: validation
phase: 3
phase_name: Dispatcher (Rapid Deployment)
created: 2026-06-14
status: active
---

# Phase 3: Dispatcher (Rapid Deployment) — Validation Strategy

## Test Framework

| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert` (no external framework) |
| Config file | None — tests are standalone scripts |
| Quick run command | `node tests/unit/dispatcher.test.js` |
| Full suite command | `node tests/unit/dispatcher.test.js && node tests/unit/modifier.test.js && node tests/unit/copier.test.js` |

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FR-05 | `buildTargetRelevance(groupName)` produces syntactically valid relevance expression | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-05 | `buildTargetRelevance("")` produces `"true"` fallback | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-05 | POST round-trip: buildDeployXml output accepted with HTTP 200/201 | integration | `node tests/integration/dispatcher.integration.test.js` | ❌ Wave 0 |
| FR-06 | `buildDeployXml()` XML contains `<IsOffer>true</IsOffer>` | unit (string assert on buildDeployXml helper) | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-06 | Offer category in XML matches fixlet category | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-07 | `buildExpirationElement(7)` produces `P7D` duration element | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-07 | `PORTAL_CONFIG.defaultExpirationDays` is 7 (or positive integer) | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-07 | `PORTAL_CONFIG.targetGroups` is a non-empty array of strings | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| NFR-01 | POST /api/actions round-trip completes in < 5000ms | integration | `node tests/integration/dispatcher.integration.test.js` | ❌ Wave 0 |
| NFR-02 | API error handling: error response surfaced in callback, not swallowed | integration | `node tests/integration/dispatcher.integration.test.js` | ❌ Wave 0 |
| NFR-05 | `parseActionId(body)` correctly extracts numeric ID from regex-path fixture | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |

## Sampling Rate

- **Per task commit:** `node tests/unit/dispatcher.test.js`
- **Per wave merge:** `node tests/unit/dispatcher.test.js && node tests/unit/modifier.test.js && node tests/unit/copier.test.js`
- **Phase gate:** All three unit suites green; integration test skips gracefully without live BigFix

## Wave 0 Gaps (Created by Plan 03-01)

- [ ] `tests/unit/dispatcher.test.js` — covers FR-05 (target relevance), FR-06 (offer XML elements), FR-07 (expiry + config), NFR-05 (parseActionId)
- [ ] `tests/integration/dispatcher.integration.test.js` — covers FR-05 POST round-trip, NFR-01 timing, NFR-02 error handling
- [ ] `tests/fixtures/phase-03/valid-fixlet-with-actions.ojo` — multi-action fixlet fixture for action parsing tests
- [ ] `tests/fixtures/phase-03/valid-fixlet-single-action.ojo` — single DefaultAction fixture
- [ ] `tests/fixtures/phase-03/sample-action-response.xml` — BESAPI response fixture for parseActionId unit tests

## Security Validation Coverage

| Threat Pattern | Test Coverage |
|---------------|---------------|
| XML injection via group name in buildDeployXml | Unit test: `buildDeployXml()` with group name containing `<`, `>`, `'`, `"` characters |
| XSS via fixlet name/category in DOM | Unit test: `buildTargetRelevance()` with special characters |
| Relevance injection via group name | Unit test: single-quote in group name does not break relevance syntax |
| Empty target guard (deployment to all computers) | Unit test: `deployFixlet()` called without selectedTargetGroup returns error before building XML |
| CDATA double-escaping of description | Unit test: `buildDeployXml()` description field is CDATA-wrapped, not XML-escaped |

---

*Extracted from 03-RESEARCH.md Validation Architecture section*
*Phase: 03-dispatcher-rapid-deployment*
*Created: 2026-06-14*
