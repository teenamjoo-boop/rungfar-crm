# RUNGFA CRM — TEST PLAN AND VERIFIED HISTORY

> Test strategy, completed evidence, and future test matrix.
>
> Latest verified **runtime** closeout: Employer CRUD (Admin), Staging 2026-07-26 — see section 8d.
>
> Latest verified **design** closeout: `LINE-PDF-DUAL-MODE-DESIGN`, 2026-08-05 — design review only, **no runtime test executed** — see section 8e.
>
> Latest verified **Staging Storage** evidence: PDF icon upload (owner Dashboard action, 2026-08-06) + read-only object verification (2026-08-07) — Storage foundation only, **not** a LINE runtime or helper acceptance — see section 8g.
>
> Prior historical closeouts: F1 Payment-specific Stage, 2026-07-14 (section 7); Stage 58K-C, 2026-07-13 (section 4). Live values must be re-checked before new tests.

## 1. Testing principles

1. Staging first.
2. Synthetic/marker-scoped data only for destructive or ownership tests.
3. One stage and one operator action at a time.
4. Read-only pre-check before each mutation.
5. Exact Expected vs Actual verification after each action.
6. Verify audit, privacy, counts, ownership, and unrelated invariants.
7. Cleanup/restore and confirm baseline before closing the stage.
8. Never fix a product gap during a smoke test unless that gap is the explicit stage objective.
9. Production smoke is a separate, minimal, non-destructive plan after Staging approval.

## 2. Standard stage test lifecycle

```text
Pre-flight Git/environment
→ DB baseline and fixture resolver (SELECT only)
→ Frontend selector/payload contract
→ Backend RPC/ownership/audit contract
→ Stop for user approval
→ User performs one UI/SQL action
→ Post-action SELECT-only verification
→ Audit/privacy verification
→ Cleanup/restore if in scope
→ Baseline verification
→ Verdict and documentation update
```

### Required pre-flight evidence

- Correct repo/path/branch/HEAD/tree.
- Correct Staging project ref.
- Zero Production refs in Staging local HTML/command.
- Exact fixture IDs resolved from live DB, not memory.
- Actual function signature/overload.
- Current counts/statuses and stop conditions.

### Required post-action evidence

- Exact affected row(s) and returned IDs.
- Expected ownership attribution.
- Checklist/case/worker/employer counts.
- Audit action, entity ID, actor, and privacy-safe detail.
- No orphan/duplicate rows.
- No unrelated data changes.
- Production untouched.

## 3. Verdict taxonomy

- **Runtime full-cycle PASS**: real Staging mutation, verify, cleanup/reset, and baseline restoration completed.
- **Runtime PASS**: runtime behavior proved, but full cleanup/reset may be handled by another test in the same stage.
- **READ-ONLY PASS**: SELECT/static scan acceptance criteria met with no mutation needed.
- **UI-guard runtime-observed + backend static verified**: UI prevented invalid path; backend rejection confirmed from code, no deliberate write probe.
- **Static verified**: contract verified from deployed code/schema but live runtime path intentionally unavailable.
- **Not runtime-testable / fixture not ready**: prerequisite UI/data path absent.
- **HARD STOP**: environment/baseline/security/count mismatch; no further action.

## 4. Stage 58K-C — Owner-aware document runtime smoke

### Environment and fixture baseline used

```text
Repo: D:\dev\claude
Branch: feature-attendance
HEAD: 54680ec
Staging ref: bzwtknqvhvdmatangzqf
Production ref in Staging HTML: 0
Original case: CASE-20260709-000001 (id=1)
Original case workers: primary customer 1 / secondary customer 2
Disposable employer case: CASE-20260710-000002 (id=2, employer=2, cancelled)
Seed documents: five TEST_58K_SEED metadata-only documents
```

### Final T1–T13 matrix

| Test | Scope | Final classification | Key verified result |
| --- | --- | --- | --- |
| T1 | Primary worker document | Runtime full-cycle PASS | `worker`, owner customer 1, case_worker 1; link/unlink/reset |
| T2 | Secondary worker / Name List | Runtime full-cycle PASS | `worker`, owner customer 2, case_worker 3; isolated from primary |
| T3 | Case-owned document | Runtime full-cycle PASS | `case`, owner case 1, case_worker null |
| T4 | Employer-owned document | Runtime full-cycle PASS | `employer`, owner employer 2 on disposable case 2 |
| T5 | Internal document | Runtime full-cycle PASS | `internal`, owner case 1, case_worker null; item 17 |
| T6 | Duplicate/idempotent link | Runtime PASS | same link ID returned; combo stayed one row; `already_linked=true` audit |
| T7 | Unrelated document rejection | UI-guard runtime-observed + backend static verified | unrelated customer-4 document absent from all selector sections; backend `document_not_allowed` confirmed |
| T8 | Inactive/non-member worker rejection | Static verified; live business guard not triggered | inactive/non-member IDs are UI-unreachable; MCP SQL probe hit permission 42501 before function body; no mutation |
| T9 | Dedicated unlink + strict audit | Runtime PASS | one link removed, source doc kept, strict unlink audit written |
| T10 | Audit privacy scrub | READ-ONLY PASS | zero forbidden key/value hits in link/unlink audit details |
| T11 | Row count/original-case invariant | READ-ONLY PASS | original case, two active workers, 17 checklist items and synthetic row counts remained correct |
| T12 | Payment proof | Code contract verified; UI runtime not testable; fixture not ready | checklist payment item is guidance-only; real flow requires `case_payments` fixture and payment proof UI |
| T13 | Establishment rejection | Intentionally unsupported; static verification PASS | frontend placeholder + backend `owner_link_not_supported`; repo defines `public.establishments` (migration 20260804, filename ≠ table name); live Staging deployment not re-verified — do not assume absent/deployed |

### Important historical numbering note

During execution, some early labels shifted while the external test plan was reconstructed. The final canonical matrix above is the one to use. Do not infer test definitions from seed-document order.

## 5. Stage 58K-C cleanup verification

Mandatory document cleanup acceptance:

| Check | Before | After | Result |
| --- | ---: | ---: | --- |
| `documents source='TEST_58K_SEED'` | 5 | 0 | PASS |
| Seed links | 0 | 0 | PASS |
| Total `case_documents` | 0 | 0 | PASS |
| `case_payments` | 0 | 0 | PASS |
| Audit rows | 131 | 131 | retained / PASS |
| Original case checklist | 13/4/0 | 13/4/0 | unchanged |
| Production | untouched | untouched | PASS |

Optional soft-deactivation was not performed.

## 6. Known behavior recorded by testing

### G1 — unlink status asymmetry

Linking a document can move `missing → received`. Unlinking does not automatically revert `received → missing`; manual reset is required.

### G2 — stale checked marker on reset

Manual reset to `missing` keeps existing `checked_by_code` and `checked_at` (Option B behavior).

### G3 — UI status semantics

- “ผ่าน” counts `approved` only.
- “ขาด” counts `missing`.
- “ลิงก์” counts linked documents.
- `received` is a DB status but has no equivalent top summary chip.

### G4 — audit consistency asymmetry

- Link/unlink audit: strict.
- Checklist status update audit: best-effort.

These are documented product decisions/gaps, not test failures for 58K-C.

## 7. F1 Payment-specific Stage — COMPLETED TEST RECORD

Closed 2026-07-14. Objective met: the real payment-proof path was proved **without** forcing `owner_type='payment'` through the normal checklist selector.

### Environment and fixture

```text
Repo: D:\dev\claude
Branch: feature-attendance
HEAD: e9d035c12921a7dddab9672ea028be304b153f36
Staging ref: bzwtknqvhvdmatangzqf
Production ref in Staging HTML: 0 (Production never queried or touched)
Connector: read-only Staging, re-fingerprinted before every gate
Disposable case: CASE-20260710-000002 (id 2, cancelled, customer 3, employer 2)
Fixture documents: id 11 same-case proof (customer 3), id 12 wrong-case proof (customer 4)
  — both metadata-only, source=TEST_F1_PAYMENT, no storage_path/file_data/bucket/URL
Fixture payment: id 1, case 2, service_fee, amount_due 100, amount_paid 0, initial status unpaid
```

The disposable case was reused rather than creating a new case. Technical suitability of a cancelled case was recorded explicitly as **not** an endorsement of adding payments to cancelled cases in normal business use.

### User action checkpoints (operator-assisted; one action → one verification)

| Gate | Operator action | Agent role |
| --- | --- | --- |
| Seed | Ran the approved transaction-protected fixture SQL once in the Staging SQL Editor | Displayed SQL; did not execute it |
| Step 2 | Created one payment through the real payment UI (single Save) | SELECT-only verification |
| Step 3 | Linked same-case proof via the dedicated payment-proof UI | SELECT-only verification |
| Step 4 | Observed wrong-case proof absent from the picker | No mutation attempted |
| Step 5 | Updated the existing payment by ID (note only) | SELECT-only verification |
| Step 6 | Changed status `unpaid → cancelled` | SELECT-only verification |
| Cleanup | Ran the approved cleanup SQL once | Displayed SQL; SELECT-only post-verification |

Claude Code executed no write statement and no write RPC at any point.

### Results

| Case | Result | Evidence |
| --- | --- | --- |
| Payment create | PASS | Exactly 1 row; case 2; `service_fee`; due 100 / paid 0; status `unpaid`; `proof_document_id` null; `paid_at` null |
| Same-case proof link | PASS | `case_payments.proof_document_id = 11`; **no** `case_documents` row created; dedicated payment path used |
| Wrong-case protection | **UI runtime-observed + backend static verified; no forced live negative write** | Document 12 absent from picker (picker filters by the case's own customer); deployed `document_not_allowed` ownership check verified statically |
| Update by ID | PASS | Same row modified in place; no duplicate; total remained 1 |
| Proof preservation on update | PASS | Proof remained 11 after update with no proof argument supplied |
| Status transition | PASS | `unpaid → cancelled`; same payment id; `paid_at` remained null; proof remained 11 |
| Audit privacy | READ-ONLY PASS | Rows 204–207; forbidden-key scan (path/bucket/URL/file data/base64/token/credential/secret) = 0 hits |
| Invariants | READ-ONLY PASS | `case_documents` 0 throughout; payment checklist item stayed guidance-only; original case id 1 held 17 items and 13/4/0 |

Audit rows written (append-only, best-effort): `204 case.payment.create`, `205 case.payment.proof_link`, `206 case.payment.update`, `207 case.payment.cancel`.

### Cleanup result

| Check | Before | After | Result |
| --- | ---: | ---: | --- |
| `case_payments` | 1 | 0 | PASS |
| `documents source='TEST_F1_PAYMENT'` | 2 | 0 | PASS |
| Total `documents` | 2 | 0 | PASS |
| `case_documents` | 0 | 0 | PASS |
| Audit rows | 135 | 135 | retained / PASS |
| Audit id range | 73–207 | 73–207 | retained / PASS |
| Customers / employers / cases | 4 / 2 / 2 | 4 / 2 / 2 | unchanged |
| Original case checklist | 13/4/0 | 13/4/0 | unchanged |
| Disposable case id 2 | cancelled | cancelled | unchanged |
| Production | untouched | untouched | PASS |

Deleted exactly payment id 1 and documents 11 and 12. No customer, employer, case, worker, checklist, user, or audit row was deleted. No orphan reference to documents 11 or 12 remained.

### Current constraints recorded (not defects fixed in this stage)

- **No demonstrated create idempotency.** The payment create path has no proven duplicate protection; the operator submitted once only. Duplicate-create clicking was deliberately excluded from the test.
- **Omitted/null proof on update preserves the existing proof.** Passing no proof argument keeps the current `proof_document_id`.
- **Proof detach was not tested.** No detach/removal workflow exists or was approved in F1; because the save path treats null as "keep existing", detach is not reachable through the tested contract.
- **Payment audit is best-effort.** Audit is written from inside the RPC body and a failure there does not fail the transaction.

### Scope notes

- No migration and no application-code change were required.
- F1 did not modify G1–G4 or R1.
- Production smoke remains not started.
- The Stage 58K-C T12 result stands unchanged as historical evidence; F1 closed the runtime gap that T12 recorded, and T12 was not retroactively re-scored.

## 8. F2 / Stage 58L Establishment — status and remaining test plan

### Status (superseded original objective)

F2/58L is now **PARTIAL** — see section 8c for the executed runtime acceptance. The deployed canonical table `public.establishments` was confirmed on Staging (RPCs `app_save_establishment`/`app_set_establishment_active`/`app_get_employer_detail`/`app_list_employers_phase2` + Establishment UI); `public.employer_establishments` is only the migration filename, not a deployed table. Establishment Admin runtime acceptance PASS; duplicate-toggle fix + same-state no-op (migration 20260813) PASS; fixture cleanup PASS. The original "reconcile whether the table is deployed" objective is resolved.

### Remaining test plan (separate approved stages)

- Active Staff fixture + Staff runtime permission acceptance (create/edit under role-not-null; Admin-only toggle) — currently NOT TESTABLE (0 active staff). Applies to both Establishment and Employer.
- Employer CRUD acceptance — **Admin path closed PASS, see section 8d.** Remaining: Staff runtime permission matrix; employer delete and employer active/inactive are not implemented and are out of scope until a product decision.
- Migration-history registration decision/evidence (deployment proven; history UNVERIFIED).
- Establishment↔case relationship model (`cases.establishment_id` absent) and the establishment-owned document-link decision (`owner_link_not_supported`).
- Production plan (separate, not started).

### Discovery notes (for the remaining stages)

- Compare migration files and applied migration history (registration currently unverified).
- Inspect Staging and Production schema separately and read-only.
- Inspect `app_save_establishment` and `app_set_establishment_active` definitions/grants (as deployed).
- Confirm expected relationships with employer and case.
- Determine whether an additive migration is needed for establishment↔case binding.

### Acceptance before any write

- Written schema decision.
- Migration rollback plan.
- No conflict with existing production data.
- Staging-only migration plan.
- CRUD and active/inactive test matrix.
- Explicit decision whether establishment-owned documents remain unsupported or get a later dedicated link path.

## 8b. Repository Phase 2 foundations awaiting runtime acceptance

These systems have repository implementation (tables + RPCs + frontend paths) but **no runtime acceptance evidence was found**, and their deployed database state was not queried in the 2026-07-24 documentation reconciliation pass. Each needs its own approved test stage. Do not classify any as Runtime PASS, Staging ready, or Production ready.

| System | Repository evidence | Status |
| --- | --- | --- |
| Establishment reconciliation | table `public.establishments` (migration 20260804 — filename `employer_establishments` differs), `app_save_establishment`, `app_set_establishment_active`, frontend modal | **Superseded — see section 8c.** Canonical table `public.establishments` confirmed deployed on Staging; Establishment Admin runtime acceptance PASS (F2/58L PARTIAL) |
| Appointments | `case_appointments`, `app_save_case_appointment`, `app_set_case_appointment_status`, `app_case_appointment_summary`, frontend path | Implemented; runtime acceptance not found |
| Government / e-WorkPermit tracking | `case_tracking_logs`, `app_add_case_tracking_log`, `app_list_case_tracking_logs`, request-number frontend path | Implemented; runtime acceptance not found |
| Case status history | `case_status_logs`, `app_change_case_status` | Implemented; runtime acceptance not found |
| Contact timeline / activity | `contact_logs`, `work_timeline`, `app_add_contact_log`, `app_add_work_timeline` (migration 20260717) | Implemented; runtime acceptance not found; operational use unconfirmed |

Acceptance for each requires its own approved stage: live read-only pre-check, fixture/identity resolution, contract inspection, operator-assisted single action, SELECT-only verification, audit/privacy scan, cleanup, and baseline restore. This test plan records the verification need only — no test has been run and no completed result is claimed.

## 8c. F2/58L Establishment runtime acceptance — canonical result

Executed operator-assisted on Staging (`rungfar-crm-staging`, ref `bzwtknqvhvdmatangzqf`) with SELECT-only verification; evidence supplied by Project Control (2026-07-24/25). Canonical table is `public.establishments` (deployed); `public.employer_establishments` is not a deployed table. Production not queried or modified.

### Employer support / read path (part of the Establishment test)

| Step | Result | Evidence type |
| --- | --- | --- |
| Open Employer fixture (id=2 `TEST_58K_EMPLOYER`) detail | PASS | Operator-assisted Staging (read) |
| Render workers + establishment count/section | PASS | Operator-assisted + SELECT-only |
| Refresh/reopen persistence | PASS | Operator-assisted |
| **Full Employer CRUD (create/update/permission/audit)** | **Superseded — see section 8d.** Employer Admin Runtime Acceptance PASS on Staging; Staff runtime still NOT TESTABLE | separate controlled stage, executed |

### Establishment Admin flow (fixture id=1 `ZZ_TEST_58L_EST_20260724_A`, employer id=2)

| Step | Result | Evidence type |
| --- | --- | --- |
| Create establishment | PASS | Operator-assisted Staging mutation |
| Post-create SELECT verify (count 0→1, employer_id=2, is_active=true) | PASS | SELECT-only |
| Create audit present + privacy-safe | PASS | SELECT-only |
| Reload persistence | PASS | Operator-assisted |
| Edit one field (`branch_name` → `F2_58L_EDITED_1`) | PASS | Operator-assisted Staging mutation |
| Post-edit SELECT verify (only intended field changed) | PASS | SELECT-only |
| Update audit present + privacy-safe | PASS | SELECT-only |
| Admin inactive toggle | PASS | Operator-assisted Staging mutation |
| Reload inactive persistence | PASS | Operator-assisted |
| Admin active restore | PASS | Operator-assisted Staging mutation |
| Post-fix inactive regression (1 action / 1 dialog / 1 audit) | PASS | Operator-assisted + SELECT-only |
| Post-fix active regression (1 action / 1 dialog / 1 audit) | PASS | Operator-assisted + SELECT-only |
| Same-state active→active direct RPC no-op (no `updated_at`/`updated_by_code` change, no new audit) | PASS | SELECT-only |
| Cleanup (delete exactly the marked establishment row) | PASS | Operator-assisted Staging mutation |
| Baseline restoration (establishments under employer id=2 = 0) | PASS | Cleanup verification (SELECT-only) |

**Establishment Admin Runtime Acceptance verdict: PASS.**

### Duplicate-toggle incident + fix (historical evidence, resolved)

Before the fix, one intended inactive→active flow presented two confirmation dialogs and recorded two `establishment.set_active` audit rows (`is_active=true`); final state correct. Confirmed defects: frontend lacked duplicate/in-flight protection; backend was not audit-idempotent for same-state. The exact second-invocation trigger was **not fully reproduced** (no fully proven event-binding root cause claimed). Fix — frontend per-establishment in-flight guard (acquired before `guardSession()`, first await, and `confirm()`) + button disable; backend migration `20260813` same-state no-op (no UPDATE/timestamp/actor/audit on same state; one UPDATE + one audit on real change), applied once via Staging SQL Editor ("Success. No rows returned"). The two pre-fix duplicate audit rows are **retained append-only historical evidence**, not an active failure after the fix.

Final retained audit for entity `establishment/1`: create 1, update 1, set_active 5 (original inactive + two pre-fix duplicates + one inactive + one active after fix), total 7. Same-state no-op created no audit. Details privacy-safe (only `employer_id`/`is_active`/`soft_toggle`/`internal_only`).

### Staff flow

```text
NOT TESTABLE — NO ACTIVE STAFF FIXTURE
```
Staging user baseline: 1 active user, 1 active Admin, 0 active Staff. Static repository contract only: active Staff may create/edit establishments under the current role-not-null save contract; active toggle is Admin-only (frontend + server RPC). Runtime Staff acceptance remains pending — do not record as PASS or FAIL. (No Staff account was created in the documentation stage.)

### Gaps

- Employer CRUD acceptance — Admin path closed PASS (section 8d); Staff path still pending; employer delete and active/inactive not implemented.
- Staff runtime acceptance — pending (needs active Staff fixture).
- Establishment↔case binding — not implemented (`cases.establishment_id` absent).
- Establishment-owned document linking — unsupported/deferred (`owner_link_not_supported`).
- Migration-history registration — UNVERIFIED (function deployed via SQL Editor; no manual history row).
- Production testing — not started.

## 8d. Employer CRUD runtime acceptance — canonical result

Executed operator-assisted on Staging (`rungfar-crm-staging`, ref `bzwtknqvhvdmatangzqf`) with SELECT-only verification. Production ref `magwqolbjmwymqxelizl` was **not queried and not touched**. Scope was Admin create / read / reload / single-field edit / audit / invariants / cleanup — **not** delete and **not** active/inactive (neither is implemented).

This section supersedes the `PENDING` row for "Full Employer CRUD (create/update/permission/audit)" in section 8c for the **Admin** path only. Staff remains untested.

### Environment and fixture

```text
Staging project: rungfar-crm-staging (ref bzwtknqvhvdmatangzqf)
Production: magwqolbjmwymqxelizl — not queried, not touched
Fixture employer id: 3
Fixture name: ZZ_TEST_EMPCRUD_20260726_A
employer_kind: company
Optional fields left blank intentionally → persisted as null
Related customers / establishments / cases / documents for id 3: 0 / 0 / 0 / 0
```

### Baseline before the test (SELECT-only)

| Item | Value |
| --- | ---: |
| employers | 2 |
| customers | 4 |
| establishments | 0 |
| cases | 2 |
| documents | 0 |
| audit_logs | 142 |
| audit max id | 214 |
| fixture marker count | 0 |

Audit-baseline reconciliation: the F1 closing baseline was `135` audit rows with max id `207` (section 7). The F2/58L Establishment stage added exactly the seven retained rows for entity `establishment/1` (create 1 + update 1 + set_active 5, section 8c), giving `135 + 7 = 142` and max id `207 + 7 = 214`. The Employer CRUD baseline above is therefore continuous with the recorded history — no unexplained audit rows.

### Results

| Case | Result | Evidence |
| --- | --- | --- |
| Employer Admin create | PASS | `employers` 2 → 3; exactly one fixture row; blank optional fields persisted as null |
| Employer detail / read | PASS | Detail opened; workers 0, establishments 0, employer documents 0 |
| Full-page reload and persistence | PASS | Fixture still visible after full refresh; detail reopened successfully |
| Single-field edit | PASS | Among business fields, only `phase2_note` changed, to `EMPCRUD_EDITED_1`; `updated_at` advanced automatically as expected; no other business field changed; `employers` remained 3; marker count remained 1 |
| Create audit + privacy | PASS | Audit id `215`, action `employer.phase2.create`, actor role `admin`, detail `{"internal_only": true}`; privacy scan PASS |
| Update audit + privacy | PASS | Audit id `216`, action `employer.phase2.save`, **exactly one** save audit row; privacy scan PASS; no duplicate submit observed |
| Relationship invariant verification | PASS | See invariant table below |
| Exact fixture cleanup | PASS | Operator ran the approved marker-and-id-scoped transaction once in the Staging SQL Editor; deleted exactly employer id 3 with the exact marker name; all four relation guards were zero; no audit row deleted |
| Baseline restoration | PASS | See restored baseline below |

**Employer Admin Runtime Acceptance verdict: PASS.**

Audit rows written (append-only, best-effort under the current contract): `215 employer.phase2.create`, `216 employer.phase2.save`.

### Restored baseline after cleanup

| Check | Before | After | Result |
| --- | ---: | ---: | --- |
| employers | 2 | 2 | PASS |
| customers | 4 | 4 | unchanged |
| establishments | 0 | 0 | unchanged |
| cases | 2 | 2 | unchanged |
| documents | 0 | 0 | unchanged |
| audit_logs | 142 | 144 | retained / PASS |
| audit max id | 214 | 216 | retained / PASS |
| exact marker count (id + name) | 1 | 0 | PASS |
| marker-name count | 1 | 0 | PASS |
| Production | untouched | untouched | PASS |

Retained audit ids `215` and `216` remain after cleanup — raw row deletion has no cleanup audit trigger and audit retention is intentional, consistent with the 58K-C and F1 precedents.

### Protected invariants — all held

```text
employer id 1: unchanged
employer id 2: unchanged
customer/worker id 3: still linked to employer id 2
employer id 2 establishments: 0
case id 1: draft, employer_id null
case id 2: cancelled, employer_id 2
case id 1 checklist: total 17, missing 13, received 4, approved 0
```

### Staff flow

```text
NOT TESTABLE — NO ACTIVE STAFF FIXTURE
```
Staging user baseline at the time of the test: 1 active user total, 1 active Admin, 0 active Staff. Employer Staff Runtime is recorded as **neither PASS nor FAIL**. No Staff account was created. The static repository contract (unchanged) allows an active Staff user to create/edit employers under the `role is not null` save contract.

### Scope boundaries and gaps recorded (not defects fixed in this stage)

- **Employer delete through the UI is not implemented and was not tested.** No delete RPC and no UI delete control exist for employers.
- **Employer active/inactive is not implemented and was not tested.** `employers` has no active/inactive or soft-delete concept.
- **Duplicate prevention remains PARTIAL** — there is no database uniqueness guarantee on employers and no proven double-submit guard on the save path. The operator submitted once only; duplicate-click was deliberately excluded from the test.
- **Audit remains best-effort** under the current deployed contract, and the audit detail does not identify which field changed — field-level change proof comes from SELECT comparison only.
- **Staff runtime remains NOT TESTABLE** (needs an active Staff fixture, a separately approved stage).
- **Migration-history registration remains UNVERIFIED** (carried forward from section 8c; unchanged by this stage).
- **Production remains NOT STARTED / untouched.**
- **F2/58L overall remains PARTIAL** — this stage closes the Employer **Admin** runtime path only.

### Scope notes

- No migration and no application-code change were required or made.
- This stage did not modify G1–G4, R1, or the F1 follow-ups.
- The completed Establishment (section 8c) and F1 (section 7) evidence is unchanged and was not rewritten.

## 8e. LINE PDF-to-images dual mode — DESIGN APPROVED / NOT RUNTIME TESTED

**Classification: design review complete. No test has been executed.** This section records planned test areas only. It is not evidence of any verified behaviour.

### What this stage did and did not do

- Design review is **complete** and recorded as `LINE-PDF-DUAL-MODE-DESIGN` = DESIGN PASS (2026-08-05).
- **No runtime test was executed.**
- **No database object exists from this stage** — no table, index, constraint, function, trigger, or migration was created or applied.
- **No Cloud Run resource was created**, and no GCP resource of any kind was created or configured.
- **No LINE message was sent**, and no LINE API was called.
- **No quota, delivery-lane, retry, router, group, or conversion behaviour is classified as PASS.**
- No environment was queried in the documentation stage that recorded this section.
- The **implementation and Staging test environment must be selected and re-verified in a separate implementation pre-check** before any test in this section can be planned in detail.

None of the taxonomy verdicts in section 3 — `Runtime full-cycle PASS`, `Runtime PASS`, `READ-ONLY PASS`, `UI-guard runtime-observed + backend static verified`, `Static verified`, or `Not runtime-testable / fixture not ready` — applies to any row below. Nothing here is fixture-ready. Do not upgrade any row without its own approved stage.

### Planned test areas (summary level only)

| Area | Intended coverage — none executed |
| --- | --- |
| Routing compatibility | Existing image upload and existing `จบ` batch finalization must still reach the frozen helper unchanged; a PDF file event must not enter the image workflow; unapproved groups stay ignored |
| Conversion | Page-count boundaries, Thai scanned documents, mixed page orientation, password-protected, corrupt, oversized, and very large page dimensions |
| Saving Mode | First range by Reply; subsequent ranges by user action; final-range composition; concurrent and repeated user actions; **no Push request issued for page delivery** |
| Auto Mode | First range by Reply, remaining ranges by Push; page order; partial-failure handling; quota pre-check and fallback behaviour |
| Job association | One sender's document never reaches another sender; multiple documents from one sender; expiry; duplicate and delayed webhooks |
| Group delivery stream | One delivery stream per group; a second sender receives a busy response and no images; different groups unaffected |
| Reply ambiguity | Explicit user resolution path, authorization, and idempotency |
| Push retry | Time-bounded retry episodes, exact-payload reuse, accepted-request reconciliation, and behaviour after the retry window |
| Mode control | Default mode for unconfigured groups; admin-only mode change; unauthorized attempt |
| Security and privacy | Signature boundary, internal-call authentication, original-group binding, and the audit/log privacy scan |
| Regression | Existing PDF+Excel card generation, existing commands, existing rotations, existing auto-finalize cron, existing document inbox |
| Mobile acceptance | Multi-select forwarding of returned images on Android and iPhone LINE |

### Prerequisites before any of the above can be executed

1. This documentation correction verified, owner-approved, committed, and pushed.
2. A separate LINE **implementation pre-check** (read-only).
3. Selection and verification of the implementation and Staging runtime environment.
4. Separate approvals for migration, function deployment, GCP resource creation, router activation, and any Auto-Mode quota window.
5. Production deployment and runtime remain unapproved. Production was not mutated; see section 8f for the separately approved owner-assisted read-only export of two static icons.

## 8f. LINE Staging asset foundation (AP-1 … AP-4) — STORAGE FOUNDATION ONLY

**Classification: Staging Storage foundation. This is NOT a LINE runtime test, NOT helper runtime acceptance, and NOT implementation acceptance.** No LINE message was sent, no LINE API was called, no Edge Function was deployed or invoked, and no application code was changed.

### Branch A decision and its limits

The owner selected **Branch A**: preserve and later restore the existing frozen PDF+Excel helper on Staging **after** removing its Production asset dependency under a dedicated approved stage. Branch A is **not** code-change approval, **not** deployment approval, and **not** Production approval. The existing helper remains **FROZEN**, and LINE PDF-to-images remains **DESIGN PASS — IMPLEMENTATION NOT STARTED** (section 8e is unchanged by this section).

### Environment and target proof

```text
Staging project: rungfar-crm-staging (ref bzwtknqvhvdmatangzqf)
Target proof: get_project_url returned https://bzwtknqvhvdmatangzqf.supabase.co, re-proven in each Gate
Repository HEAD during all four Gates: unchanged; working tree clean; no repository file modified
```

**Production classification for this workstream:** Production ref `magwqolbjmwymqxelizl` was **NOT MUTATED** — no connector query, no deployment, and no schema/data/Storage/policy/configuration change. The owner located the two static icon files in the protected Production `line-assets` bucket and performed **one separately approved read-only export/download of exactly those two files**. Production **was** accessed for that export. Do not describe Production as untouched throughout this workstream.

### Local source assets (owner attestation)

```text
PDF icon    ChatGPT Image Jun 3, 2026, 02_52_40 PM.png   PNG RGB 1254x1254     734,889 bytes
            SHA-256 77f5483899b0258c07317400bb4d6c2458a547a2b8049a84dd8e351bda793d7d
Excel icon  ChatGPT Image Jun 3, 2026, 09_14_20 PM.png   PNG RGB 1254x1254   1,031,644 bytes
            SHA-256 1b99ddbcab857f7ad423936fe52cd2dc33d41dd7c987400657706d7403b3a1e4
```

Both files were opened and visually verified locally. They were **not proven byte-identical to the Production objects**. Neither file was copied into the repository.

### Gate results

| Gate | Type | Result | Evidence |
| --- | --- | --- | --- |
| AP-1 | READ-ONLY metadata check | **HISTORICAL GATE EVIDENCE — pre-creation state, not current state** | Staging target `bzwtknqvhvdmatangzqf`; exactly one SELECT-only statement; bucket `line-assets` absent; both required objects absent; no Storage mutation; Production not queried |
| AP-3 | **OWNER-ASSISTED STAGING STORAGE MUTATION** | Executed | Owner created exactly one bucket through the Supabase Dashboard: id/name `line-assets`, public true, displayed size limit 2 MB, allowed MIME type `image/png`; no folder, no object upload, no policy action |
| AP-4 | **READ-ONLY PASS** | Verified | Target re-proven; exactly one SELECT-only statement; all values matched — see Expected vs Actual |

### AP-4 Expected vs Actual

| Item | Expected | Actual | Result |
| --- | --- | --- | --- |
| bucket row count | 1 | 1 | PASS |
| bucket id / name | `line-assets` | `line-assets` | PASS |
| public | true | true | PASS |
| file_size_limit | 2000000 or 2097152 | **2097152** | PASS |
| allowed_mime_types | exactly one entry `image/png` | one entry, `image/png` | PASS |
| object count in bucket | 0 | 0 | PASS |
| total Staging bucket count | 3 | 3 | PASS |
| public Staging bucket count | 1 | 1 | PASS |
| line-assets-specific Storage policy count | 0 | 0 | PASS |
| total `storage.objects` policy count | recorded | 0 | recorded |
| created_at | recorded | 2026-08-05 15:31:03.675746+00 | recorded |
| updated_at | recorded | 2026-08-05 15:31:03.675746+00 | recorded |

Timestamp reading: **created_at and updated_at were equal at AP-4 verification; no post-creation bucket update was observed in that metadata snapshot.**

AP-4 performed no database write, no Storage mutation, no object upload or download, no signed or public URL request, no policy change, no deployment, no commit, no push, and no Production query.

### Public-access statement

- The bucket is **configured public** for non-sensitive static UI icons.
- **Public write is not approved.**
- **No `line-assets`-specific Storage policy existed at AP-4.**
- **Public object retrieval remains untested.**

### Scope limitations

- **At AP-4 (2026-08-05) the bucket contained zero objects: PDF icon NOT UPLOADED, Excel icon NOT UPLOADED.** That is the dated AP-4 state and it must stay recorded as such. **Superseded for the PDF icon only** by section 8g (uploaded 2026-08-06, verified 2026-08-07, bucket object count now 1). **Excel icon remains NOT UPLOADED.**
- **LINE image rendering remains untested.**
- `line-ai-excel-helper` (four Production asset references) and `line-ai-excel-finalize-due` (three Production asset references) remain **BLOCKED FROM DEPLOYMENT**.
- **No asset-decoupling code edit has been performed.** No Edge Function has been deployed.
- The **final asset URL construction strategy is UNRESOLVED** and requires a separately approved stage.
- No Production deployment is approved.

### Next test sequence — steps 1–3 complete, the rest not started and each separately approved

1. ✅ Read-only pre-check for uploading only the PDF icon — PASS (section 8g).
2. ✅ Upload the PDF icon (one operator action) — executed 2026-08-06 (section 8g).
3. ✅ Read-only verification of that object — PASS (section 8g).
4. Read-only pre-check for uploading only the Excel icon.
5. Upload the Excel icon (one operator action).
6. Read-only verification of that object.
7. Asset-decoupling code edit under the dedicated frozen-helper stage.
8. Static verification of that edit.
9. Each Edge Function deployment separately, each preceded by a Production-reference zero check.
10. Webhook activation.
11. Runtime regression of the existing frozen helper.

## 8g. LINE Staging PDF icon — upload and read-only verification (2026-08-06/07)

**Classification: Staging Storage foundation, first object only. NOT a LINE runtime test, NOT helper runtime acceptance, NOT implementation acceptance.** No LINE message was sent, no LINE API was called, no Edge Function was deployed or invoked, no application code was changed, and no public or signed URL was requested. **Production was not accessed** during the upload or either verification stage.

### Environment and target proof

```text
Staging project ref: bzwtknqvhvdmatangzqf
Target proof: get_project_url returned https://bzwtknqvhvdmatangzqf.supabase.co
              — re-proven at the start of every gate below
Bucket: line-assets (bucket root; no folder created)
Repository during all gates: branch feature-attendance,
              HEAD 926f976090ebe73e6336f5b26440f9e57a5ac656 = origin, tree/index clean,
              Production ref count in Staging local HTML = 0
```

### Gates

| Gate | Type | Result | Evidence |
| --- | --- | --- | --- |
| Upload pre-check (first attempt) | READ-ONLY | **PARTIAL — local source path required** | Six-file read and Git precheck passed; the exact local source-file path was not available from session evidence or from any document, so the stage stopped before connector proof. One SELECT-only statement was withheld; zero queries executed |
| Upload pre-check (resumed) | **READ-ONLY PASS** | Verified | Owner supplied `D:\PDFExcelicons`. Exactly one candidate matched the required basename prefix: `ChatGPT Image Jun 3, 2026, 02_52_40 PM - สำเนา.png`. Size 734,889 bytes and SHA-256 `77f5483899b0258c07317400bb4d6c2458a547a2b8049a84dd8e351bda793d7d` matched the locked contract exactly; PNG signature + IHDR gave 1254 × 1254, bit depth 8, colour type 2 (RGB), non-interlaced; file readable, outside the repository, not tracked/staged/present in the working tree. Exactly one SELECT-only statement confirmed the bucket contract and **object count 0 / exact target object count 0** |
| PDF icon upload | **OWNER-ASSISTED STAGING STORAGE MUTATION** | Executed | Owner uploaded exactly one file through the Supabase Dashboard into `line-assets`; one object created; no folder, no policy action, no second file |
| Post-upload verification (first statement) | READ-ONLY | **BLOCKED — exact target object not found** | Bucket contract unchanged; bucket object count 1; but the count for the pre-approved name `ChatGPT Image Jun 3, 2026, 02_52_40 PM.png` was **0** and its metadata columns were null. Stopped on the mismatch with no retry and no second query in that stage |
| Actual-name verification | **READ-ONLY PASS** | Verified | Exactly one SELECT-only statement returned exactly one row and identified the stored object — see below |

### Verified object state (read-only, 2026-08-07)

| Item | Value |
| --- | --- |
| bucket_id | `line-assets` |
| bucket public / file_size_limit / allowed_mime_types | true / 2097152 / `["image/png"]` — unchanged from AP-4 |
| total object count in bucket | 1 |
| stored object name | `ChatGPT Image Jun 3, 2026, 02_52_40 PM.png.png` |
| mimetype | `image/png` |
| size | 734889 bytes |
| created_at | 2026-08-06 17:49:17.996475+00 |
| updated_at | 2026-08-06 17:49:17.996475+00 |
| Excel icon object | absent |

`created_at` equals `updated_at`, so this snapshot shows one insert and no post-upload object update. No historical inference is drawn beyond the returned snapshot.

### Name discrepancy and its resolution

The pre-approved target object name was `ChatGPT Image Jun 3, 2026, 02_52_40 PM.png`. The stored name carries a **doubled `.png` extension**, consistent with the Windows Explorer hidden-extension behaviour recorded during the pre-check (the local copy suffix ` - สำเนา` was removed, and a second `.png` was appended). The **owner explicitly accepted the doubled-extension name as the permanent object name**; no rename, delete, replacement, or re-upload is required. Recorded as a durable decision in `DECISIONS_LOG.md` (2026-08-07).

### Limits of this evidence

- `object_size` 734889 and `mimetype` `image/png` match the approved local source asset, and 734889 differs from the Excel icon's 1,031,644 bytes. Storage metadata exposes **no checksum**, so this is a size-and-MIME match, **not** a SHA-256 byte-identity proof of the stored object.
- The local source asset was never proven byte-identical to the protected Production object; that classification is unchanged.
- **Public object retrieval remains UNTESTED** — no public or signed URL was requested. **LINE image rendering remains UNTESTED.**
- The **asset URL construction strategy remains UNRESOLVED** and needs its own approved stage.
- `line-ai-excel-helper` (four Production asset references) and `line-ai-excel-finalize-due` (three Production asset references) remain **BLOCKED FROM DEPLOYMENT**. **No asset-decoupling code edit has been performed.**
- **Excel icon: NOT UPLOADED.** LINE PDF-to-images remains **DESIGN PASS — IMPLEMENTATION NOT STARTED**, and the existing PDF+Excel helper remains **FROZEN**.
- The AP-4 zero-object evidence in section 8f remains valid dated history for 2026-08-05 and was not rewritten.

## 8h. N8N-001A Automation Integration Foundation (READ-ONLY V1) — canonical runtime result

**Verdict: PASS — STAGING RUNTIME ACCEPTED, 2026-08-10.** Environment: Staging `bzwtknqvhvdmatangzqf` only; **Production access zero**. Implementation files were left **uncommitted** at acceptance.

### Architecture under test

```text
n8n machine token → n8n-read-api Edge Function → integration_n8n_* SECURITY INVOKER RPCs → CRM tables
```

Exactly three V1 actions: `health.v1`, `management.summary.v1`, `cases.readiness.v1`.

### Baseline (SELECT-only, before mutation)

```text
customers 4 (4 active)   employers 2   cases 2   documents 0
case_checklist_items 34  case_payments 0  case_appointments 0  case_tracking_logs 0
audit_logs 144 (max id 216)   app_users 1
Staging Edge Functions 0   public.integration_request_logs ABSENT   integration_n8n_* ABSENT
DB TimeZone UTC   app_list_cases canonical ordering cs.created_at DESC
service_role SELECT on cases/customers/employers/case_checklist_items = true (rolbypassrls = true)
```

### T1–T26 matrix

| Test | Expected | Actual | Verdict |
| --- | --- | --- | --- |
| T1 Environment/deployment | Staging only | `bzwtknqvhvdmatangzqf`; exactly 1 Edge Function; 0 Production access | RUNTIME VERIFIED |
| T2 SECURITY INVOKER | prosecdef=false, search_path='' | 5/5 both; live service_role execution succeeded without new grants | RUNTIME VERIFIED |
| T3 Human isolation | no app_users touch | app_users 1 unchanged; no session/user_id path exists | RUNTIME VERIFIED |
| T4 Missing Authorization | 401, zero business RPC | 401 + `no-store`; 0 audit rows | RUNTIME VERIFIED |
| T5 Invalid token | 401 | 401; malformed scheme also 401 | RUNTIME VERIFIED |
| T6 Valid token + invalid action | 400 | 400 `invalid_action`; **no** audit row, no DB contact | RUNTIME VERIFIED |
| T7 Generic proxy attacks | rejected | `rpc`/`sql`/`app_save_customer`/unknown `table` all rejected; zero mutation | RUNTIME VERIFIED |
| T8 client_request_id | stored; distinct server id | `n8n-test-001` stored verbatim; server `request_id` a distinct UUID v4 | RUNTIME VERIFIED |
| T9 Body cap | 413 before JSON parsing | authenticated >8 KiB → **HTTP 413**; unauthenticated 16 KiB → 401 (auth precedes body read) | RUNTIME VERIFIED |
| T10 Method/content-type/cache | rejected + no-store | GET→405, text/plain→415, `Cache-Control: no-store` on all | RUNTIME VERIFIED |
| T11 health.v1 | 5 safe fields only | HTTP 200; business_date matched independent Bangkok SQL | RUNTIME VERIFIED |
| T12 management.summary.v1 | matches independent SQL | HTTP 200; open 1, draft 1, cancelled 1, due_soon_7 0, overdue 0, required_items 12, remaining 12, missing 10, blocked 1, customers 4, employers 2 | RUNTIME VERIFIED |
| T13 cases.readiness.v1 | open only, no PII | HTTP 200; 1 open case; 12 = 10 missing + 2 received; zero PII/storage fields | RUNTIME VERIFIED |
| T14 Deterministic ordering | identical on repeat | repeated call **IDENTICAL**; `created_at DESC, id DESC`; items `sort_order ASC, id ASC` | RUNTIME VERIFIED |
| T15 Cap contract | cap 100 + truncation meta | `LIMIT 100` + `total_open_cases`/`returned_count`/`truncated`; Staging has 1 open case, **no cases seeded** | STATIC VERIFIED |
| T16 Bangkok boundary | 6 boundary cases | 16:59:59Z→2026-08-10; 17:00:00Z→2026-08-11; due 08-10 overdue, 08-11/08-18 due_soon, 08-19 outside | RUNTIME VERIFIED (SQL) |
| T17 DB clock authority | DB-only timestamps | `duration_ms` reconciled to `finished_at − created_at` on every row; no timestamp parameter exists | RUNTIME VERIFIED |
| T18 Rate limiter | 5 admitted, 6th 429 | **5×200 + 1×429** in a 201.382 ms burst; occupancy 0,1,2,3,4 → 6th saw 5 prior; 429 created **no** row; recovery confirmed after the window | RUNTIME VERIFIED |
| T19 Timeout guard | 8s deadline, no retry | AbortController budgets present in deployed source; **no test-only sleep endpoint created by design** | STATIC VERIFIED |
| T20 Audit lifecycle | one row, terminal | 20/20 terminal `success`; 0 stuck at `started`; 20 distinct UUID v4 ids | RUNTIME VERIFIED |
| T21 Audit privacy | no secrets/PII | 0 hits for token/header/payload/URL/storage and 0 hits cross-checked against live customer name/passport/alien ID/WP/visa | RUNTIME VERIFIED |
| T22 Response privacy | no forbidden keys | payloads contain none of passport_no/alien_id/wp_no/visa_no/photo/storage_*/URL/token/secret | RUNTIME VERIFIED |
| T23 Token replacement | B→200, A→401 | **NOT EXERCISED** — requires a separate approved secret change | NOT EXERCISED |
| T24 Business invariants | identical | identical before/after (see below) | RUNTIME VERIFIED |
| T25 CRM invariants | unchanged | `app_*` 67 unchanged; existing grants/RLS unchanged; `rungfar_crm_17.html` unchanged | RUNTIME VERIFIED |
| T26 Repository diff | exactly 2 files | exactly 2 implementation files; 0 tracked files modified | PASS |

### Business invariants — before / after

| Table | Before | After | Result |
| --- | ---: | ---: | --- |
| customers (active/all) | 4 / 4 | 4 / 4 | unchanged |
| employers | 2 | 2 | unchanged |
| cases | 2 | 2 | unchanged |
| documents | 0 | 0 | unchanged |
| case_checklist_items | 34 | 34 | unchanged |
| case_payments | 0 | 0 | unchanged |
| case_appointments | 0 | 0 | unchanged |
| case_tracking_logs | 0 | 0 | unchanged |
| app_users | 1 | 1 | unchanged |
| audit_logs | 144 (max id 216) | 144 (max id 216) | unchanged |
| Production | untouched | untouched | PASS |

Only `public.integration_request_logs` grew (0 → 20 rows). The CRM `audit_logs` trail was **not** written by the integration path — integration auditing is deliberately separate.

### Privilege-hardening amendment (approved, applied separately)

Supabase's project-wide `ALTER DEFAULT PRIVILEGES` on schema `public` auto-grants `Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) to `service_role` on every new table. For an append-and-finalize audit table TRUNCATE is equivalent to wiping the trail, so an owner-approved amendment revoked those four privileges. Verified result: `relacl service_role=arw` — **exactly SELECT/INSERT/UPDATE**, DELETE never granted. The migration source was updated to reproduce this ACL on replay.

### Constraints recorded (not defects)

- **T15** and **T19** remain STATIC VERIFIED by design — no business cases were seeded to exceed the 100 cap, and no test-only sleep endpoint was created to force a timeout.
- **T23** and **n8n-side credential rotation** were NOT EXERCISED. V1 has exactly one active verifier; **no zero-downtime rotation is claimed**.
- The migration was applied via the Staging SQL Editor and is **not registered** in `supabase_migrations` — that schema is **absent** on Staging, as it is for all 63 predecessors. Reconciliation is a separate future ticket.

## 9. Phase 1 regression plan

### Customer/worker CRUD

- Create/edit/cancel modal.
- Multiple image/document uploads, including five large images.
- Newest-first and employer-first business sorting.
- Document open/download access.
- No accidental duplicate customer.

### Import/export

- Leading zero and long ID preservation.
- Dates and Thai text.
- Large file and invalid row behavior.
- Duplicate handling.
- Rollback/no partial import.
- Excel export without E+ notation.

### Attendance

- Check-in/out on desktop/mobile.
- GPS/location permission behavior.
- Absence count/dashboard consistency.
- LINE Messaging API notification on/off and quota behavior.

### User/security

- Active/inactive user.
- Admin/staff permissions.
- Session invalidation.
- Device/IP logs and alerts.
- Delete request/approval path.
- Unauthorized direct RPC/table access rejection.

### Mobile/UI

- Scroll every major page and modal.
- Sidebar open/close.
- Tables/cards readable.
- File picker/open/download behavior in Chrome and LINE in-app browser.
- No dotted/slashed zero glyph.

## 10. Production smoke policy

Production smoke is not yet approved. When ready, create a separate plan with:

- Exact production backup and rollback checkpoints.
- Non-destructive existing record or explicitly approved prod-safe fixture.
- Minimum subset only.
- Pre-count and post-count equality.
- No broad cleanup.
- User-performed actions and immediate verification.
- Separate deploy approval.

Do not reuse the Staging seed script against Production.

## 11. Test evidence and documentation rule

For each stage, record:

- Stage ID/name and date.
- Commit/HEAD and environment.
- Fixture IDs and cleanup state.
- Expected vs Actual report.
- Runtime/static classification.
- Known gaps found.
- Final baseline.
- Link to commit/migration/report file if placed in repo.

Update this file after a stage closes; do not rewrite historical outcomes without explaining the correction in `DECISIONS_LOG.md`.
