# ParkWell — agent instructions

Rules for any Claude session (local CLI or remote) working in this repo.

## Git workflow

- `main` is the reviewed trunk. **Never commit or push directly to `main`.**
- Work on a feature branch: `claude/local-<topic>` (local CLI sessions) or
  `claude/remote-<topic>` (remote sessions). Merge to `main` via pull request
  only.
- **Never force-push** (`--force`, `--force-with-lease`, amend-then-push) to
  any branch another session may have pulled. If a commit needs fixing after
  push, add a follow-up commit instead.
- Pull before pushing — two agents share this repo.
- Do not commit local tooling artifacts (`.agents/`, `skills-lock.json`,
  generated Info.plists) — see `.gitignore`.

## Project facts

- iOS app in `ios/` — XcodeGen project: run `xcodegen generate` after
  `project.yml` changes or when files are added/removed; the `.xcodeproj`
  and Info.plists are generated, not committed.
- Backend: Supabase project `yinolxfbmcsdzmeiyokg` (ca-central-1), linked via
  CLI from repo root. Schema lives in `supabase/migrations/` (0001–0005
  applied remotely). All tables RLS read-only for the anon key.
- `supabase/imports/hrm_import.sql` is **generated** by
  `tools/hrm-import/import_hrm.py` — never hand-edit it; fix the generator
  and regenerate. It's too big for the SQL Editor; apply via psql or the
  Management API (chunked — see the local session memory about the
  `db push` 502 fallback).
- The rule engine (`ios/ParkWell/Services/RuleEngine.swift`) is pure and
  fully covered by `ios/ParkWellTests/RuleEngineTests.swift` — keep it that
  way; new rule logic needs tests.
- Product principle: **honest degradation**. Never show confident status on
  stale or unverified data — staleness flags, "likely OK" vs verified green,
  and "check posted signs" copy are load-bearing, not decoration.

## Secrets

- Never commit API keys. The Supabase anon (publishable) key in
  `ios/ParkWell/Config.swift` is intentionally public; the `ANTHROPIC_API_KEY`
  lives only in Supabase edge-function secrets; the database password and
  CLI tokens stay in the local keychain.
