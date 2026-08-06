# RUNGFA CRM — CURRENT STATE LOCK

> Canonical handoff lock. It records verified history through the Employer CRUD (Admin) runtime acceptance on Staging, plus the closed `LINE-PDF-DUAL-MODE-DESIGN` design review. The LINE PDF-to-images product remains at **DESIGN PASS — IMPLEMENTATION NOT STARTED**, with no LINE runtime or deployment recorded or approved. Separately, the Staging LINE asset foundation AP-1 through AP-4 is **PARTIAL**: the `line-assets` Storage bucket was created on Staging through one approved owner-assisted action and verified by a read-only metadata check; it still contains zero objects and does not constitute LINE runtime or implementation acceptance.
>
> Snapshot date: 2026-08-05 (Thailand time context) — LINE-PDF-DOC-CONSISTENCY-CORRECTION, documentation-only. Prior snapshots: 2026-07-26 (Employer CRUD Admin runtime acceptance) and 2026-07-22 (F1 documentation closeout). The F1 Payment-specific Stage runtime test and cleanup were executed and verified on Staging 2026-07-14; the section 2 database values are that historical baseline, superseded by section 5c. This file records the last verified state, not a substitute for live pre-flight. Re-verify Git and DB before every new mutation.

## 1. Canonical status

```text
PROJECT: RUNGFA CRM
REPO: D:\dev\claude
GIT BASH: /d/dev/claude
BRANCH: feature-attendance
CURRENT LIVE HEAD: read from Git every session (`git rev-parse HEAD`) — not frozen in this file
LATEST VERIFIED PRE-EDIT COMMITTED CHECKPOINT: 4c8b45e "Record Employer CRUD staging acceptance"
  Verification evidence — verified on 2026-08-05 before this documentation edit: local = origin/feature-attendance; 0 ahead / 0 behind; working tree and index clean before the six-file edit; no untracked files.
  This is HISTORICAL PRE-EDIT EVIDENCE for one dated verification, not a permanent current-HEAD field. Live HEAD and live working-tree state must always be read from Git (`git rev-parse HEAD`, `git status`) at the start of every session.
STAGE EVIDENCE COMMITS (historical): e9d035c = F1 runtime-test HEAD; bf40820 = F1 documentation-closeout commit; 2c30070 = post-closeout metadata sync; 80dcafe = recovery-inventory doc reconciliation; 81f03b9 = post-F2/58L Establishment Admin checkpoint (frontend toggle guard + migration 20260813 + F2/58L documentation); fbcf624 = post-push control-pointer reconciliation (documentation-only); 4c8b45e = Employer CRUD acceptance documentation commit (2026-07-26, five of the six documents)
WORKING TREE (historical pre-edit observation, 2026-08-05): clean before the six-file documentation edit began. The F2/58L package (rungfar_crm_17.html toggle guard, migration 20260813, and the F2/58L documentation) was committed and pushed as 81f03b9, followed by documentation-only commits fbcf624 and 4c8b45e. The local-only patched rungfar_crm_17.STAGING.local.html remains untracked/excluded. Re-verify live before any write.

STAGING REF: bzwtknqvhvdmatangzqf
PRODUCTION REF: magwqolbjmwymqxelizl
PRODUCTION: NOT MUTATED — no connector query, deployment, schema/data/Storage/policy change, or configuration change occurred. One separately approved owner-assisted read-only export of exactly two static icon files from the Production `line-assets` bucket was performed on 2026-08-05. Do not describe Production as untouched throughout this LINE asset workstream.
LOCAL STAGING HTML: rungfar_crm_17.STAGING.local.html
PRODUCTION REF COUNT IN STAGING HTML: 0 (safety gate — must stay 0)
STAGING REF COUNT IN STAGING HTML: 4 (informational snapshot — re-report if the file changes)

LATEST CLOSED RUNTIME STAGE: Employer CRUD (Admin) — PASS on Staging 2026-07-26
LATEST CLOSED DESIGN STAGE: LINE-PDF-DUAL-MODE-DESIGN — DESIGN PASS on 2026-08-05 (design only; no runtime, no implementation)
PRIOR CLOSED RUNTIME STAGES (historical): F2/58L Establishment Admin acceptance (2026-07-25, F2/58L overall PARTIAL); F1 Payment-specific Stage — closed 2026-07-14; Stage 58K-C Runtime Smoke
RUNTIME/STATIC MATRIX: T1–T13 recorded (58K-C)
MANDATORY TEST DOCUMENT CLEANUP: complete (58K-C)
F1 PAYMENT FIXTURE CLEANUP: complete
OPTIONAL SOFT-DEACTIVATION: not performed
PRODUCTION SMOKE: not started
PAYMENT-SPECIFIC STAGE: CLOSED on Staging
CANONICAL ESTABLISHMENT TABLE: public.establishments (deployed on Staging) — NOT public.employer_establishments
F2/58L ESTABLISHMENT: PARTIAL — Establishment Admin runtime acceptance PASS; duplicate-toggle fix PASS; same-state backend no-op PASS; fixture cleanup PASS
F2/58L STAFF RUNTIME: NOT TESTABLE — no active Staff fixture (0 active staff on Staging); applies to both Establishment and Employer
EMPLOYER CRUD (ADMIN): PASS — Employer Admin Runtime Acceptance closed on Staging 2026-07-26 (create / read / reload / single-field edit / audit + privacy / invariants / exact fixture cleanup / baseline restoration). Scope was Admin create-read-edit only
EMPLOYER CRUD (STAFF): NOT TESTABLE — 0 active Staff on Staging; recorded as neither PASS nor FAIL
EMPLOYER DELETE: not implemented — no delete RPC and no UI delete control; not tested
EMPLOYER ACTIVE/INACTIVE: not implemented — employers has no active/inactive or soft-delete concept; not tested
EMPLOYER DUPLICATE PREVENTION: PARTIAL — no database uniqueness guarantee and no proven double-submit guard
ESTABLISHMENT↔CASE BINDING: not implemented (cases.establishment_id absent)
ESTABLISHMENT-OWNED DOCUMENT LINK: unsupported/deferred (owner_link_not_supported)
MIGRATION 20260813 (same-state no-op): deployed via Staging SQL Editor ("Success. No rows returned") — migration-history registration UNVERIFIED
IDENT-1 IDENTITY/SESSION: design complete, implementation PARKED (not started)
CURRENT CONTROL STATUS: LINE-PDF-DUAL-MODE-DESIGN is documented at DESIGN PASS level; LINE implementation remains unauthorized.
LINE PDF-TO-IMAGES DUAL MODE: DESIGN PASS — implementation not started, not approved

LINE STAGING ASSET FOUNDATION (AP-1…AP-4, 2026-08-05): PARTIAL
BRANCH A: selected — preserve and later restore the existing PDF+Excel helper on Staging after removing its Production asset dependency. Branch A is NOT code-change approval, NOT deployment approval, and NOT Production approval
STAGING BUCKET line-assets: VERIFIED ON STAGING — created by one OWNER-ASSISTED MUTATION (AP-3), then verified READ-ONLY PASS (AP-4)
  public=true; file_size_limit=2097152 bytes; allowed_mime_types=[image/png]; object_count=0
  line-assets-specific Storage policy count=0; total Staging buckets=3; public Staging buckets=1
  created_at and updated_at were equal at AP-4 verification; no post-creation bucket update was observed in that metadata snapshot
BUCKET PURPOSE: configured public for non-sensitive static UI icons only; public write is NOT approved; public object retrieval remains untested
PDF ICON OBJECT: NOT UPLOADED
EXCEL ICON OBJECT: NOT UPLOADED
LINE IMAGE RENDERING: untested
line-ai-excel-helper: BLOCKED FROM DEPLOYMENT — four Production asset references remain in tracked source
line-ai-excel-finalize-due: BLOCKED FROM DEPLOYMENT — three Production asset references remain in tracked source
ASSET-DECOUPLING CODE EDIT: not performed
LINE EDGE FUNCTION DEPLOYMENT: none
ASSET URL STRATEGY: UNRESOLVED — pending a separately approved stage
EXISTING PDF+EXCEL HELPER: FROZEN
LINE PDF-TO-IMAGES DUAL MODE (unchanged by this foundation): DESIGN PASS — IMPLEMENTATION NOT STARTED
```

Repository HEAD/snapshot semantics:

- **Current live HEAD is obtained from Git pre-flight, never from a value frozen in this file.** The hashes recorded here are dated snapshots and historical stage evidence.
- Latest verified pre-edit snapshot: `4c8b45e` (2026-08-05) — `local = origin/feature-attendance`, 0 ahead / 0 behind, working tree clean before the six-file documentation edit. Earlier historical snapshots: `fbcf624` (2026-07-26) and `2c30070` (2026-07-23), each verified `local = origin`, 0 ahead / 0 behind, working tree clean on its own date. None of these is a permanent current-HEAD field. A live HEAD newer than the latest snapshot is only a HARD STOP when the newer commit(s)/working tree introduce a meaningful unexplained change (application code, schema/migration, HTML, configuration, environment, or an unrecorded Stage-status change). A documentation-only commit newer than the snapshot does not invalidate recorded Stage evidence.
- Historical stage evidence: `bf40820` = F1 documentation-closeout commit (2026-07-22, six-doc edit, pushed). `e9d035c` = the HEAD at which the F1 runtime test was executed on 2026-07-14, and parent of `bf40820`. `54680ec` = code-baseline HEAD during Stage 58K-C. All are historical evidence, not current state.
- Documentation-only commit `bf40820` changed **all six** source-of-truth Markdown files (`AGENTS.md`, `CURRENT_STATE_LOCK.md`, `DECISIONS_LOG.md`, `PROJECT_MASTER_HANDOFF.md`, `ROADMAP.md`, `TEST_PLAN.md`). Documentation-only commit `2c30070` changed **only four** of them (`AGENTS.md`, `CURRENT_STATE_LOCK.md`, `PROJECT_MASTER_HANDOFF.md`, `ROADMAP.md`). Neither commit modified application code, HTML, migration, SQL, or configuration.

## 2. Verified Staging database baseline after F1 cleanup

Baseline verified read-only immediately after the F1 fixture cleanup on 2026-07-14.

> Note (2026-07-24 documentation reconciliation): the database values in this section are **documented historical evidence — not re-verified in this documentation pass** (no database was queried). Re-verify read-only before any dependent action.
>
> Note (2026-07-26): this section remains the **F1-era historical baseline**. The **current** verified Staging baseline is recorded in section 5c after the Employer CRUD stage (`audit_logs 144`, `audit max id 216`; entity counts unchanged). The audit progression is continuous: F1 closing `135` (max id 207) → `+7` retained `establishment/1` rows from F2/58L → `142` (max id 214) → `+2` retained `employer` rows from the Employer CRUD stage → `144` (max id 216).

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

## 3. F1 Payment-specific Stage result — CLOSED (historical verified record)

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

**Still pending / not implemented:** Staff runtime acceptance (NOT TESTABLE — 0 active staff; static contract allows active staff to create/edit under role-not-null, toggle is Admin-only); establishment↔case binding (`cases.establishment_id` absent); establishment-owned document linking (`owner_link_not_supported`, deferred). Production: not started. (Employer CRUD acceptance was pending at the time of this section; the Admin path has since closed PASS — see section 5c.)

## 5c. Employer CRUD Admin runtime acceptance (current)

Executed operator-assisted on Staging (`rungfar-crm-staging`, ref `bzwtknqvhvdmatangzqf`) with SELECT-only verification, closed 2026-07-26. Production ref `magwqolbjmwymqxelizl` was **not queried and not touched**. Full evidence: `TEST_PLAN.md` section 8d.

**Employer Admin Runtime Acceptance — PASS.** Create through the real Employer UI (`employers` 2 → 3, exactly one fixture row, blank optional fields persisted as null); detail/read PASS; full-page reload persistence PASS; single-field edit PASS (among business fields only `phase2_note` changed, to `EMPCRUD_EDITED_1`; `updated_at` advanced automatically as expected; no other business field changed); create audit id `215` (`employer.phase2.create`, actor role admin, detail `{"internal_only": true}`) and update audit id `216` (`employer.phase2.save`, exactly one save row) both privacy-safe; relationship invariants held; exact fixture cleanup PASS; baseline restoration PASS.

Synthetic fixture (created and removed within the stage):

```text
employer id=3  ZZ_TEST_EMPCRUD_20260726_A  employer_kind=company
related customers / establishments / cases / documents: 0 / 0 / 0 / 0
```

Baseline before → after:

```text
employers 2 → 2        customers 4 → 4        establishments 0 → 0
cases 2 → 2            documents 0 → 0
audit_logs 142 → 144   audit max id 214 → 216
exact marker count 0 → 1 → 0   marker-name count 0 → 1 → 0
```

Cleanup: the operator ran the approved marker-and-id-scoped transaction once in the Staging SQL Editor, deleting exactly employer id 3 with the exact marker name. All four relation guards (customers / establishments / cases / documents referencing that employer) were zero. **No audit row was deleted**; ids `215` and `216` are retained append-only evidence.

Protected invariants held throughout:

```text
employer id 1 unchanged; employer id 2 unchanged
customer/worker id 3 still linked to employer id 2
employer id 2 establishments: 0
case id 1: draft, employer_id null
case id 2: cancelled, employer_id 2
case id 1 checklist: total 17, missing 13, received 4, approved 0
```

**Staff:** active users total 1, active Admin 1, **active Staff 0** → Employer Staff Runtime **NOT TESTABLE**, recorded as neither PASS nor FAIL. No Staff account was created.

**Not in scope / not implemented:** employer delete (no delete RPC, no UI control) and employer active/inactive (no such column or concept) — neither was tested. Duplicate prevention remains PARTIAL (no database uniqueness guarantee, no proven double-submit guard; the operator submitted once only). Audit remains best-effort and its detail does not identify the changed field. Migration-history registration remains UNVERIFIED. Production not started. **F2/58L overall remains PARTIAL** — this stage closes the Employer Admin path only.

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
F2/58L establishment reconciliation — PARTIAL (see section 5b). Canonical table `public.establishments` is deployed on Staging; Establishment Admin runtime acceptance PASS. Staff runtime NOT TESTABLE (no active staff); establishment↔case binding and establishment-owned document link remain not implemented/unsupported.
E1 Employer duplicate prevention is PARTIAL — no database uniqueness guarantee on employers and no proven double-submit guard on the save path (open).
E2 Employer delete is not implemented — no delete RPC and no UI delete control, so **no normal user-facing Employer delete workflow exists**. The marker-scoped SQL cleanup run in the Employer CRUD stage was approved **only for the exact synthetic fixture** and is not a delete path for real employers; deleting a real Employer record requires a separate product/control decision and approval (open).
E3 Employer active/inactive is not implemented — employers has no active/inactive or soft-delete concept (open).
E4 Employer audit is best-effort and its detail does not identify which field changed; field-level proof requires SELECT comparison (open, related to G4).
```

Do not fix these implicitly during another stage.

## 7. Completed/frozen work relevant to continuation

- Owner-aware document link/unlink contract and audits have passed Stage 58K-C.
- The existing PDF+Excel helper / LINE batch is completed and **remains frozen** from unrelated work.
- **LINE PDF-to-images dual mode — DESIGN PASS (design stage only).** Summary of the approved design: a person sends a PDF into the existing operational LINE group and types `จบ` to receive the pages as ordinary LINE image messages. The same existing group is the **preferred** target, subject to router and environment verification in a later pre-check. **Saving Mode is the default** for unconfigured groups; **Auto Mode is controlled by database-backed admin authority and is bound to the job's original group**. Pages are delivered in ranges of **up to five images**; the **first range uses Reply**, and remaining **Auto ranges use Push**. **One delivery stream per LINE group.** Reply and Push ambiguity use **different** recovery rules. An **external Cloud Run converter worker** was selected for the MVP design. Cross-group routing is **out of scope**. **No implementation has started**; no database object, GCP resource, Staging runtime, quota window, or Production action is approved by this design.
- Attendance LINE group notification is paused pending quota/new testing window.
- Meta Ads analytics remains local/manual CSV; no live Meta API.
- No Production smoke or deployment has been approved.

## 8. Next work — not yet approved

No stage is automatically authorized by this lock.

```text
DOCUMENTATION PACKAGE CLOSURE CONDITION:
This six-file documentation package is closed only when all six approved files
are committed together and verified on origin/feature-attendance.

NEXT TECHNICAL CANDIDATE AFTER CLOSURE:
A separately owner-approved LINE implementation pre-check.
Implementation is not automatically authorized.
```

```text
NEXT CONTROLLED DEPENDENCY (LINE asset foundation):
A separately approved read-only pre-check for uploading only the PDF icon as the
first Staging `line-assets` object.

Each of the following remains its own separate approval:
  PDF icon upload
  PDF icon verification
  Excel icon upload
  Excel icon verification
  asset-decoupling code edit
  static verification
  each Edge Function deployment
  webhook activation
  every runtime test
  documentation commit
  push
```

The documentation package procedure is: documentation edit → read-only verification → owner diff review and approval → commit → push → verify on `origin/feature-attendance`. That is a procedure, not an assertion about which step is currently in progress; read live Git to determine that. (The Employer Admin runtime acceptance and its documentation closeout are complete and committed as `4c8b45e`; the F2/58L frontend/migration/documentation package was committed and pushed as `81f03b9`, followed by documentation-only commit `fbcf624`.)

**Implementation remains blocked.** No implementation approval, no migration approval, no Edge Function or Cloud Run deployment approval, no GCP resource approval, no Staging runtime approval, no quota window, and no Production approval exists.

Subsequent candidate stages, requiring separate owner approval:

2. **Staff runtime acceptance (Establishment + Employer)** — requires creating/enabling an active Staff fixture first; currently NOT TESTABLE with 0 active Staff.
3. **Employer duplicate-prevention decision (E1)** — whether to add a database uniqueness rule and/or a double-submit guard on the Employer save path.
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
