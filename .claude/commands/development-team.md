---
description: Run a task through the CLOV development team — plan, implement (frontend / data layer), then review in parallel (swift, backend, security) and build-verify.
argument-hint: "[feature, bug, or change to deliver]"
---

# Development Team

Deliver `$ARGUMENTS` by orchestrating the project agents below. You are the lead: delegate, collect results, integrate, and report. Do not end your turn while an agent is still running.

## Roster

| Role | Agent | Owns |
|------|-------|------|
| Planner | `planner` | Implementation plan, risks, file list (read-only) |
| Architect | `architect` | Design decisions when the change spans layers (read-only) |
| Explorer | `code-explorer` | Tracing existing flows before changing them (read-only) |
| Frontend | `frontend` | `CLOV/Sources/Screens/**`, `Components/**`, App shell UI. Never touches networking/models |
| Data layer | `general-purpose` (brief it with the Supabase rules below) | `Networking/**`, `Models/**`, `App/AppState.swift` |
| Tests | `tdd-guide` | `CLOVTests/**`, test-first for logic changes |
| Swift review | `swift-reviewer` | Concurrency, ARC, idioms |
| Backend review | `backend-code-reviewer` | Supabase client, DTOs, auth/session, AppState |
| Security | `security-reviewer` | Auth, user input, RLS assumptions, secrets |
| Silent failures | `silent-failure-hunter` | Swallowed errors, bad fallbacks |
| Accessibility | `a11y-architect` | Only when UI changed |
| Build | `swift-build-resolver` | Only when the build fails |

## Workflow

1. **Scope** — Restate the task in 2-3 lines. If it's trivial (single-file, one layer), skip to step 3 with the one relevant agent.
2. **Plan** — Run `planner` (add `code-explorer` / `architect` in parallel if the change crosses UI + data). Show the user the plan and wait for confirmation before editing code if the change is non-trivial or touches auth, payments, or the try-on flow.
3. **Implement** — Split by ownership so agents never edit the same file:
   - UI work → `frontend`
   - Networking/model/AppState work → data-layer agent
   - Run these in parallel only when their files don't overlap; if UI depends on a new API signature, do data layer first.
   - Logic changes: `tdd-guide` writes failing tests in `CLOVTests/` first.
4. **Review (parallel)** — Launch together, scoped to `git diff`:
   `swift-reviewer`, `backend-code-reviewer` (if data layer touched), `security-reviewer` (if auth/input/network touched), `silent-failure-hunter`, `a11y-architect` (if UI touched).
5. **Fix** — Address CRITICAL/HIGH findings (route to the owning agent), re-review only what changed.
6. **Verify** — Regenerate with `xcodegen` if `project.yml` or files were added, then build and run unit tests:
   ```
   xcodegen generate
   xcodebuild -project CLOV.xcodeproj -scheme CLOV -destination 'platform=iOS Simulator,name=iPhone 16' build test
   ```
   On build failure, hand to `swift-build-resolver`.
7. **Report** — Summarize what changed (by file), review findings and their resolution, build/test result, and anything deferred. Do not commit unless asked.

## Rules

- No custom server exists; "backend" is the Supabase client layer.
- Never hardcode secrets; keep Supabase keys in existing config only.
- Prefer immutability, small functions, early returns (see `.claude/rules`).
- Do not touch unrelated uncommitted changes in the working tree.
