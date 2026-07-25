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
F2/58L Establishment: 🟡 PARTIAL — Admin runtime acceptance ✅ PASS; duplicate-toggle fix ✅ PASS; same-state backend no-op (migration 20260813) ✅ PASS; fixture cleanup ✅ PASS; Staff runtime ⚪ NOT TESTABLE (no active staff); Employer full CRUD 🟡 pending
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

1. Active Staff test fixture + Staff runtime permission acceptance (currently NOT TESTABLE — 0 active staff; static contract: active staff may create/edit under role-not-null, toggle is Admin-only).
2. Employer full CRUD acceptance (create/update/permission-matrix/audit) — separate controlled stage.
3. Migration-history registration decision/evidence (deployment proven; history registration UNVERIFIED — SQL Editor run, no manual history row).
4. Establishment↔case model (`cases.establishment_id` absent → binding not implemented).
5. Establishment-owned document-link decision/stage (`owner_link_not_supported`, deferred).
6. Production plan and approval (not started).

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
1. F2/58L Establishment — PARTIAL: Admin runtime acceptance + duplicate-toggle hardening + same-state no-op + cleanup done on Staging (uncommitted)
2. F2/58L-CLOSE-2 — final exact diff / evidence review and commit preparation  ← immediate next action (review/commit-prep, not new implementation)
3. F2/58L remaining: Staff runtime (needs active staff fixture), Employer full CRUD, migration-history decision, establishment↔case + establishment-owned document decisions
4. Complete Phase 1 mobile/security/import-export/production-readiness gaps
5. Decide the open F1 follow-ups (create idempotency, proof-detach) if they become blocking
6. Run 2–3-user pilot → fix findings → roll out to 12 users
7. Continue Phase 2 checklist/profile/case-template expansion
8. Add document generation/OCR/portal later

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
