# RUNGFA CRM — TEST PLAN AND VERIFIED HISTORY

> Test strategy, completed evidence, and future test matrix.
>
> Last verified closeout: F1 Payment-specific Stage, 2026-07-14 (prior: Stage 58K-C, 2026-07-13). Live values must be re-checked before new tests.

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
| T13 | Establishment rejection | Intentionally unsupported; static verification PASS | frontend placeholder + backend `owner_link_not_supported`; Staging table absent |

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

## 8. Next technical test plan — F2 / Stage 58L Establishment reconciliation

### Objective

Reconcile deployed establishment RPCs with the absent Staging `employer_establishments` table, then define a safe establishment data model and tests.

### Discovery

- Compare migration files and applied migration history.
- Inspect Staging and Production schema separately and read-only.
- Inspect `app_save_establishment` and `app_set_establishment_active` definitions/grants.
- Confirm expected relationships with employer and case.
- Determine whether 20260804 migration should be applied, revised, or superseded.

### Acceptance before any write

- Written schema decision.
- Migration rollback plan.
- No conflict with existing production data.
- Staging-only migration plan.
- CRUD and active/inactive test matrix.
- Explicit decision whether establishment-owned documents remain unsupported or get a later dedicated link path.

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
