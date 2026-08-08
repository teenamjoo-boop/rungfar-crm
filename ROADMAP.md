# RUNGFA CRM — ROADMAP

> Product and technical roadmap after the 2026-07-13 handoff.
>
> This file states intended sequencing. `CURRENT_STATE_LOCK.md` states the latest verified reality. A roadmap item is not permission to start it.

## 1. Product north star

Build a practical internal system that is easier than Excel and supports the real operating flow of RUNGFA RUNGFA CO., LTD.:

1. Keep one trusted profile for each worker/customer, employer, establishment, case, and document.
2. Turn work into clear queues, statuses, missing-document lists, assignments, deadlines, and audit trails.
3. Prepare complete case packages before staff submit them to e-WorkPermit or other government systems.
4. Reduce repeated typing and document mistakes without pretending the CRM is the government system.
5. Roll out safely: foundations → small-user test → fixes → 12-user production use.

## 2. Roadmap status legend

- ✅ **COMPLETE / CLOSED** — evidence and closeout recorded.
- 🟢 **FOUNDATION EXISTS** — implemented historically, but may need readiness regression.
- 🟡 **PARTIAL / NEXT** — important work remains.
- ⚪ **PLANNED** — analyzed, not yet implemented.
- ⏸ **DEFERRED / FROZEN** — intentionally paused.
- 🔴 **BLOCKED / PREREQUISITE** — cannot safely proceed yet.

## 3. Current position

```text
Stage 58K-C owner-aware document runtime smoke: ✅ closed
Mandatory synthetic document cleanup: ✅ closed
F1 payment-specific test stage: ✅ closed on Staging 2026-07-14
F1 fixture cleanup / baseline restore: ✅ closed
F1 documentation closeout: ✅ committed and pushed 2026-07-22 (bf40820)
Production smoke/deploy: ⏸ not started
Establishment foundation (public.establishments + RPC + UI): ✅ deployed on Staging (canonical table public.establishments)
F2/58L Establishment: 🟡 PARTIAL — Admin runtime acceptance ✅ PASS; duplicate-toggle fix ✅ PASS; same-state backend no-op (migration 20260813) ✅ PASS; fixture cleanup ✅ PASS; Staff runtime ⚪ NOT TESTABLE (no active staff)
Employer CRUD (Admin) runtime acceptance: ✅ PASS — closed on Staging 2026-07-26 (create/read/reload/single-field edit/audit+privacy/invariant/cleanup/baseline restore)
Employer CRUD (Staff) runtime acceptance: ⚪ NOT TESTABLE — no active Staff fixture
Employer delete / active-inactive: ⚪ NOT IMPLEMENTED — out of scope until a product decision
Employer duplicate prevention: 🟡 PARTIAL — no database uniqueness guarantee, no proven double-submit guard
LINE PDF-to-images dual mode: 🟡 DESIGN PASS (2026-08-05) — implementation not started, not approved; no GCP, Staging runtime, or Production approval
LINE Staging asset foundation (AP-1…AP-4 2026-08-05; PDF icon 2026-08-06/07): 🟡 PARTIAL — Branch A selected; Staging bucket `line-assets` created by one owner-assisted action and verified READ-ONLY PASS (public, 2,097,152-byte limit, image/png only; 0 objects at AP-4); PDF icon ✅ uploaded and read-only verified (bucket object count now 1, accepted name `ChatGPT Image Jun 3, 2026, 02_52_40 PM.png.png`, image/png, 734,889 bytes); Excel icon upload, asset-decoupling code edit, Edge Function deployments, webhook activation, public retrieval, and all runtime tests remain pending
Appointments / tracking / case-status-history / contact-timeline: 🟢 repo foundation; ⚪ runtime acceptance not found
ai_autopost_system.html: ⚪ standalone tracked file; scope/ownership/testing unconfirmed; not yet classified as Core CRM — final classification pending owner decision
Phase 1 production readiness: 🟡 incomplete
Phase 2 case-management product: 🟢 foundation + ⚪ remaining stages
```

## 4. Phase 0 — Repository and operational control

### 0.1 Source-of-truth handoff pack — CURRENT

Deliverables:

- `PROJECT_MASTER_HANDOFF.md`
- `AGENTS.md`
- `CURRENT_STATE_LOCK.md`
- `ROADMAP.md`
- `TEST_PLAN.md`
- `DECISIONS_LOG.md`

Acceptance:

- Files reviewed by user.
- Copied to repo root.
- Git diff contains documentation only.
- Commit/push performed only after explicit approval.
- New ChatGPT Project uses these files as primary context.

### 0.2 Working protocol

- Chat/Work = planning and control.
- Claude Code/Codex = one primary implementer per stage.
- Repo/DB = live truth.
- State Lock updated after every closed stage.

## 5. Phase 1 — Core CRM stability and production readiness

### 1.1 Security, identity, sessions, and audit — 🟢 foundation / 🟡 acceptance pending

Already present:

- `app_users` and admin/staff roles.
- RLS/session hardening.
- Security/audit RPC foundations.
- User-management and inactive-user concepts.

Remaining:

- End-to-end device/IP/session alert testing.
- New-device/suspicious-login notification design.
- Password-sharing reduction controls.
- Confirm delete-request/approval workflow for customer/document records.
- Verify audit access, retention, and privacy on production-like data.
- Role matrix acceptance for admin/staff and future specialized roles.

Exit criteria:

- Security test plan passes on Staging.
- No unauthorized direct write/delete path.
- Production rollback and incident procedure documented.

### 1.2 Attendance, GPS, and LINE Messaging API — 🟢 foundation / ⏸ notification paused

Already present:

- Check-in/out flow and attendance pages.
- LINE group Flex notification was previously functional.

Remaining:

- Fix/verify aggregate absence notification that once showed zero until detail page was opened.
- Test GPS/device/time handling on small-user group.
- Re-enable LINE group notifications only after quota plan and controlled test.
- Mobile browser and LINE in-app-browser behavior verification.

Exit criteria:

- 2–3-user pilot passes.
- Quota and failure behavior understood.
- Notification can be disabled without breaking attendance.

### 1.3 Customer/worker and employer master data — 🟢 foundation / 🟡 profile completion

Worker profile remaining fields/workflows:

- Passport/CI, Visa, Work Permit and expiry dates/statuses.
- e-WorkPermit account metadata (no password storage).
- Thai address, employer/establishment history, case history.
- Document completeness and notes.
- Duplicate detection and merge policy.

Employer profile remaining fields/workflows:

- Company certificates, tax/VAT, commercial registration.
- Authorized signatories and powers of attorney.
- Establishments/branches and assigned workers.
- Case history and expiring documents.

Exit criteria:

- One source of truth for worker and employer.
- Import/export preserves identifiers and dates.
- Mobile and desktop CRUD regression passes.

### 1.4 Import/export and data quality — 🟢 foundation / 🟡 stress testing

Remaining:

- Large-file tests.
- Duplicate and invalid-row handling.
- Transaction/rollback behavior.
- Date/ID/phone leading-zero preservation.
- Excel scientific notation regression.
- Clear error report and safe retry.

### 1.5 Mobile readiness and UX cleanup — 🟡

Remaining:

- Fix pages/modals that cannot scroll on mobile.
- Test shared sidebar/modal/table behavior across common screen sizes.
- Compact labels and actions for staff use.
- Preserve zero-fix typography.
- Produce short user manual.

### 1.6 Production readiness — 🔴 prerequisite before rollout

Required:

- Staging acceptance matrix.
- Backup/restore and rollback plan.
- Environment/ref verification.
- Minimal Production smoke plan using non-destructive real/prod-safe data.
- Monitoring/audit plan.
- 2–3-user pilot plan, then 12-user rollout plan.

No Production deploy is approved merely by completing Staging work.

## 6. Phase 2 — Labor-document case center

### Product identity

User-facing direction:

- “งานเอกสารแรงงาน”
- “เคสเอกสารแรงงาน”
- “ศูนย์งานเอกสารแรงงาน”

Avoid presenting it as a government system. It is the internal preparation and tracking center before real submission.

### 2.1 Document Vault / Storage Foundation — 🟢 existing foundation / 🟡 hardening

Goals:

- Private file storage with metadata and owner.
- Signed URL access.
- Expiry/status and duplicate rules.
- Upload/open/download audit without secret/path leakage.
- Consistent document ownership for worker, employer, case, internal, and later establishment/payment flows.

Stage 58K-C owner-aware link/unlink testing is complete for worker, case, employer, and internal paths.

### 2.2 Worker Profile Upgrade — ⚪

Build the full worker record needed by all case types and document generation. Do not duplicate data per case when it belongs to the worker profile.

### 2.3 Employer Profile Upgrade — ⚪

Build full company, authorized-person, establishment/branch, worker-assignment, and document-expiry records.

### 2.4 Basic Case Management — 🟢 foundation / 🟡 expand

Core case workflow:

```text
create case
→ choose case type / legal basis / form
→ attach workers and employer/establishment
→ generate checklist
→ collect and review documents
→ ready to submit
→ record submission number/payment/appointment
→ track corrections/approval/result
→ close or cancel
```

Required features:

- Case number, type, status, owner/assignee, priority, deadlines.
- Multiple workers/Name List.
- Notes, timeline, audit, payment, appointments, submission records.
- Work queues and dashboard summaries.

### 2.5 Checklist Templates from official PDFs — ⚪ high priority

Templates to verify against current official manuals/files:

- Foreign-worker registration.
- MOU Section 41/46 and N.J.2.
- MOU handover Section 43 / B.T.13.
- Employer notice of worker entering/leaving work, including B.T.53-related flow.
- Section 60 paragraph 2 / B.T.32.
- B.T.31 / B.T.33 and related forms.
- Case-specific Cabinet resolutions and supporting documents.

Rules:

- PDF/manual content must be verified; filenames/headings may be inconsistent.
- Templates must be versioned and effective-dated.
- Checklist should distinguish worker, employer, company, establishment, case, payment, and internal evidence.

### 2.6 F1 Payment-specific Stage — ✅ CLOSED (Staging, 2026-07-14)

Original reason for the stage:

- Payment checklist items are guidance-only.
- Real proof flow uses `case_payments` and `app_save_case_payment`/proof-document linkage.
- Stage 58K-C T12 had no payment fixture and was not runtime-testable.

Acceptance evidence:

- Payment created through the real payment UI on disposable case id 2: exactly one row, `service_fee`, due 100 / paid 0, status `unpaid`.
- Same-case proof linked through the dedicated payment-proof UI: `case_payments.proof_document_id` set; **no** `case_documents` row created; the normal checklist `owner_type='payment'` path was never exposed or used.
- Wrong-case proof protection: absent from the picker plus deployed `document_not_allowed` verified statically — classified as **UI runtime-observed + backend static verified, no forced live negative write**.
- Update by ID modified the same row only and preserved the proof link; status transition `unpaid → cancelled` preserved the proof and left `paid_at` null.
- Audit rows 204–207 append-only with zero forbidden-key hits; original case invariant 17 items / 13/4/0 held throughout.
- Fixture cleanup deleted exactly one payment and two documents; audit retained; baseline restored (`case_payments` 0, documents 0, `case_documents` 0, audit 135 / ids 73–207).
- No migration and no application-code change were required.

Open follow-ups (not blocking; require a product/technical decision before any dedicated stage):

- Payment create has no demonstrated idempotency protection.
- No proof-detach workflow exists or was tested.
- Payment audit remains best-effort.

Full record: `TEST_PLAN.md` section 7.

### 2.7 F2 / Stage 58L Establishment — 🟡 PARTIAL (Admin acceptance + toggle hardening complete on Staging)

Canonical fact: the deployed table is `public.establishments` (migration filename `20260804_employer_establishments.sql` differs from the table name). It exists on Staging with RPCs `app_save_establishment`/`app_set_establishment_active`/`app_get_employer_detail`/`app_list_employers_phase2` and an Establishment UI inside Employer detail. `public.employer_establishments` is **not** a deployed table.

**Completed on Staging:**

- Canonical table/RPC reconciliation (public.establishments confirmed deployed).
- Establishment Admin runtime acceptance: create → SELECT verify → audit/privacy → reload → edit → update audit → inactive toggle → active restore — PASS.
- Frontend duplicate-toggle guard (per-establishment in-flight guard + button disable) — PASS.
- Backend same-state no-op (migration `20260813_establishment_set_active_same_state_noop.sql`, applied once via Staging SQL Editor) — PASS.
- Post-fix Admin runtime regression (active↔inactive single-audit; same-state active→active no-op audit-free) — PASS.
- Synthetic fixture cleanup (baseline establishments under employer id=2 back to 0; audit retained) — PASS.

**Remaining:**

1. Active Staff test fixture + Staff runtime permission acceptance, covering **both Establishment and Employer** (currently NOT TESTABLE — 0 active staff; static contract: active staff may create/edit under role-not-null, establishment toggle is Admin-only).
2. Employer CRUD acceptance — **Admin path ✅ closed PASS on Staging 2026-07-26** (see section 2.7b). Remaining: Staff permission matrix, plus the employer delete / active-inactive / duplicate-prevention decisions.
3. Migration-history registration decision/evidence (deployment proven; history registration UNVERIFIED — SQL Editor run, no manual history row).
4. Establishment↔case model (`cases.establishment_id` absent → binding not implemented).
5. Establishment-owned document-link decision/stage (`owner_link_not_supported`, deferred).
6. Production plan and approval (not started).

### 2.7b Employer CRUD runtime acceptance — ✅ Admin path CLOSED (Staging, 2026-07-26)

Scope of the closed stage: **Admin create / read / full-page reload persistence / single low-risk field edit / server audit + privacy / relationship invariants / exact fixture cleanup / baseline restoration** on Staging (`bzwtknqvhvdmatangzqf`). Production was not queried or touched.

Acceptance evidence:

- Create through the real Employer UI: `employers` 2 → 3, exactly one fixture row (`employer id=3`, `ZZ_TEST_EMPCRUD_20260726_A`, `employer_kind=company`), all intentionally blank optional fields persisted as null.
- Detail/read: workers 0, establishments 0, employer documents 0; full refresh preserved the row and the detail reopened successfully.
- Single-field edit: among business fields, only `phase2_note` changed, to `EMPCRUD_EDITED_1`; `updated_at` advanced automatically as expected; no other business field changed. Employer count stayed 3; marker count stayed 1; no duplicate submit observed.
- Audit: id `215` `employer.phase2.create` and id `216` `employer.phase2.save` — exactly one save row, actor role admin, detail `{"internal_only": true}`, privacy scan PASS on both.
- Invariants held: employer id 1 and id 2 unchanged; worker id 3 still linked to employer id 2; employer id 2 establishments 0; case id 1 draft with `employer_id` null; case id 2 cancelled with `employer_id` 2; case id 1 checklist 17 / 13 missing / 4 received / 0 approved.
- Cleanup: operator ran the approved marker-and-id-scoped transaction once in the Staging SQL Editor; deleted exactly employer id 3 with the exact marker name; all four relation guards zero; no audit row deleted.
- Baseline restored: employers 2, customers 4, establishments 0, cases 2, documents 0, audit_logs 144 (max id 216, ids 215/216 retained), marker count 0.

**Verdict: Employer Admin Runtime Acceptance = PASS.** Full record: `TEST_PLAN.md` section 8d.

**Remaining / not implemented (do not treat the Employer workstream as complete):**

1. Employer **Staff** runtime acceptance — NOT TESTABLE (0 active Staff); needs an active Staff fixture in a separately approved stage.
2. Employer **delete** — not implemented (no delete RPC, no UI control) and not tested; **no normal user-facing Employer delete workflow exists**. The marker-scoped SQL cleanup in this stage was approved **only for the exact synthetic fixture** and must not be treated as a delete path for real employers — deleting a real Employer record requires a separate product/control decision and approval.
3. Employer **active/inactive** — not implemented (no such column or concept) and not tested.
4. **Duplicate prevention (E1)** — PARTIAL: no database uniqueness guarantee and no proven double-submit guard; requires a product decision before multi-user rollout.
5. **Audit strictness (E4)** — best-effort, and audit detail does not identify the changed field.
6. Production — not started.

### 2.8 Submission tracking and after-submission records — 🟢 repository foundation / ⚪ runtime acceptance not found

Repository foundation exists but no runtime acceptance evidence was found, and deployed database state was not queried: `case_tracking_logs` (`app_add_case_tracking_log`/`app_list_case_tracking_logs`), `case_appointments` (`app_save_case_appointment`/`app_set_case_appointment_status`/`app_case_appointment_summary`), `case_status_logs` (`app_change_case_status`), and contact timeline (`contact_logs`/`work_timeline`, `app_add_contact_log`/`app_add_work_timeline`). Each needs its own approved test stage — do not treat as Runtime PASS, Staging ready, or Production ready.

Store:

- e-WorkPermit request number.
- Receipt/payment proof.
- Appointment.
- Requests for correction/additional documents.
- Approval/result documents.
- Follow-up dates and final closure notes.

Do not automate real submission until a separate security/legal/operational review.

### 2.9 Document generator / Single-entry — ⚪ later

Goal:

- Enter worker/employer data once and generate controlled templates such as employment contracts, powers of attorney, cover sheets, MOU supporting documents, entering/leaving-work preparation forms, and 90-day reporting documents.

Prerequisites:

- Stable profiles.
- Versioned templates.
- Complete case/checklist mapping.
- Human review before use/submission.

### 2.10 OCR / AI Assist — ⚪ later

Possible uses:

- Read passport/CI/Visa/WP metadata.
- Suggest document type and expiry date.
- Flag missing/inconsistent fields.

Human confirmation is mandatory. Do not auto-overwrite master data or submit government applications.

## Operational LINE Document Automation

A separate operational workstream, **not** part of the Phase 2 labor-document product. It is listed here between Phase 2 and Phase 3 without renumbering the product phases.

### LINE PDF-to-images dual mode — 🟡 DESIGN PASS / implementation gated

**Status: design approved on 2026-08-05. Implementation has not started and is not approved.**

Approved design, at summary level:

- **Same existing operational group is the preferred target**, subject to router and environment verification in a separate implementation pre-check.
- **Saving Mode is the default** for unconfigured groups.
- **Auto Mode is controlled by database-backed admin authority** and is bound to the job's original group.
- Commands: `โหมดประหยัด` / `โหมดออโต้` / `ดูโหมด`.
- A PDF sent into the group is converted to **page images**.
- Pages are delivered in ranges of **up to five images**.
- The **first range uses Reply**.
- Remaining **Auto ranges use Push**.
- **One group-wide delivery stream**, so pages from two documents cannot interleave in one group.
- An **external Cloud Run converter worker** was selected for the MVP design.
- **Reply ambiguity requires explicit user resolution.**
- **Push uses time-bounded retry episodes and exact-payload reuse.**
- **Cross-group automation is out of scope.**

Not approved by this design stage:

- No implementation, no code change, no migration.
- No GCP resource creation, no Cloud Run deployment.
- No Staging runtime environment selection — that requires a separate decision and pre-check.
- No Production implementation or deployment.

#### Staging asset foundation progress (AP-1…AP-4 on 2026-08-05; PDF icon upload + verification 2026-08-06/07) — 🟡 PARTIAL

**Storage-foundation progress only.** It does not change the design status above and is not implementation, deployment, or runtime acceptance.

- **Branch A selected:** preserve and later restore the existing frozen helper on Staging after removing its Production asset dependency, under a dedicated approved stage. **Not code-change, deployment, or Production approval.**
- Staging Storage bucket `line-assets`: **VERIFIED ON STAGING** — created by one owner-assisted Dashboard action, then verified read-only: `public = true`, `file_size_limit = 2,097,152` bytes, `allowed_mime_types = [image/png]`, 0 `line-assets`-specific Storage policies. Object count was **0 at AP-4 (2026-08-05, historical)** and is **1 as verified on 2026-08-07**; the bucket contract values were re-verified unchanged.
- Bucket purpose: configured public for non-sensitive static UI icons only. **Public write is not approved. Public object retrieval remains untested. LINE image rendering remains untested.**
- **PDF icon: ✅ UPLOADED AND READ-ONLY VERIFIED** — one owner Dashboard upload on 2026-08-06, verified read-only on 2026-08-07. Accepted permanent object name `ChatGPT Image Jun 3, 2026, 02_52_40 PM.png.png` (doubled `.png` extension explicitly accepted by the owner; no rename, delete, replacement, or re-upload required), `image/png`, 734,889 bytes, `created_at = updated_at = 2026-08-06 17:49:17.996475+00`. Size and MIME match the approved source asset; Storage metadata exposes no checksum, so this is **not** a SHA-256 byte-identity proof. **Excel icon: NOT UPLOADED.**
- `line-ai-excel-helper` (four Production asset references) and `line-ai-excel-finalize-due` (three Production asset references): **BLOCKED FROM DEPLOYMENT**.
- **No asset-decoupling code edit has been performed.** **Asset URL strategy: UNRESOLVED.**
- **Production NOT MUTATED** — no connector query, deployment, or schema/data/Storage/policy/configuration change. One separately approved owner-assisted read-only export of two static icon files was performed on 2026-08-05; do not describe Production as untouched throughout this workstream.
- All remaining icon uploads, code edits, Edge Function deployments, webhook changes, and runtime tests **require separate approval**.

Full evidence: `TEST_PLAN.md` section 8f (bucket foundation) and section 8g (PDF icon upload + read-only verification).

Gates, each requiring its own owner approval, in order:

```text
1. Six-file documentation package — closed only when all six approved files are
   committed together and verified on origin/feature-attendance
2. LINE implementation pre-check (read-only)
3. Local implementation and container proof of concept
4. Owner review of measured proof-of-concept evidence
5. Approval to create and configure GCP resources
6. If the implementation pre-check proves a migration is required: prepare the
   exact Staging migration plan and obtain separate approval; the owner runs it
   once only after Staging target proof
7. Deploy only to the separately approved Staging/test environment, initially
   unreferenced; verify without changing any live Production router
8. Router canary on an owner-approved isolated test target. A new LINE group is
   not required by default; the target must be selected during the
   implementation pre-check
9. Saving-mode runtime test
10. Auto-mode runtime test inside an owner-approved quota window
11. Regression verification of the existing frozen helper
12. Rollback readiness verification
13. Documentation update, commit, push
14. Separate production-wide enablement approval
```

## 7. Phase 3 — Customer upload portal / PWA — ⚪

Planned after core readiness:

- Customer/employer upload links.
- Mobile photo capture and document status.
- Secure limited access.
- No access to unrelated customers/cases.
- Audit, expiry, and notification integration.

## 8. Deferred ideas

- Decorative animated/pixel office with about 12 characters and speech bubbles — after CRM completion.
- Live Meta Ads API integration — requires separate token/security/data stage.
- Fully autonomous government-system submission — not approved.
- `ai_autopost_system.html` — a standalone tracked file that is not wired into the main CRM navigation; the Recovery Inventory (2026-07-24) flagged it as Meta content-planning/autopost. Its scope, ownership, operational use, and testing status are unconfirmed. It is not currently classified as Core CRM and is not Production-ready or completed; final classification is pending owner decision. Meta inside the CRM stays local/manual CSV and live Meta API remains not approved.

## 9. Recommended execution order from this handoff

```text
0. F1 documentation closeout — done (bf40820); recovery-inventory doc reconciliation — done (80dcafe)
1. F2/58L Establishment — PARTIAL: Admin runtime acceptance + duplicate-toggle hardening + same-state no-op + cleanup done on Staging — **committed + pushed (81f03b9)**
2. Employer CRUD Runtime Acceptance (Admin) — ✅ closed PASS on Staging 2026-07-26; documentation closeout ✅ complete and committed (4c8b45e)
3. LINE-PDF-DUAL-MODE-DESIGN — ✅ DESIGN PASS 2026-08-05 (design only; implementation not started, not approved)
4. Six-file documentation package (LINE-PDF-DOC-CONSISTENCY-CORRECTION) — a prerequisite to the LINE implementation pre-check. It is CLOSED only when all six approved files are committed together and verified on origin/feature-attendance
5. After that closure condition is met: the next candidate is a separately approved LINE implementation pre-check (read-only). Implementation is NOT automatically approved
6. Employer remaining: Staff runtime (needs active staff fixture), and the delete / active-inactive / duplicate-prevention (E1–E3) product decisions
7. F2/58L remaining: Staff runtime (same fixture prerequisite), migration-history decision, establishment↔case + establishment-owned document decisions
8. Complete Phase 1 mobile/security/import-export/production-readiness gaps
9. Decide the open F1 follow-ups (create idempotency, proof-detach) if they become blocking
10. Run 2–3-user pilot → fix findings → roll out to 12 users
11. Continue Phase 2 checklist/profile/case-template expansion
12. Add document generation/OCR/portal later

IDENT-1 identity/session hardening remains a parked design backlog (not the active next stage).
```

F1 is closed and must no longer be offered as an unstarted choice.

Do not run F1 and 58L simultaneously on the same branch. This prohibition remains on record: if any F1 follow-up stage is ever opened, it must not overlap with 58L.

## 10. Roadmap update rule

After every closed stage:

- Move the item to its real status.
- Add acceptance evidence/commit reference.
- Add newly discovered dependency or risk.
- Keep planned ideas separate from implemented features.
- Update `CURRENT_STATE_LOCK.md`, `TEST_PLAN.md`, and `DECISIONS_LOG.md` in the same documentation closeout.
