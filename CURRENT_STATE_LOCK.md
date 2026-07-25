# RUNGFA CRM — CURRENT STATE LOCK

> Canonical handoff snapshot after the F1 Payment-specific Stage and its cleanup.
>
> Snapshot date: 2026-07-22 (Thailand time context) — documentation closeout. The F1 Payment-specific Stage runtime test and cleanup were executed and verified on Staging 2026-07-14; the database values below are that verified baseline. This file records the last verified state, not a substitute for live pre-flight. Re-verify Git and DB before every new mutation.

## 1. Canonical status

```text
PROJECT: RUNGFA CRM
REPO: D:\dev\claude
GIT BASH: /d/dev/claude
BRANCH: feature-attendance
CURRENT LIVE HEAD: read from Git every session (`git rev-parse HEAD`) — not frozen in this file
LAST COMMITTED CHECKPOINT: 81f03b9 "Harden establishment toggle and document 58L acceptance" (verified committed + pushed; local = origin/feature-attendance; 0 ahead / 0 behind; working tree clean at the verified post-push check). This is a checkpoint fact — read live HEAD from Git every session, do not treat this hash as a permanent current HEAD.
STAGE EVIDENCE COMMITS (historical): e9d035c = F1 runtime-test HEAD; bf40820 = F1 documentation-closeout commit; 2c30070 = post-closeout metadata sync; 80dcafe = recovery-inventory doc reconciliation; 81f03b9 = post-F2/58L Establishment Admin checkpoint (frontend toggle guard + migration 20260813 + F2/58L documentation)
WORKING TREE (at verified post-push check): clean — the F2/58L package (rungfar_crm_17.html toggle guard, migration 20260813, and the F2/58L documentation) was committed and pushed as 81f03b9. The local-only patched rungfar_crm_17.STAGING.local.html remains untracked/excluded. Re-verify live before any write.

STAGING REF: bzwtknqvhvdmatangzqf
PRODUCTION REF: magwqolbjmwymqxelizl
PRODUCTION: untouched
LOCAL STAGING HTML: rungfar_crm_17.STAGING.local.html
PRODUCTION REF COUNT IN STAGING HTML: 0 (safety gate — must stay 0)
STAGING REF COUNT IN STAGING HTML: 4 (informational snapshot — re-report if the file changes)

LATEST CLOSED STAGE: F1 Payment-specific Stage (Staging) — closed 2026-07-14
PRIOR CLOSED STAGE: Stage 58K-C Runtime Smoke (historical)
RUNTIME/STATIC MATRIX: T1–T13 recorded (58K-C)
MANDATORY TEST DOCUMENT CLEANUP: complete (58K-C)
F1 PAYMENT FIXTURE CLEANUP: complete
OPTIONAL SOFT-DEACTIVATION: not performed
PRODUCTION SMOKE: not started
PAYMENT-SPECIFIC STAGE: CLOSED on Staging
CANONICAL ESTABLISHMENT TABLE: public.establishments (deployed on Staging) — NOT public.employer_establishments
F2/58L ESTABLISHMENT: PARTIAL — Establishment Admin runtime acceptance PASS; duplicate-toggle fix PASS; same-state backend no-op PASS; fixture cleanup PASS
F2/58L STAFF RUNTIME: NOT TESTABLE — no active Staff fixture (0 active staff on Staging)
F2/58L EMPLOYER FULL CRUD: pending (separate controlled stage)
ESTABLISHMENT↔CASE BINDING: not implemented (cases.establishment_id absent)
ESTABLISHMENT-OWNED DOCUMENT LINK: unsupported/deferred (owner_link_not_supported)
MIGRATION 20260813 (same-state no-op): deployed via Staging SQL Editor ("Success. No rows returned") — migration-history registration UNVERIFIED
IDENT-1 IDENTITY/SESSION: design complete, implementation PARKED (not started)
CURRENT STAGE: POST-PUSH-DOC-1 post-push documentation reconciliation
```

Repository HEAD/snapshot semantics:

- **Current live HEAD is obtained from Git pre-flight, never from a value frozen in this file.** The hashes recorded here are dated snapshots and historical stage evidence.
- Last pre-reconciliation verified snapshot: `2c30070` (2026-07-23) — `local = origin/feature-attendance`, 0 ahead / 0 behind, working tree clean. A live HEAD newer than this snapshot is only a HARD STOP when the newer commit(s)/working tree introduce a meaningful unexplained change (application code, schema/migration, HTML, configuration, environment, or an unrecorded Stage-status change). A documentation-only commit newer than the snapshot does not invalidate recorded Stage evidence.
- Historical stage evidence: `bf40820` = F1 documentation-closeout commit (2026-07-22, six-doc edit, pushed). `e9d035c` = the HEAD at which the F1 runtime test was executed on 2026-07-14, and parent of `bf40820`. `54680ec` = code-baseline HEAD during Stage 58K-C. All are historical evidence, not current state.
- Documentation-only commit `bf40820` changed **all six** source-of-truth Markdown files (`AGENTS.md`, `CURRENT_STATE_LOCK.md`, `DECISIONS_LOG.md`, `PROJECT_MASTER_HANDOFF.md`, `ROADMAP.md`, `TEST_PLAN.md`). Documentation-only commit `2c30070` changed **only four** of them (`AGENTS.md`, `CURRENT_STATE_LOCK.md`, `PROJECT_MASTER_HANDOFF.md`, `ROADMAP.md`). Neither commit modified application code, HTML, migration, SQL, or configuration.

## 2. Verified Staging database baseline after F1 cleanup

Baseline verified read-only immediately after the F1 fixture cleanup on 2026-07-14.

> Note (2026-07-24 documentation reconciliation): the database values in this section are **documented historical evidence — not re-verified in this documentation pass** (no database was queried). Re-verify read-only before any dependent action.

```text
total documents: 0
seed_docs (source=TEST_58K_SEED): 0
fixture docs (source=TEST_F1_PAYMENT): 0
total case_documents: 0
case_payments: 0
audit_total: 135 (retained; id range observed 73–207)
customers: 4   employers: 2   cases: 2
```

Retained F1 payment audit rows (append-only evidence; not deleted by cleanup):

```text
204 case.payment.create
205 case.payment.proof_link
206 case.payment.update
207 case.payment.cancel
```

Historical note: audit_total `131` with id range `73–203` was the Stage 58K-C closing baseline. It is historical evidence, not current state. The four F1 payment audit rows raised the retained total to 135.

Original test case:

```text
case id: 1
case_code: CASE-20260709-000001
case_status: draft
customer_id: 1
employer_id: null
active case workers: 2
checklist total: 17
missing / received / approved: 13 / 4 / 0
item 5 (worker_photo): missing
item 6 (name_list): missing
item 13 (payment_receipt): missing
item 17 (submit_result_note): received
item 17 active links: 0
```

Synthetic entities retained after mandatory document cleanup:

```text
customer id=1: TEST WORKER 58I — active; original case customer/primary worker
customer id=2: TEST WORKER 58J SECOND — active; secondary worker
customer id=3: TEST_58K_EMP_WORKER — active; employer_id=2
customer id=4: TEST_58K_UNRELATED_CUSTOMER — active
employer id=2: TEST_58K_EMPLOYER — active
disposable case id=2: CASE-20260710-000002 — cancelled; customer_id=3; employer_id=2
```

A separate non-58K employer row (`employer id=1`, name recorded in prior reports) exists and must not be touched by synthetic cleanup.

## 3. F1 Payment-specific Stage result — CLOSED (current)

Closed on Staging 2026-07-14. Operator-assisted runtime; Claude Code read-only throughout. No migration and no application-code change were required.

Fixture used (temporary, now removed):

```text
disposable case id=2  CASE-20260710-000002 (cancelled, customer 3, employer 2)
document id=11  same-case proof, customer 3, metadata-only, source=TEST_F1_PAYMENT
document id=12  wrong-case proof, customer 4, metadata-only, source=TEST_F1_PAYMENT
payment  id=1   case 2, service_fee, amount_due 100, amount_paid 0, initial status unpaid
```

Runtime results:

- Payment create through the real payment UI: exactly one row; correct case, type, amounts, status `unpaid`; `proof_document_id` null; `paid_at` null.
- Same-case proof link through the **dedicated payment-proof UI**: `case_payments.proof_document_id = 11`; **no** `case_documents` row created.
- Wrong-case protection: document 12 was absent from the payment picker (the picker filters by the case's own customer) and the deployed `document_not_allowed` ownership check was verified statically. Classification: **UI runtime-observed + backend static verified; no forced live negative write.**
- Update by ID: same payment row modified in place; no duplicate; proof link remained 11.
- Status transition `unpaid → cancelled`: same payment id; `paid_at` remained null; proof remained 11.
- `case_documents` remained 0 for the entire stage; the payment checklist item stayed guidance-only.
- Original case id 1 invariant held throughout: 17 checklist items, 13 missing / 4 received / 0 approved.
- Payment audit rows 204–207 were append-only and contained no storage path, bucket, URL, file data, base64, token, credential, or secret.

Cleanup:

- Deleted exactly payment id 1 and documents 11 and 12.
- Audit rows retained; no customer, employer, case, worker, checklist, or user record deleted.
- Restored baseline verified read-only — see section 2.

Constraints recorded (not defects fixed in this stage):

- Payment create has **no demonstrated idempotency protection**; the operator submitted once only.
- Omitting/null proof during a payment update **preserves** the existing proof.
- No proof-detach workflow exists or was tested/approved in F1.
- Payment audit is **best-effort** under the current deployed contract.

## 4. Stage 58K-C final result (historical)

### Runtime full-cycle PASS

- T1 Primary worker owner-aware link/unlink/reset.
- T2 Secondary worker / Name List attribution.
- T3 Case-owned document attribution.
- T4 Employer-owned document attribution on disposable case.
- T5 Internal document attribution.
- T6 Duplicate/idempotent re-link.
- T9 Dedicated unlink + strict audit.

### Read-only PASS

- T10 Audit privacy scrub: zero forbidden hits.
- T11 Row-count/original-case invariants.

### Partial/static outcomes recorded by design

- T7 Unrelated document: UI visibility guard runtime-observed; backend `document_not_allowed` statically verified. No deliberate negative write probe was required.
- T8 Inactive/non-member worker: guard and UI-unreachability statically verified. Attempted SQL connector probe was blocked at permission layer (`42501`) before the business function; no mutation occurred. This is not counted as a live business-guard PASS.
- T12 Payment proof: backend contract exists, checklist UI is guidance-only, and no `case_payments` fixture exists. Classified code-supported/UI-unreachable + fixture-not-ready.
- T13 Establishment: checklist path intentionally unsupported (`owner_link_not_supported`); static verification only; separate 58L stage required. **Correction (2026-07-24):** the repository migration `20260804_employer_establishments.sql` defines the table as `public.establishments` (the filename differs from the table name), with RPCs `app_save_establishment`/`app_set_establishment_active` and a frontend modal. The earlier "table absent" reading came from searching the wrong name `public.employer_establishments`; live Staging deployment of `public.establishments` was **not re-verified** and must not be assumed present or absent until a read-only 58L pre-check. **Update (2026-07-25):** This earlier deployment uncertainty is superseded by the verified F2/58L Staging review. `public.establishments` is the deployed canonical table and Establishment Admin Runtime Acceptance is PASS. F2/58L remains PARTIAL (Staff Runtime NOT TESTABLE, Employer CRUD pending); see section 5b for the current result and remaining gaps.

## 5. Stage 58K-C cleanup result (historical)

Mandatory document cleanup completed successfully in Staging SQL Editor:

- Deleted exactly five marker-scoped `TEST_58K_SEED` documents.
- No `case_documents` or `case_payments` referenced them at cleanup time.
- No non-test document was touched.
- Customers, employers, cases, case workers, checklist items, and audit logs were not changed.
- Audit count stayed 131 because raw document deletion has no cleanup audit trigger and audit retention was intentional.
- Optional soft-deactivation of synthetic customers/employer was deliberately not performed.

## 5b. F2/58L Establishment runtime acceptance (current)

Reconciled from operator-assisted Staging runtime + SELECT-only verification (evidence supplied by Project Control on 2026-07-24/25). Canonical table is `public.establishments` (deployed on Staging); `public.employer_establishments` is **not** a deployed table (it is only the migration filename).

**Establishment Admin Runtime Acceptance — PASS.** Employer fixture detail loaded (workers + establishments rendered); establishment create succeeded (count 0→1, `employer_id=2`, `is_active=true`, privacy-safe create audit); refresh preserved it; admin edit of `branch_name` changed only the intended field (privacy-safe update audit); admin inactive toggle + reload + active restore succeeded.

**Duplicate-toggle incident (historical) + fix — PASS.** Before the fix, one intended inactive→active flow produced two confirmation dialogs and two `establishment.set_active` audit rows (`is_active=true`); final state was correct. Confirmed defects: frontend lacked duplicate/in-flight protection; backend was not audit-idempotent for same-state. The exact second-invocation trigger was **not fully reproduced** (do not claim a fully proven event-binding root cause). Fix: frontend per-establishment in-flight guard (acquired before `guardSession()`, before first await, before `confirm()`) + button disable; backend migration `20260813` makes same-state a no-op (no UPDATE, no `updated_at`/`updated_by_code` change, no audit) while a real change performs exactly one UPDATE + one audit.

**Post-fix Admin regression — PASS.** active→inactive and inactive→active each: one action, one dialog, one state change, one audit. Same-state active→active direct RPC: returned `id=1, is_active=true`, `updated_at`/`updated_by_code` unchanged, `set_active` audit count unchanged — PASS.

**Fixture cleanup — PASS.** Synthetic establishment `ZZ_TEST_58L_EST_20260724_A` (id=1) deleted; establishments under employer id=2 = 0; employer fixture id=2 and worker fixture retained; audit rows retained append-only. Final audit for entity `establishment/1`: create 1, update 1, set_active 5 (original inactive + two pre-fix duplicates + one inactive + one active after fix), total 7; the same-state no-op created no audit. Audit details privacy-safe (only `employer_id`/`is_active`/`soft_toggle`/`internal_only`).

**Migration 20260813** was applied once via the confirmed Staging SQL Editor ("Success. No rows returned"); function deployment is proven but **migration-history registration is UNVERIFIED** (run through SQL Editor, no manual history row added) — an unresolved traceability point, not a failed migration.

**Still pending / not implemented:** Staff runtime acceptance (NOT TESTABLE — 0 active staff; static contract allows active staff to create/edit under role-not-null, toggle is Admin-only); Employer full CRUD acceptance; establishment↔case binding (`cases.establishment_id` absent); establishment-owned document linking (`owner_link_not_supported`, deferred). Production: not started.

## 6. Known product gaps carried forward

```text
G1 unlink does not auto-revert checklist received → missing.
G2 reset to missing retains checked_by_code and checked_at.
G3 UI chips: “ผ่าน” = approved, “ขาด” = missing, “ลิงก์” = linked docs; received is separate.
G4 checklist update audit is best-effort; link/unlink audit is strict.
R1 item17 retains stale checked_by_code/checked_at after fixture reset (instance of G2).
F1 CLOSED 2026-07-14 — payment-specific fixture/UI stage completed on Staging.
F1a payment create has no demonstrated idempotency protection (open).
F1b no proof-detach workflow exists or was tested (open).
F1c payment audit remains best-effort (open).
F2/58L establishment reconciliation — PARTIAL (see section 5b). Canonical table `public.establishments` is deployed on Staging; Establishment Admin runtime acceptance PASS. Staff runtime NOT TESTABLE (no active staff); Employer full CRUD pending; establishment↔case binding and establishment-owned document link remain not implemented/unsupported.
```

Do not fix these implicitly during another stage.

## 7. Completed/frozen work relevant to continuation

- Owner-aware document link/unlink contract and audits have passed Stage 58K-C.
- PDF+Excel helper / LINE batch is completed and frozen.
- Attendance LINE group notification is paused pending quota/new testing window.
- Meta Ads analytics remains local/manual CSV; no live Meta API.
- No Production smoke or deployment has been approved.

## 8. Next work — not yet approved

No stage is automatically authorized by this lock. The immediate next action is:

1. **POST-PUSH-DOC-2 — final exact documentation diff and commit preparation** for this post-push documentation reconciliation. This is a review/commit-prep action, not a new implementation stage. (The F2/58L frontend/migration/documentation package itself is already committed and pushed as 81f03b9.)

Subsequent candidate stages, requiring separate owner approval:

2. **Employer CRUD Runtime Acceptance** — the next business candidate after this documentation checkpoint (not yet approved/started).
3. F2/58L Staff runtime acceptance — requires creating/enabling an active Staff fixture first (out of scope here).
4. Establishment↔case binding model, and the establishment-owned document-link decision — separate product stages.
5. Continue Phase 1 readiness backlog: mobile, import/export stress, security/IP/device, delete-approval acceptance, manuals, production readiness.
6. Decide the open F1 follow-ups (payment create idempotency, proof-detach) — F1 itself is closed and must not be re-offered as unstarted.

IDENT-1 identity/session hardening is a **parked design backlog**, not the active next stage.

The user must select and approve the next stage.

## 9. Mandatory session-start comparison

At the next session, compare live facts with this lock:

```bash
cd /d/dev/claude
git status --short --branch
git diff --check
git log --oneline --decorate -10
```

Read-only DB checks should verify only the values required for the next stage. If any canonical value differs, report:

```text
EXPECTED (CURRENT_STATE_LOCK)
ACTUAL (LIVE REPO/DB)
IMPACT
SAFE NEXT ACTION
```

Then stop before write.

## 10. Lock update rule

Update this file only when canonical state changes, such as:

- A stage closes.
- A migration/commit changes the authoritative baseline.
- A fixture is created/cleaned.
- A Production/Staging environment state changes.
- A known gap is resolved or reclassified.
- The approved next stage changes.

Do not overwrite history silently. Record major decisions in `DECISIONS_LOG.md` and test results in `TEST_PLAN.md`.
