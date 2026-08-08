# RUNGFA CRM — DECISIONS LOG

> Durable product, architecture, safety, and workflow decisions. Use this to prevent a new chat/agent from reopening settled questions without new evidence.
>
> Dates reflect the known decision period; some decisions were formed across multiple sessions.

## Decision format

- **Decision** — what is settled.
- **Reason** — why.
- **Impact** — what future work must do.
- **Reopen when** — conditions that justify reconsideration.

---

## 2026-06 to 2026-07 — One central data foundation, modular workflows

**Decision:** Customer/worker/employer/document data remains in one shared foundation. Phase 2 case workflows are a separate module on top, not a separate disconnected database.

**Reason:** Staff should enter data once and reuse it across MOU, CI, Passport, Visa/WP, entering/leaving work, 90-day reporting, and other cases.

**Impact:** Avoid duplicating master data per case. Model relationships through cases, case workers, document ownership, and templates.

**Reopen when:** A legal/security requirement demands hard tenant/database isolation.

---

## 2026-06 to 2026-07 — Phase 2 is an internal preparation center, not a government portal

**Decision:** The product helps classify cases, legal basis, form code, required documents, readiness, and post-submission tracking. It does not claim to be e-WorkPermit and does not automatically submit applications by default.

**Reason:** Direct government submission involves authentication, OTP, payment, identity confirmation, changing workflows, and high operational risk.

**Impact:** Build strong preparation/checklist/tracking first. Keep human review and actual submission with staff.

**Reopen when:** Official integration/API, legal approval, security review, and controlled operational acceptance are available.

---

## 2026-06 to 2026-07 — Reduce repetitive disclaimers

**Decision:** Do not repeat “internal only / not a government form / not connected to government website” on every section and action. Keep one small help/info note where needed.

**Reason:** Repetition makes the system feel defensive and difficult, reducing staff adoption.

**Impact:** UX should emphasize clear work steps and readiness, not warnings.

**Reopen when:** Legal counsel requires specific placement.

---

## 2026-06 to 2026-07 — Staff adoption over backend jargon

**Decision:** User-facing Thai should be practical and easier than Excel. Technical English can appear in parentheses where useful.

**Reason:** The primary users are operational staff, not developers.

**Impact:** Use clear queues, compact status, missing-document explanations, and familiar business terms.

---

## 2026-06 to 2026-07 — Database stores metadata; Storage stores files

**Decision:** Actual files belong in private Storage. Database stores metadata, owner, status, expiry, and file reference/path.

**Reason:** Security, scalability, signed access, and avoiding base64/database bloat.

**Impact:** File opens use signed URLs/permission checks. Audit must not expose storage paths or signed URLs.

---

## 2026-06 to 2026-07 — One implementer per stage

**Decision:** Chat/Work controls direction; Claude Code or Codex is selected as the primary implementer for a stage. Do not let two coding agents edit the same branch simultaneously.

**Reason:** Prevent conflicting assumptions, file states, and partial changes.

**Impact:** A stage handoff must contain State Lock and exact next action before changing agent/machine.

---

## 2026-06 to 2026-07 — Staging first, Production separately approved

**Decision:** All new migrations, fixtures, smoke tests, and destructive tests run on Staging first. Production smoke/deploy is a separate stage and approval.

**Reason:** Protect real business data.

**Impact:** Staging HTML must have zero Production refs. Any Production ref during a Staging stage is a HARD STOP.

---

## 2026-06 to 2026-07 — Operator-assisted mutation model

**Decision:** For risky UI/data tests, Claude verifies and monitors; the user performs the real UI click or approved SQL action.

**Reason:** Keeps human control over mutations and avoids accidental agent actions.

**Impact:** Every action is pre-checked, performed once, then SELECT-verified. No silent retries.

---

## 2026-06 to 2026-07 — No commit/push/deploy without explicit approval

**Decision:** Passing tests does not authorize commit, push, merge, or deploy.

**Reason:** The user controls checkpoints and environment changes.

**Impact:** Agent proposes exact files, diff, tests, risks, and commit message, then stops.

---

## 2026-06 to 2026-07 — PDF+Excel helper / LINE batch is frozen

**Decision:** The completed helper is frozen during unrelated CRM/Phase 2 work.

**Reason:** It is already in real use; incidental changes create unnecessary regression risk.

**Impact:** Touch only under a dedicated approved stage.

---

## 2026-06 to 2026-07 — Use “LINE Messaging API”, not “LINE Notify”

**Decision:** All system documentation and prompts use the correct integration name.

**Reason:** The existing notification work uses LINE Messaging API; LINE Notify is a different/deprecated mechanism.

---

## 2026-07 — Attendance group notifications remain paused

**Decision:** Keep LINE group attendance notifications paused until a controlled quota/testing window.

**Reason:** Message quota and small-user testing concerns.

**Impact:** Attendance core must function without relying on group notifications.

**Reopen when:** New monthly quota/testing plan is approved.

---

## 2026-07 — Meta Ads remains local/manual CSV

**Decision:** Current Meta analytics is not a live API integration.

**Reason:** No token/security/data-sync stage has been approved.

**Impact:** Do not describe it as live data or add API credentials casually.

---

## 2026-07 — Staff deletion requires controlled approval

**Decision:** Staff should not freely delete business records; deletion should use request/approval with Admin control and audit.

**Reason:** Reduce accidental loss and misuse.

**Impact:** Security/role tests must confirm no unauthorized direct delete path.

---

## 2026-07 — Preserve user-facing zero glyph

**Decision:** Do not use fonts/classes that render digit 0 with a dot or slash in user-facing UI; preserve the existing zero-fix behavior.

**Reason:** The user explicitly requires normal readable zeros in CRM screens.

---

## 2026-07 — Owner-aware document attribution

**Decision:** Document linkage records explicit context through `linked_owner_type`, server-computed `linked_owner_id`, and `linked_case_worker_id` where relevant.

**Reason:** A case can contain primary/secondary workers, employer documents, case documents, and internal evidence. Attribution must not be guessed from document customer ID alone.

**Impact:** Supported verified paths include worker, case, employer, and internal. Server computes owner IDs and validates membership/ownership.

---

## 2026-07 — `received` is not `approved`

**Decision:** UI “ผ่าน” means `approved`, not `received`.

**Reason:** `received` means a document/status has been received or linked; it has not necessarily passed review.

**Impact:** Summary chips remain `missing`/`approved`/linked counts. Do not inflate “ผ่าน” using `received`.

---

## 2026-07 — Unlink does not automatically reset checklist status (G1)

**Decision:** Stage 58K-C recorded current behavior without changing it: unlink removes the link but leaves checklist status `received` until manual reset.

**Reason:** This was the deployed contract during the smoke test; changing it mid-test would mix product work with verification.

**Impact:** Treat as a product decision/gap. A dedicated stage must decide whether auto-revert is desirable.

**Reopen when:** Product owner chooses expected behavior and edge cases are specified (multiple links, manual statuses, approved items).

---

## 2026-07 — Reset to missing preserves check attribution (G2)

**Decision:** Current Option B behavior keeps `checked_by_code` and `checked_at` when status is reset to `missing`.

**Reason:** Backend code explicitly preserves these fields; Stage 58K-C verified it.

**Impact:** UI/report may show stale attribution. Do not silently clear fields until product decision.

---

## 2026-07 — Audit strictness remains asymmetric (G4)

**Decision:** Link/unlink audit is strict; checklist status update audit remains best-effort.

**Reason:** This is the deployed behavior and was outside the smoke-test fix scope.

**Impact:** Any consistency change needs a dedicated security/performance review.

---

## 2026-07 — T1–T13 canonical test mapping

**Decision:** Use the final matrix in `TEST_PLAN.md`; do not derive T numbers from seed document order or partial chat memory.

**Reason:** During the long session, early external-plan labels and seed order caused temporary numbering confusion.

**Impact:** New sessions must read the Test Plan before referencing T numbers.

---

## 2026-07 — T7 negative rejection does not require an unsafe direct write probe

**Decision:** UI visibility guard runtime evidence plus backend static contract was accepted for unrelated-document rejection.

**Reason:** The UI correctly cannot emit the unrelated document; forcing a direct write was unnecessary for the stage.

**Impact:** Classify honestly as UI-observed + backend static, not full live backend rejection.

---

## 2026-07 — T8 permission-layer failure is not a business-guard PASS

**Decision:** The SQL connector’s `42501 permission denied` occurred before the RPC function body and therefore did not prove `case_worker_inactive` live.

**Reason:** Security boundary blocked the call, but the intended business guard was not reached.

**Impact:** Record T8 as static/UI-unreachable with zero mutation, not a live guard PASS. Do not bypass grants or impersonate roles to force the test.

---

## 2026-07 — Payment proof is a separate payment-specific path (F1)

**Decision:** Do not force payment evidence through the normal checklist `app_link_case_document` selector.

**Reason:** Payment checklist rows are guidance-only; real flow uses `case_payments`, payment save RPC, and proof-document linkage.

**Impact:** Build a dedicated payment fixture/UI test stage.

---

## 2026-07 — Establishment link path is intentionally unsupported until 58L (F2)

**Decision:** `owner_type='establishment'` remains rejected by `owner_link_not_supported`; frontend stays placeholder/read-only.

**Reason:** An earlier check reported Staging lacking a `public.employer_establishments` table while some write RPCs were deployed, so the data model/schema was treated as needing reconciliation first. **Correction (2026-07-24):** the repository migration `20260804_employer_establishments.sql` actually defines the table as `public.establishments` (the filename differs from the table name); the earlier "table lacking" reading came from searching the wrong name. Live Staging deployment of `public.establishments` was not re-verified and must not be assumed present or absent until a read-only 58L pre-check. See the 2026-07-24 decision "Establishment migration filename differs from the actual table name."

**Impact:** Do not patch the selector or force an establishment link. Run Stage 58L separately.

---

## 2026-07-13 — Mandatory cleanup deletes only marker-scoped seed documents

**Decision:** Stage 58K-C cleanup deleted exactly the five `TEST_58K_SEED` documents and retained audit, cases, customers, employers, case workers, and checklist items.

**Reason:** Minimal cleanup was sufficient and safest. Synthetic entities may be reused by future payment/58L stages.

**Impact:** Optional soft-deactivation remains pending; do not assume synthetic entities are gone.

---

## 2026-07-13 — Audit retention during cleanup

**Decision:** Do not delete audit logs during routine fixture cleanup.

**Reason:** Audit is append-only evidence. Raw document cleanup did not create a cleanup audit row, and keeping count 131 was expected.

**Impact:** Future cleanup plans must distinguish test data deletion from audit retention policy.

---

## 2026-07-13 — Source-of-truth documentation pack before new chat

**Decision:** Move to a new ChatGPT Project using a compact repository-backed handoff pack instead of copying the entire old chat.

**Reason:** The long chat became slow and contained stale/intermediate states that could be mistaken for current truth.

**Impact:** New chat reads `PROJECT_MASTER_HANDOFF.md`, `CURRENT_STATE_LOCK.md`, `ROADMAP.md`, `TEST_PLAN.md`, `DECISIONS_LOG.md`, and `AGENTS.md` before proposing work.

---

## 2026-07-14 — The dedicated payment path is the accepted runtime path (F1)

**Decision:** Payment evidence is created and linked through `app_save_case_payment` and the dedicated payment-proof UI. This is now the verified, accepted runtime path.

**Reason:** F1 proved the full cycle on Staging: create, same-case proof link, update, and status change all worked through the payment-specific path with no schema or application-code change.

**Impact:** Future payment work builds on this path. `case_payments.proof_document_id` is the proof linkage; no `case_documents` row is produced by payment proof.

---

## 2026-07-14 — Payment proof must not be forced through the checklist selector (F1 confirmed)

**Decision:** The earlier F1 direction is confirmed by runtime evidence: payment proof must never be routed through the normal checklist `app_link_case_document` selector, and the payment checklist item remains guidance-only.

**Reason:** The dedicated path validates case-customer ownership server-side and keeps payment evidence out of the checklist link table. `case_documents` stayed 0 for the entire stage.

**Impact:** Do not add an `owner_type='payment'` path to the checklist selector. Do not create payment-owned `case_documents` rows.

---

## 2026-07-14 — Wrong-case evidence classification (F1)

**Decision:** Wrong-case proof protection is recorded as **UI runtime-observed plus backend static verification**, not a forced live negative write.

**Reason:** The picker filters to the case's own customer, so the unrelated document was never selectable; the deployed `document_not_allowed` ownership check was read from the live function definition. Forcing a negative write was unnecessary and would have been an unsafe deliberate probe.

**Impact:** Classify honestly. This follows the same precedent as the 58K-C T7 decision. Do not upgrade this to "live backend rejection" without a separately approved negative-path stage.

---

## 2026-07-14 — Omitting proof during update preserves the existing proof (F1)

**Decision:** Passing no proof argument (or null) to the payment save path **keeps** the current `proof_document_id`. This is the accepted deployed behavior.

**Reason:** Verified at runtime: the payment was updated with note-only changes and the proof link remained intact.

**Impact:** A caller cannot clear a proof by omitting it. Any future detach capability needs an explicit, separately designed workflow.

---

## 2026-07-14 — Cancellation preserves the proof and leaves paid_at null (F1)

**Decision:** A status transition to `cancelled` preserves `proof_document_id` and does not set `paid_at`.

**Reason:** Verified at runtime on the synthetic payment. `paid_at` is set only on transition to `paid`.

**Impact:** Cancellation is a soft status change, not a data-clearing operation. A cancelled synthetic payment must never be described as evidence of a real payment.

---

## 2026-07-14 — Payment audit remains best-effort; audit retained during cleanup (F1)

**Decision:** Payment audit stays best-effort under the current deployed contract, and payment audit rows are retained during fixture cleanup.

**Reason:** Audit is written inside the RPC body within an exception guard, so an audit failure does not fail the payment transaction. Audit is append-only evidence.

**Impact:** Rows 204–207 (`create`, `proof_link`, `update`, `cancel`) were retained; the Staging audit baseline moved from 131 to 135 (ids 73–207). Do not delete audit during routine cleanup. Any move to strict payment audit needs a dedicated review alongside G4.

---

## 2026-07-14 — F1 cleanup scope (F1)

**Decision:** F1 cleanup deleted only payment id 1 and documents 11 and 12.

**Reason:** Minimal marker-and-ID-scoped cleanup is the safest pattern, consistent with the 58K-C cleanup precedent.

**Impact:** No customer, employer, case, worker, checklist, user, or audit row was deleted. Synthetic entities (customers 1–4, employers 1–2, cases 1–2) remain and may be reused by a future stage. Baseline restored: `case_payments` 0, documents 0, `case_documents` 0, audit 135.

---

## 2026-07-24 — Live HEAD is read from Git, not frozen in documentation

**Decision:** The current live HEAD is obtained from Git pre-flight (`git rev-parse HEAD`) every session. A commit hash written in any of the six documents is historical stage evidence or a dated snapshot, never an assertion of the permanent live HEAD.

**Reason:** The prior pattern stored a "current HEAD" value in Markdown. Because the commit that records the value cannot contain its own future hash, the wording went stale immediately after every documentation commit (self-staling), forcing repeated HARD STOPs.

**Impact:** Documents distinguish four roles — live HEAD (from Git), Stage test-evidence commit, documentation-closeout commit, and dated verified snapshot. Never create a commit solely to make a stored "current HEAD" field equal the commit being created.

**Reopen when:** Never, unless a tooling change makes live Git HEAD unavailable at pre-flight.

---

## 2026-07-24 — A newer documentation-only commit is not automatically a Stage contradiction

**Decision:** A live HEAD newer than the stored snapshot is a HARD STOP only when the newer commit(s) or working-tree state introduce a meaningful, unexplained difference — application code, schema/migration, HTML, configuration, environment, or an unrecorded Stage-status change. A documentation-only commit newer than the snapshot does not invalidate recorded Stage evidence.

**Reason:** Distinguishes real drift from harmless snapshot aging.

**Impact:** Pre-flight compares substance, not just hash equality. Reconcile snapshot wording in a documentation pass rather than chasing SHAs.

---

## 2026-07-24 — Establishment migration filename differs from the actual table name

**Decision:** The migration `20260804_employer_establishments.sql` defines the table `public.establishments`. The filename `employer_establishments` must not be mistaken for the table name.

**Reason:** An earlier check searched for `public.employer_establishments`, did not find it, and wrongly concluded "the table is absent." Repository evidence shows the table plus RPCs `app_save_establishment`/`app_set_establishment_active` and a frontend modal.

**Impact:** Do not state the table is absent based on the wrong name, and do not state it is deployed. Repository migration evidence does not prove live Staging deployment; live Staging schema was not re-verified. F2/58L remains not started and must reconcile repository definitions against live Staging read-only before any schema change. The unsupported establishment-owned checklist-link behavior (`owner_link_not_supported`) is preserved until a dedicated approved decision.

**Update (2026-07-25):** The stated F2/58L pre-check and reconciliation condition has now been satisfied, followed by Establishment Admin Runtime Acceptance on Staging. `public.establishments` is confirmed as the deployed canonical table. Current status is **F2/58L PARTIAL**; Staff Runtime and Employer CRUD remain pending. See the 2026-07-25 decisions for the canonical current status.

**Reopen when:** A read-only 58L pre-check establishes the live Staging schema.

---

## 2026-07-24 — Repository foundation is not proof of deployment or runtime acceptance

**Decision:** Across the documents, "repository implementation exists" is kept separate from "deployed on Staging" and from "runtime acceptance verified." A migration file does not prove deployment; UI code does not prove a runtime flow passed.

**Reason:** The Recovery Inventory found several Phase 2 systems (appointments, government/e-WorkPermit tracking, case status history, contact timeline) with repository foundations but no runtime acceptance evidence, and no database was queried.

**Impact:** These are recorded as repository foundations with runtime acceptance not found and deployed state not checked. Each requires its own approved test stage. None may be described as Runtime PASS, Staging ready, or Production ready. F1 remains closed; its cleanup database values remain documented historical evidence, not re-verified in this pass. 58K-C T7/T8 and F1 wrong-case classifications are unchanged (UI-observed + backend static; permission-blocked, not a live business-guard PASS). Production remains untouched and Production smoke remains not started.

**Reopen when:** A dedicated approved stage records runtime acceptance for a given system.

---

## 2026-07-24 — SYSTEM_STATUS_MASTER.md remains cancelled; handoffs are evidence, not Source of Truth

**Decision:** `SYSTEM_STATUS_MASTER.md` stays cancelled and absent from the working tree, tracked files, and Git history; it must not be recreated without explicit owner approval. The six existing files remain the only repository Source-of-Truth documents. `docs/handoffs/` is a historical archive only, and any external chat handoff (e.g. `RUNGFA_CRM_CHAT_HANDOFF_2026-07-23.md`) is historical evidence outside the repository, not current state. ChatGPT Project Sources are copies and may become stale.

**Reason:** The seventh-file attempt duplicated `PROJECT_MASTER_HANDOFF.md`, expanded the Source-of-Truth set unnecessarily, and stalled real work before being restored cleanly. Current facts come from live Git and correctly identified live environments.

**Impact:** Do not add a seventh Source-of-Truth file. `ai_autopost_system.html` is recorded as an unresolved inventory item: a standalone tracked repository file that is not currently classified as Core CRM, with its operational use, ownership, testing status, and future scope unconfirmed. Its final classification remains pending the owner's decision, and it is not currently an approved Core CRM product.

**Reopen when:** The owner explicitly approves a new document or a classification for `ai_autopost_system.html`.

---

## 2026-07-25 — Canonical Establishment table is public.establishments (F2/58L)

**Decision:** `public.establishments` is the canonical current Establishment table, confirmed deployed on Staging. `public.employer_establishments` is **not** the deployed canonical table (it is only the migration filename `20260804_employer_establishments.sql`).

**Reason:** Operator-assisted Staging runtime + SELECT-only verification confirmed the deployed table, RPCs, and UI. An earlier "table absent" reading came from searching the wrong name.

**Impact:** Future code/docs/tests must reference `public.establishments` unless a separately approved migration changes the model. Supersedes the earlier "table absent / deployment not re-verified" wording.

---

## 2026-07-25 — Establishment active-toggle duplicate defense at both layers (F2/58L)

**Decision:** Protect the Establishment active toggle at both layers: frontend per-establishment in-flight guard + button disable (guard acquired before `guardSession()`, before the first await, and before `confirm()`); backend `app_set_establishment_active` same-state no-op (migration `20260813`) that performs no UPDATE, no `updated_at`/`updated_by_code` change, and no audit when requested state equals current state, while a real change performs exactly one UPDATE and one audit.

**Reason:** One intended inactive→active flow previously produced two confirmation dialogs and two `set_active` audit rows. Confirmed defects: frontend lacked duplicate/in-flight protection; backend was not audit-idempotent for same-state. The exact second-invocation trigger was **not fully reproduced** — no fully proven event-binding root cause is claimed.

**Impact:** Real state changes create exactly one audit; same-state calls return success without audit noise. Backend defense is defense-in-depth and does not replace the frontend guard. Admin-only toggle and create/edit behavior are unchanged.

---

## 2026-07-25 — F2/58L Establishment Admin acceptance PASS; overall PARTIAL

**Decision:** Establishment Admin Runtime Acceptance is **PASS** on Staging (create/edit/reload/toggle + audit/privacy + fixture cleanup, and post-fix regression + same-state no-op). F2/58L **overall remains PARTIAL**.

**Reason:** No active Staff fixture exists (0 active staff → Staff runtime NOT TESTABLE, recorded as neither PASS nor FAIL), and full Employer CRUD acceptance was not completed. Establishment↔case binding is not implemented (`cases.establishment_id` absent) and establishment-owned document linking remains unsupported (`owner_link_not_supported`).

**Impact:** Do not report Employer/Establishment as fully complete or F2/58L as fully closed. Staff runtime and Employer full CRUD require separately approved continuation stages.

---

## 2026-07-25 — Establishment fixture cleanup and audit retention (F2/58L)

**Decision:** The synthetic Establishment fixture (`ZZ_TEST_58L_EST_20260724_A`, id=1) is deleted after testing (establishments under employer id=2 back to 0; employer/worker fixtures retained). Audit remains append-only and retained, including the two historical pre-fix duplicate `set_active` rows.

**Reason:** Marker-scoped cleanup is the safest pattern (consistent with 58K-C/F1); audit is evidence and must not be deleted during routine cleanup.

**Impact:** The two pre-fix duplicate audit rows are retained historical evidence, not an active failure after the fix. Establishment table has no hard-delete RPC (soft active/inactive only), so row removal used an approved marker-scoped delete, not the app UI.

---

## 2026-07-25 — Migration 20260813 deployed via SQL Editor; history registration unverified

**Decision:** Migration `20260813_establishment_set_active_same_state_noop.sql` was applied once through the confirmed Staging SQL Editor ("Success. No rows returned"). Function deployment is proven; **migration-history registration is UNVERIFIED** (run through SQL Editor, no manual `supabase_migrations` row added).

**Reason:** SQL-Editor application does not register migration history automatically, and no manual history row was written.

**Impact:** Record honestly as an unresolved traceability point, not a failed migration. Do not manually write to migration-history tables. Reconcile deployment evidence later; do not convert into a separate migration-history repair stage.

---

## 2026-07-25 — Identity/session hardening remains parked during F2/58L acceptance

**Decision:** System-wide identity/session hardening (IDENT-1, opaque server-side session token) remains a **separate parked design backlog**. It was not required to block controlled operator-assisted Establishment Staging acceptance, and no IDENT-1 implementation occurred.

**Reason:** The frontend-asserted identity model is the same one under which 58K-C and F1 were accepted; a controlled Admin operator-assisted test on Staging does not worsen that systemic risk.

**Impact:** IDENT-1 is not the active next stage. It stays on record as designed-but-parked; opening it is a separate owner decision.

---

## 2026-07-26 — Employer CRUD acceptance is scoped to the Admin create/read/edit path

**Decision:** Employer Admin Runtime Acceptance is **PASS** on Staging (create → read → full-page reload persistence → single low-risk field edit → server audit + privacy → relationship invariants → exact fixture cleanup → baseline restoration). The accepted scope is deliberately **Admin create/read/edit only**. Employer **delete** and Employer **active/inactive** are confirmed **not implemented** in the current contract and are explicitly **out of scope**, not failures. Employer **Staff** runtime remains **NOT TESTABLE** (0 active Staff) and is recorded as neither PASS nor FAIL.

**Reason:** The repository contract has no employer delete RPC, no UI delete control, and no active/inactive or soft-delete column on `employers`; the establishments FK is intentionally non-cascading. Testing a capability that does not exist would produce a false FAIL. No active Staff fixture exists, matching the same limitation already recorded for F2/58L.

**Impact:** Do not report the Employer workstream as complete, and do not report F2/58L as closed — F2/58L overall remains PARTIAL. Adding employer delete or active/inactive requires its own product decision and a dedicated stage, including how it interacts with the delete-request/approval workflow and the non-cascading establishments FK. Full evidence: `TEST_PLAN.md` section 8d.

---

## 2026-07-26 — Employer duplicate prevention recorded as a gap, not fixed during acceptance

**Decision:** The Employer duplicate-prevention gap (**E1**) is recorded and carried forward, **not fixed** during the acceptance stage. The current contract **does not guarantee duplicate prevention**: no database uniqueness guarantee on `public.employers` and no proven double-submit guard on the Employer save path were established. The operator submitted once only; **duplicate creation was not runtime-tested in this stage** and duplicate-click was deliberately excluded.

**Reason:** Testing-principle 8 forbids fixing a product gap during a smoke test unless that gap is the explicit stage objective. The stage objective was acceptance of the existing contract, and a uniqueness or in-flight-guard change would alter application code and schema mid-acceptance.

**Impact:** Because neither safeguard was established, duplicate Employer records **may occur** — including through the indirect creation paths (new customer with a typed company name, and Excel import) — but this was **not runtime-tested in this stage**, so no observed-duplicate claim is made. Decide before multi-user rollout whether to add a database uniqueness rule, a frontend in-flight/disable guard (the pattern already applied to the establishment toggle), or both. Until then, treat employer duplicates as an unverified operational risk, not an accepted design.

---

## 2026-08-05 — LINE PDF-to-images dual mode approved at design level only

**Decision:** A dedicated **LINE PDF-to-images dual-mode** stage is approved **at design level only** (`LINE-PDF-DUAL-MODE-DESIGN` = DESIGN PASS). The target is the **same existing operational LINE group**, subject to implementation pre-check evidence. **Saving Mode is the default.** **Auto Mode is controlled by database-backed admin authority with original-group binding.** An **external Cloud Run converter worker** is selected for the MVP design **over in-Edge WASM rasterisation**. **One active PDF delivery stream per group.** The **first range of up to five page images uses Reply**; **remaining Auto ranges use Push**. **Reply ambiguity requires explicit user resolution.** **Push retry keys are time-bounded 24-hour retry episodes**, and **Push retries reuse the exact persisted original payload**; **ambiguity surviving the retry window requires an explicit human decision**. **Retry keys, signed URLs, payload snapshots, lane tokens, secrets, and raw LINE IDs must not appear in audit, logs, reports, screenshots, or handoff documents.** **Cross-group routing is out of scope.** **Production implementation and deployment remain separately gated.**

**Reason:** Supabase Edge runtime limits, WASM packaging constraints, and unproven PDF rasterisation performance make in-Edge rasterisation unsuitable for the approved MVP without a separate feasibility proof. Reply messages are not counted toward the monthly message count while Push messages are counted per recipient, so a Saving-Mode default with an admin-gated Auto Mode is the quota-safe posture, consistent with the standing decision to keep LINE group notifications paused pending a quota plan. A single group transcript makes interleaved page streams from two documents a real, user-visible defect, so one delivery stream per group is required. Reply has no platform-level retry-key idempotency while Push does, so the two ambiguity cases cannot share one recovery rule. `AGENTS.md` sections 6 and 10 forbid tokens, signed URLs, and credentials in audit details, reports, and handoff documents.

**Impact:** Implementation **remains blocked** until this documentation correction is verified, owner-approved, committed, and pushed. GCP resources, migrations, Edge Functions, router integration, Staging runtime selection, any Auto-Mode quota window, and Production each remain **separately gated**. The existing PDF+Excel helper **remains frozen**; any adjacent router integration requires a separate implementation pre-check and its own approval. This documentation stage queried no environment; the implementation and Staging runtime target must be selected and re-verified in that separate pre-check. Production implementation and deployment remain unapproved and untouched by this stage.

**Reopen when:** LINE platform limits or pricing behaviour change materially; the owner declines external converter hosting; or a runtime proof of concept invalidates a stated design assumption.

---

## 2026-08-05 — Branch A: decouple the Production asset dependency before any Staging restore

**Decision:** The owner selected **Branch A** — the existing frozen PDF+Excel helper will be preserved and later restored on Staging, but only after every Production asset reference is removed from its deployment source under a **dedicated approved frozen-helper stage**. Deploying unchanged while accepting the Production asset dependency **is not an allowed option and must not be reoffered**. Branch A is **not** code-change approval, **not** deployment approval, and **not** Production approval.

Settled by this decision:

1. **A Production project reference inside the exact Staging deployment source is a deployment blocker.** `line-ai-excel-helper` remains **BLOCKED FROM DEPLOYMENT** with four such references, and `line-ai-excel-finalize-due` remains **BLOCKED FROM DEPLOYMENT** with three.
2. **Staging uses its own `line-assets` bucket.**
3. **The bucket's purpose is limited to non-sensitive static UI icons** used by LINE Flex messages. It is not approved for customer, worker, employer, or company documents, generated PDFs or Excel files, batch images, OCR inputs or outputs, Doc Inbox files, credentials, or any private business data.
4. **Bucket contract:** `public = true`, `file_size_limit = 2097152`, `allowed_mime_types = [image/png]`. Changing any of these requires its own approval.
5. **Public write is not approved.** No `line-assets`-specific Storage policy existed at AP-4, and **public object retrieval is untested**.
6. **The owner-assisted two-file Production export was a one-time controlled read-only source-recovery action**, separately approved. **Production was not mutated** — no connector query, deployment, or schema/data/Storage/policy/configuration change. It establishes no general permission to read Production, and Production must not be described as untouched throughout this workstream.
7. **The final asset URL construction method remains UNRESOLVED.**
8. The existing helper remains **FROZEN**, and LINE PDF-to-images remains **DESIGN PASS — IMPLEMENTATION NOT STARTED**.

**Reason:** Environment separation and Production protection require that a Staging deployment artifact not carry a Production project reference. Such references would make Staging runtime clients depend on Production Storage, which is not an acceptable Staging posture. The frozen-helper boundary means the asset correction cannot ride along inside a restoration or deployment Gate and needs its own approved stage. A Staging-local, non-sensitive static-icon foundation is therefore required before any restore.

**Impact:** Every icon upload, the asset-decoupling code edit, static verification, each Edge Function deployment, webhook activation, every runtime test, the documentation commit, and the push each remain **separately approved**. Full evidence: `TEST_PLAN.md` section 8f.

**Reopen when:** The owner changes Branch A, or later evidence makes the bucket contract or the URL-construction decision obsolete.

---

## 2026-08-07 — The Staging PDF icon keeps its doubled-extension object name

**Decision:** The first object in the Staging `line-assets` bucket is permanently named **`ChatGPT Image Jun 3, 2026, 02_52_40 PM.png.png`**. The owner explicitly **accepted the doubled `.png` extension** as the permanent object name. **No rename, delete, replacement, or re-upload is required or approved.** Any future change to this object name is a separate owner-approved Storage mutation, and any code that references the icon must use this exact stored name.

**Reason:** The owner uploaded the approved local source asset through the Supabase Dashboard on 2026-08-06 while Windows Explorer was hiding file extensions, so a second `.png` was appended to the intended name `ChatGPT Image Jun 3, 2026, 02_52_40 PM.png`. Read-only verification on 2026-08-07 proved the object is otherwise exactly as approved — `image/png`, 734,889 bytes, one object in the bucket, bucket contract unchanged (`public = true`, `file_size_limit = 2097152`, `allowed_mime_types = [image/png]`). Renaming would require an extra Storage mutation on a correct object for cosmetic reasons only, which is a worse risk trade than accepting the name.

**Impact:** The accepted name becomes part of the asset contract recorded in `CURRENT_STATE_LOCK.md` and `TEST_PLAN.md` section 8g. The still-unresolved asset URL construction strategy (pending decision 13) must be resolved **against this exact name**. Nothing else changes: the Excel icon remains **NOT UPLOADED**, public object retrieval and LINE image rendering remain **UNTESTED**, `line-ai-excel-helper` and `line-ai-excel-finalize-due` remain **BLOCKED FROM DEPLOYMENT**, no asset-decoupling code edit has been performed, the existing PDF+Excel helper remains **FROZEN**, and LINE PDF-to-images remains **DESIGN PASS — IMPLEMENTATION NOT STARTED**. Production was not accessed during the upload or either verification stage. Storage metadata exposes no checksum, so the stored object is verified by size and MIME only — **not** by SHA-256 byte identity.

**Reopen when:** The Excel icon or a later asset makes a consistent naming convention across `line-assets` objects necessary, or the chosen URL-construction method cannot handle the doubled extension.

---

## Pending decisions

These are not settled and require user approval:

1. Whether payment creation needs idempotency protection, and what form it should take.
2. Whether a dedicated proof-detach workflow is required, given that omitting proof preserves the existing value.
3. Whether G1 unlink should auto-reset status, and how multiple links/approved statuses behave.
4. Whether G2 should clear check attribution when resetting to missing.
5. Whether checklist update audit should become strict, and whether payment audit should follow.
6. Whether/when to soft-deactivate retained synthetic entities.
7. Exact Production smoke subset and deployment schedule.
8. Exact user-facing final name for the Phase 2 module.
9. When to re-enable LINE attendance notifications.
10. Whether Employer duplicate prevention (E1) needs a database uniqueness rule, a frontend double-submit guard, or both.
11. Whether Employer delete (E2) should exist at all, and if so whether it routes through the delete-request/approval workflow given the non-cascading establishments FK.
12. Whether Employer active/inactive (E3) is needed for employers who stop trading, and how it should interact with linked workers and cases.
13. The final asset URL construction method for the frozen helper Flex-card icons is UNRESOLVED and requires a separately approved stage.

The earlier pending item "whether F1 Payment Stage or F2/58L Establishment Stage comes first" is resolved and removed: F1 is complete, and F2/58L remains the outstanding technical gate.
