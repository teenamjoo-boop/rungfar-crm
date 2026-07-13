# RUNGFA CRM — TEST PLAN AND VERIFIED HISTORY

> Test strategy, completed evidence, and future test matrix.
>
> Last verified closeout: Stage 58K-C, 2026-07-13. Live values must be re-checked before new tests.

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

## 7. Next technical test plan — F1 Payment-specific Stage

### Objective

Prove the real payment-proof path without forcing `owner_type='payment'` through the normal checklist selector.

### Read-only discovery first

- Inspect `case_payments` schema, constraints, and current rows.
- Inspect `app_save_case_payment`, proof-document fields, and any proof picker/list RPC.
- Inspect frontend payment section and disabled/guidance-only checklist behavior.
- Confirm Staging/Production schema parity relevant to payment.

### Minimal fixture proposal (requires approval)

- One synthetic payment row linked to a synthetic/disposable case.
- One metadata-only proof document with clearly scoped marker.
- No real customer document or financial data.

### Runtime cases

1. Save/update synthetic payment safely.
2. Link same-case proof document through the actual payment UI/RPC.
3. Verify `case_payments.proof_document_id` and UI display.
4. Wrong-case proof rejection (`document_not_allowed`).
5. Idempotent/replacement behavior if supported.
6. Audit and privacy scan.
7. Cleanup payment/proof fixture and restore baseline.

### Stop conditions

- Missing/ambiguous function signature.
- UI sends checklist link instead of payment-specific RPC.
- Any real payment/customer row in fixture scope.
- Proof document can cross cases.
- Audit leaks path/URL/token/file data.
- Production ref appears.

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
