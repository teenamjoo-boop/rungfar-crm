# RUNGFA CRM — AGENT OPERATING RULES

> Repository-level instructions for ChatGPT Work, Claude Code, Codex, or any coding agent working on RUNGFA CRM.
>
> Last documentation snapshot: 2026-08-10 (N8N-001A-DOC-SYNC — Automation Integration Foundation READ-ONLY V1 accepted on Staging). Prior snapshots: 2026-08-05 (LINE-PDF-DOC-CONSISTENCY-CORRECTION); 2026-07-26 (Employer CRUD Admin runtime acceptance) and 2026-07-22 (F1 documentation closeout); the F1 Payment-specific Stage itself closed on Staging 2026-07-14. These are dated documentation snapshots, not a live-HEAD assertion. These rules are persistent, but all Git/DB facts must be re-verified at the start of every session.

## 1. Mission and role split

RUNGFA CRM is an internal business system for managing customers, migrant workers, employers, documents, attendance, alerts, and labor-document cases. It is evolving into a practical **work-preparation center before staff submit real applications to government systems**, especially e-WorkPermit.

Role boundaries:

- **Chat / Work**: analyze, plan, review reports, define stage scope, write prompts, update source-of-truth documents.
- **Claude Code or Codex**: inspect the repository, edit code, run tests, inspect Git, prepare migrations, and produce Expected-vs-Actual reports.
- **User/operator**: approve scope, perform UI clicks that mutate data when operator-assisted, run explicitly approved SQL in the correct Supabase environment, approve commit/push/deploy.

Use one primary coding agent per stage. Do not let Claude Code and Codex edit the same branch concurrently.

## 2. Source-of-truth precedence

When facts conflict, use this order:

1. Current repository files and Git state.
2. Current Staging/Production database state, checked through the correct connector or SQL Editor.
3. `CURRENT_STATE_LOCK.md`.
4. `PROJECT_MASTER_HANDOFF.md`.
5. `TEST_PLAN.md`, `ROADMAP.md`, and `DECISIONS_LOG.md`.
6. Chat history or agent memory.

Never guess a stage number, database baseline, test fixture, function signature, or file path from memory. If the current state differs from the lock, **HARD STOP** and report Expected vs Actual before doing any write.

## 3. Mandatory environment facts

- Correct Windows repository path: `D:\dev\claude`
- Correct Git Bash path: `/d/dev/claude`
- Forbidden old path: `C:\Users\Acer\OneDrive\Desktop\claude`
- Current working branch at handoff: `feature-attendance`
- **Current live HEAD: always read from Git pre-flight (`git rev-parse HEAD`). Do not treat any hash stored in this file as the permanent live HEAD.** The commit hashes below are historical stage evidence and dated snapshots, not a live-HEAD assertion:
  - F1 runtime-test HEAD (historical): `e9d035c` — the commit at which the F1 payment runtime test was executed on 2026-07-14
  - F1 documentation-closeout commit (historical): `bf40820` — recorded the F1 stage into the six documents, pushed 2026-07-22
  - Employer CRUD acceptance documentation commit (historical): `4c8b45e` — recorded the Employer Admin runtime acceptance into five of the six documents, 2026-07-26
  - Earlier verified repository snapshots (historical): `fbcf624` — verified `local = origin`, `0 ahead / 0 behind`, working tree clean on 2026-07-26; `2c30070` — same verification on 2026-07-23
  - Prior code-baseline HEAD (historical, Stage 58K-C): `54680ec`
- Main frontend: `rungfar_crm_17.html`
- Local Staging frontend: `rungfar_crm_17.STAGING.local.html`
- Staging project ref: `bzwtknqvhvdmatangzqf`
- Production project ref: `magwqolbjmwymqxelizl`

The HEAD and working tree can change after this handoff. Re-check them every session. Project refs must never be swapped.

## 4. Mandatory pre-flight before any work

Run from the correct path:

```bash
cd /d/dev/claude
git status --short --branch
git diff --check
git log --oneline --decorate -10
```

Then verify:

- Current branch and HEAD.
- Whether the working tree is clean or contains intentional changes.
- Which files are modified and why.
- The target environment is Staging or Production.
- The local Staging HTML contains the Staging ref and contains **zero** Production refs.
- The requested stage exists in `ROADMAP.md`/`TEST_PLAN.md`, or the user has explicitly defined a new stage.
- `CURRENT_STATE_LOCK.md` matches the live repository/DB facts relevant to the task.

**Live-HEAD vs stored snapshot:** obtain the current HEAD from Git, not from any stored Markdown value. A stored hash is stage evidence or a dated snapshot. A live HEAD that is newer than the stored snapshot is **not by itself** a HARD STOP — it is a HARD STOP only when the newer commit(s) or the working-tree state introduce a meaningful, unexplained difference (application code, schema/migration, HTML, configuration, environment, or a Stage-status change the documents do not record). A documentation-only commit that is newer than the snapshot does not invalidate recorded Stage evidence; reconcile the snapshot wording in a documentation pass — never create a commit solely to make a stored "current HEAD" field equal the commit being created.

Do not ask the user to run `git status` again when a complete pre-flight result was already supplied in the current turn, unless state may have changed or a commit is about to be made.

## 5. Default safety mode

Default mode is **READ-ONLY REVIEW**.

Without explicit user approval, do not:

- Edit files.
- Execute a write RPC.
- Insert, update, delete, seed, cleanup, or change fixtures.
- Run migrations against Staging or Production.
- Commit, push, merge, deploy, or switch branches.
- Change permissions, grants, RLS, roles, secrets, or environment refs.
- Touch Production.

A read-only connector must not be treated as a write-capable connector. If a write is required, prepare the exact scoped command/SQL and have the user run it through the approved environment, then perform read-only verification.

## 6. Production protection

Production is protected by default.

- Never point a Staging local file to Production.
- Never run a Staging seed/fixture against Production.
- Never run a Production smoke test until Staging is complete and the user explicitly approves a separate Production plan.
- Never deploy or push merely because a test passed.
- Never store service-role keys, API keys, tokens, passwords, signed URLs, or credentials in source files, audit details, reports, screenshots, or handoff documents.
- Any unexpected Production ref in a Staging file or command is an immediate **HARD STOP**.

**Standing Supabase CLI hazard (verified 2026-08-10).** `supabase/.temp/linked-project.json` links this working copy to **Production** (`magwqolbjmwymqxelizl`, "rungfar-crm"). It is gitignored, so it never travels with a commit, but it governs every local CLI invocation. Any command that resolves linked state without an explicit `--project-ref` — `db push`, `db pull`, `functions deploy`, `secrets set`, `db dump`, including `--dry-run` — **targets Production**. Always pass `--project-ref bzwtknqvhvdmatangzqf` explicitly, or prefer the Dashboard.

Additionally, **`supabase db push` must not be run in this repository at all.** Staging has **no `supabase_migrations` schema**, so the CLI would treat all 64 local migrations as pending and replay them against a fully-built database; the migration filenames also use 8-digit prefixes with 7 duplicate versions, which cannot coexist in the registry's primary key. Migration-history reconciliation is a separate future ticket. Similarly, `supabase functions deploy` **without a function name deploys all 12 functions**, including `line-ai-excel-helper` (4 Production asset refs) and `line-ai-excel-finalize-due` (3), both **BLOCKED FROM DEPLOYMENT**. Always name the function explicitly.

## 7. Stage execution protocol

Every technical stage must follow this sequence:

1. **Scope lock** — restate objective, in-scope files/tables/functions, out-of-scope areas, environment, and stop conditions.
2. **Pre-flight** — Git, environment, DB baseline, fixture identity, function signature, and current UI path.
3. **Read-only contract review** — frontend payload, backend validation, ownership checks, audit behavior, expected counts.
4. **Operator approval** — stop before the first mutation.
5. **Single mutation/action** — user clicks UI or runs one approved SQL/RPC action; agent monitors only when requested.
6. **Post-action read-only verification** — query exact rows, counts, audit entry, privacy scan, and invariants.
7. **Cleanup/restore** — only when explicitly in stage scope; verify baseline afterward.
8. **Stage verdict** — PASS, PARTIAL, BLOCKED, or HARD STOP with evidence.
9. **Documentation update** — update State Lock, Test Plan, Decisions Log, and Roadmap when applicable.
10. **Commit gate** — only after the user reviews and explicitly approves.

Never combine unrelated bug fixes, cleanup, schema work, and UX changes in one smoke-test stage.

## 8. Mutation and SQL rules

Before any write:

- Name the target environment and project ref.
- Show exact tables/functions and row scope.
- Show preconditions, expected row count, transaction/rollback behavior, and postconditions.
- Use allowlists and marker-scoped data for cleanup.
- Prefer transaction-protected, idempotent operations.
- Never use broad `DELETE`, destructive raw cleanup of customers/employers/cases/workers, or blanket audit deletion.
- Never silently retry with a different method after an error.
- If the result differs from expected, stop and report; do not improvise.

For Supabase SQL run by the user:

- Confirm the Dashboard project is Staging before Run.
- Run once.
- On `ABORT`/`ERROR`, stop and do not rerun until reviewed.
- After success, perform a separate read-only post-verification.

## 9. Commit, push, and deploy rules

Do not commit, push, merge, or deploy without explicit user approval.

Before proposing a commit:

```bash
git status --short --branch
git diff --check
git diff --stat
git diff -- <exact-files>
```

Report:

- Files changed.
- Why each changed.
- Tests run and results.
- Remaining risks/gaps.
- Suggested commit message.

After user approval, commit only the approved files. Push only after separate approval. Deploy only after a separate deployment plan and approval.

## 10. Database, RPC, RLS, and audit rules

- Treat deployed SQL/RPC signatures as live contracts; inspect the actual function definition before calling.
- Use `SECURITY DEFINER` only with explicit server-side identity/role/ownership validation and restricted execute grants.
- Frontend-supplied identity is not trusted by itself; server must validate active user and role.
- Maintain owner-aware document attribution for `worker`, `case`, `employer`, and `internal` paths.
- Payment and establishment paths have separate decisions and must not be forced through the normal checklist document selector.
- Link/unlink audit is strict where designed; checklist update audit is currently best-effort. Do not change this during unrelated work.
- Audit is append-only and retained. Routine cleanup must not delete audit logs.
- Audit/report detail must not contain storage path, bucket, file data, base64, signed/public URL, token, secret, password, API key, authorization header, service-role key, or PII not needed for the audit purpose.

### Connector target proof before any database query

Before any connector-based database query, the agent must positively identify the target as Staging. Acceptable proof:

1. The tool explicitly exposes the project ref and it equals `bzwtknqvhvdmatangzqf`, or
2. A SELECT-only environment fingerprint proves the known Staging synthetic markers and also proves that the Production baseline would not match.

Not acceptable as proof: prompt text alone; assuming the connector follows the current repository; assuming a connector named "Supabase" is Staging; a local HTML URL alone.

If the target cannot be positively identified, skip the database query and report: "Documented but not re-verified in this review."

## 11. Product invariants

Protect these unless a specifically approved stage changes them:

- Original customer/worker/employer/case data must not be altered by synthetic tests.
- Staff should not directly delete business data; use request/approval workflow where implemented/planned.
- Database stores file metadata and references; Storage stores actual files.
- A document selected for a case must match the intended owner/context.
- Checklist totals and case-worker membership must remain consistent after document link/unlink tests.
- New customer records should remain ordered in the business-approved order.
- Employer grouping and Excel-compatible data behavior must be preserved.
- User-facing digit `0` must not use a dotted/slashed-zero font or class. Preserve the existing zero-fix behavior.

## 12. UI/UX rules

- Use Thai business language that staff understand; English terms may appear in parentheses when helpful.
- The system should feel easier than Excel, not like a government portal.
- Avoid repeating heavy disclaimers such as “internal only / not government form / not connected to government website” across every section. Keep one small help/info note where necessary.
- Keep work queues, statuses, actions, and missing-document indicators compact and clear.
- Preserve the company’s light blue/white/orange visual direction unless a specific design stage says otherwise.
- Test desktop and mobile scrolling/modal behavior when touching shared layout code.

## 13. Frozen or deferred areas

Do not touch without explicit scope:

- Existing PDF+Excel helper / LINE batch flow — completed and **frozen from unrelated work**. It stays frozen; only a dedicated approved stage may touch it.
- LINE PDF-to-images dual mode (`LINE-PDF-DUAL-MODE-DESIGN`) — **DESIGN PASS** as a dedicated owner-approved design stage. **Implementation has not started and is not approved.** Any router-adjacent or helper-adjacent change requires a separate implementation pre-check and its own approval.
- Attendance LINE group notification — temporarily paused due to quota/testing policy.
- Meta Ads live API — not implemented; current page is local/manual CSV only.
- Production/Netlify deployment — deferred until explicit approval.
- Decorative animated/pixel-office dashboard — deferred until CRM core is finished.
- Product gaps G1–G4 — record them; do not fix during unrelated smoke tests.

## 14. Terminology

- Use **LINE Messaging API**, not LINE Notify.
- User-facing Phase 2 name should be a practical term such as “งานเอกสารแรงงาน”, “เคสเอกสารแรงงาน”, or “ศูนย์งานเอกสารแรงงาน”; “Phase 2 case” is only a development label.
- `received` means received/available in DB. It is **not** the same as `approved`/“ผ่าน”.
- UI summary chips at the verified handoff use:
  - “ขาด” = `missing`
  - “ผ่าน” = `approved`
  - “ลิงก์” = linked documents
  - `received` is a separate DB status and does not automatically count as “ผ่าน”.

## 15. Known gaps that must not be silently changed

- G1: unlink does not auto-revert checklist `received → missing`.
- G2: manual reset to `missing` keeps old `checked_by_code`/`checked_at`.
- G3: UI chip semantics separate `approved`, `missing`, and linked documents; `received` has no dedicated top chip.
- G4: checklist update audit is best-effort while link/unlink audit is strict.
- F1: **CLOSED on Staging 2026-07-14.** Payment proof uses the dedicated payment path (`app_save_case_payment`), not the normal checklist selector; the payment checklist item stays guidance-only. Three F1 follow-ups remain open and must not be silently changed (they are not part of the completed F1 runtime stage): F1a payment create has no demonstrated idempotency protection; F1b no proof-detach workflow exists or was tested; F1c payment audit remains best-effort.
- F2/58L: Establishment reconciliation is **PARTIAL** — not closed. `public.establishments` was **confirmed deployed on Staging** during the completed stage (migration `20260804_employer_establishments.sql` defines the table; note the filename differs from the table name), with RPCs `app_save_establishment`/`app_set_establishment_active` and a frontend modal. **Establishment Admin runtime acceptance = PASS** (create/read/reload/edit/toggle + audit/privacy + fixture cleanup, plus the duplicate-toggle fix and the same-state no-op migration `20260813`). Still open: **Staff runtime NOT TESTABLE** (0 active Staff), **migration-history registration UNVERIFIED**, establishment↔case binding not implemented (`cases.establishment_id` absent), and establishment-owned document linking unsupported/deferred (`owner_link_not_supported`). Do not report F2/58L as closed. Historical note: an earlier check searched the wrong name `public.employer_establishments` and wrongly concluded the table was absent.
- N8N-001A Automation Integration Foundation (READ-ONLY V1): **STAGING RUNTIME ACCEPTED 2026-08-10.** Architecture is fixed: n8n machine token → `n8n-read-api` Edge Function → `integration_n8n_*` SECURITY INVOKER RPCs → CRM tables, exposing **exactly three** actions (`health.v1`, `management.summary.v1`, `cases.readiness.v1`). Do not silently change any of the following: machine identity stays separate from `public.app_users` (no impersonation); `verify_jwt=false` is valid **only** because the Edge Function performs mandatory custom machine authentication itself; n8n holds a dedicated opaque token and Edge stores **only** the SHA-256 verifier; the service-role key is never exposed to n8n; all five integration RPCs are **SECURITY INVOKER** with `search_path=''` and service_role-only EXECUTE (**never** SECURITY DEFINER, and **no** new grant on an existing business table); `integration_request_logs` keeps RLS enabled with **0 policies** and service_role privileges of **exactly SELECT/INSERT/UPDATE**; there is **no** generic table/RPC/SQL proxy and **zero** business-data writes. Still open — do not report as complete: T15 cap and T19 timeout remain **STATIC VERIFIED**; T23 token replacement and n8n-side rotation are **NOT EXERCISED** (**never claim zero-downtime rotation** — V1 has one active verifier); migration-registry reconciliation is a separate future ticket; **N8N-001B and any AI Agent are NOT started and not approved**.
- Employer CRUD: **Admin path PASS on Staging 2026-07-26** (create / read / full-page reload / single-field edit / audit + privacy / relationship invariants / exact fixture cleanup / baseline restoration). Still open: **Staff runtime NOT TESTABLE** (0 active Staff, recorded as neither PASS nor FAIL); **employer delete NOT IMPLEMENTED** (no delete RPC, no UI control); **employer active/inactive NOT IMPLEMENTED**; **duplicate prevention remains PARTIAL** (no database uniqueness guarantee, no proven double-submit guard). Do not report the Employer workstream as complete.

Any proposal to change these requires a product decision and a dedicated stage.

## 16. Reporting format

Reports should be concise but evidence-based and include:

- Stage name and mode.
- Environment/Git.
- Scope and out-of-scope.
- Expected vs Actual.
- Exact IDs/counts when using synthetic fixtures.
- Audit/privacy result.
- Guard invariants.
- Files changed or “none”.
- Production status.
- Verdict and next permitted action.

Use these verdicts consistently:

- `PASS` — all acceptance criteria met.
- `PARTIAL / STATIC VERIFIED` — some runtime path was intentionally unavailable; exact limitation recorded.
- `BLOCKED` — prerequisite missing; no unsafe workaround attempted.
- `HARD STOP` — baseline, environment, permission, ownership, count, or security mismatch.

## 17. Session closeout

Before ending a meaningful session:

- Record current branch/HEAD/tree.
- Record database/environment state relevant to the stage.
- Record stage result and cleanup state.
- Update `CURRENT_STATE_LOCK.md` if the canonical state changed.
- Update `TEST_PLAN.md` and `DECISIONS_LOG.md` when results/decisions changed.
- Do not claim completion if documentation and cleanup are still pending.
