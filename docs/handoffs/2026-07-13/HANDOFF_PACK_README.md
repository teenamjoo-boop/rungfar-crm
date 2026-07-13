\
# RUNGFA CRM — HANDOFF PACK (2026-07-13)

This folder contains the repository-level source-of-truth documents for moving the project to a new ChatGPT Project/chat and continuing with Claude Code or Codex.

## Files

1. `PROJECT_MASTER_HANDOFF.md` — full system/business/technical handoff.
2. `AGENTS.md` — permanent rules for coding agents.
3. `CURRENT_STATE_LOCK.md` — latest verified Git/DB/stage state.
4. `ROADMAP.md` — planned sequencing and acceptance gates.
5. `TEST_PLAN.md` — test protocol and Stage 58K-C evidence.
6. `DECISIONS_LOG.md` — settled decisions and reasons.
7. `SHA256SUMS.txt` — checksums for cross-computer copy verification.

## Repository destination

Copy files 1–6 to:

```text
D:\dev\claude\
```

Do not commit until the user reviews the documentation diff and explicitly approves.

## New session start order

1. Read `AGENTS.md`.
2. Read `CURRENT_STATE_LOCK.md`.
3. Read `PROJECT_MASTER_HANDOFF.md`.
4. Read `ROADMAP.md`.
5. Read `TEST_PLAN.md`.
6. Read `DECISIONS_LOG.md`.
7. Re-run live Git/DB pre-flight; do not trust the snapshot blindly.

## Archive freeze policy

- The files in this dated archive folder are the **frozen original handoff-pack snapshot** and must not be edited.
- The documents at the repository root are the **active Source of Truth** and may contain reviewed corrections that this archive does not.
- `SHA256SUMS.txt` applies to the original flat-pack contents (the layout inside the ZIP); after the six documents were copied to the repository root, only files still in this folder verify in place.
- Moving files between the repository root and this archive directory does not indicate corruption.
- Do not silently copy an older archive file over a corrected root document.
