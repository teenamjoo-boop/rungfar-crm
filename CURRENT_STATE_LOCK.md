# RUNGFA CRM — CURRENT STATE LOCK

> Canonical handoff snapshot after Stage 58K-C cleanup.
>
> Snapshot date: 2026-07-13 (Thailand time context). This file records the last verified state, not a substitute for live pre-flight. Re-verify Git and DB before every new mutation.

## 1. Canonical status

```text
PROJECT: RUNGFA CRM
REPO: D:\dev\claude
GIT BASH: /d/dev/claude
BRANCH: feature-attendance
HEAD: 54680ec
WORKING TREE: clean (code-baseline snapshot — see note below)

STAGING REF: bzwtknqvhvdmatangzqf
PRODUCTION REF: magwqolbjmwymqxelizl
PRODUCTION: untouched
LOCAL STAGING HTML: rungfar_crm_17.STAGING.local.html
PRODUCTION REF COUNT IN STAGING HTML: 0 (safety gate — must stay 0)
STAGING REF COUNT IN STAGING HTML: 4 (informational snapshot — re-report if the file changes)

LATEST CLOSED STAGE: Stage 58K-C Runtime Smoke
RUNTIME/STATIC MATRIX: T1–T13 recorded
MANDATORY TEST DOCUMENT CLEANUP: complete
OPTIONAL SOFT-DEACTIVATION: not performed
PRODUCTION SMOKE: not started
PAYMENT-SPECIFIC STAGE: not started
58L ESTABLISHMENT RECONCILIATION: not started
```

Working-tree note:

- Code baseline snapshot: HEAD `54680ec`; the **tracked** working tree was clean before the handoff documentation pack was added.
- Current pre-commit documentation state: only the approved handoff documents (`AGENTS.md`, `CURRENT_STATE_LOCK.md`, `DECISIONS_LOG.md`, `PROJECT_MASTER_HANDOFF.md`, `ROADMAP.md`, `TEST_PLAN.md`) and the `docs/handoffs/2026-07-13/` archive are untracked; no tracked application code, migration, SQL, or HTML file is modified.
- This does not claim the complete current working tree has zero untracked files. Do not replace HEAD `54680ec` with a future or guessed commit hash; update it only after the approved documentation commit is actually created.

## 2. Verified Staging database baseline after cleanup

```text
seed_docs (source=TEST_58K_SEED): 0
seed_links: 0
total case_documents: 0
case_payments: 0
audit_total: 131 (retained; id range observed 73–203)
non-seed documents: 0 in the isolated Staging fixture database
```

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

## 3. Stage 58K-C final result

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
- T13 Establishment: checklist path intentionally unsupported (`owner_link_not_supported`); Staging `employer_establishments` table is absent while some establishment RPCs are deployed. Static verification only; separate 58L stage required.

## 4. Cleanup result

Mandatory document cleanup completed successfully in Staging SQL Editor:

- Deleted exactly five marker-scoped `TEST_58K_SEED` documents.
- No `case_documents` or `case_payments` referenced them at cleanup time.
- No non-test document was touched.
- Customers, employers, cases, case workers, checklist items, and audit logs were not changed.
- Audit count stayed 131 because raw document deletion has no cleanup audit trigger and audit retention was intentional.
- Optional soft-deactivation of synthetic customers/employer was deliberately not performed.

## 5. Known product gaps carried forward

```text
G1 unlink does not auto-revert checklist received → missing.
G2 reset to missing retains checked_by_code and checked_at.
G3 UI chips: “ผ่าน” = approved, “ขาด” = missing, “ลิงก์” = linked docs; received is separate.
G4 checklist update audit is best-effort; link/unlink audit is strict.
R1 item17 retains stale checked_by_code/checked_at after fixture reset (instance of G2).
F1 payment-specific fixture/UI test stage pending.
F2/58L establishment table/RPC/schema reconciliation pending.
```

Do not fix these implicitly during another stage.

## 6. Completed/frozen work relevant to continuation

- Owner-aware document link/unlink contract and audits have passed Stage 58K-C.
- PDF+Excel helper / LINE batch is completed and frozen.
- Attendance LINE group notification is paused pending quota/new testing window.
- Meta Ads analytics remains local/manual CSV; no live Meta API.
- No Production smoke or deployment has been approved.

## 7. Next work — not yet approved

No stage is automatically authorized by this lock. Candidate next stages, in recommended order, are:

1. Documentation handoff pack commit (current migration work).
2. F1 Payment-specific Stage — design fixture and test real `case_payments`/proof flow.
3. F2 / Stage 58L Establishment Schema Reconciliation.
4. Continue Phase 1 readiness backlog: mobile, import/export stress, security/IP/device, delete-approval acceptance, manuals, production readiness.
5. Continue Phase 2 product stages after foundations are stable.

The user must select and approve the next stage.

## 8. Mandatory session-start comparison

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

## 9. Lock update rule

Update this file only when canonical state changes, such as:

- A stage closes.
- A migration/commit changes the authoritative baseline.
- A fixture is created/cleaned.
- A Production/Staging environment state changes.
- A known gap is resolved or reclassified.
- The approved next stage changes.

Do not overwrite history silently. Record major decisions in `DECISIONS_LOG.md` and test results in `TEST_PLAN.md`.
