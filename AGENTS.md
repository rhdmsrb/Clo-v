# CLO-V iOS — agent instructions

Read `CLAUDE.md` in this repo root first and follow it. It is the source of truth for project rules (XcodeGen workflow, additive-only DB changes, reuse of `Theme`/`FloatingTabBar`/`FlowLayout`/`Haptics`, accessibility identifiers, Reduce Motion, VoiceOver labels). The UI redesign spec is `docs/ui-redesign-spec.md`.

## Working here
- This is a git worktree on branch `codex/work`. Commit only to this branch. Do not touch other worktrees or the main checkout at `/Users/danny/Desktop/CLOV-iOS`; other agents work there concurrently.
- Never hand-edit `CLOV.xcodeproj/project.pbxproj`. Add files under `CLOV/Sources/` and run `xcodegen generate`.
- Use a build-local derived data folder so builds don't collide with other agents:
  `xcodebuild -project CLOV.xcodeproj -scheme CLOV -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath .build/dd build`
- Do not commit changes that point `AppConfig` / `SupabaseManager.swift` at a local Supabase (`127.0.0.1`). Production URL and key must stay as committed.
- Do not apply Supabase migrations to the remote project. Database changes are additive only, each with a matching file in `supabase/rollback/`.
- Commit messages: `<type>: <description>` with type one of feat, fix, refactor, docs, test, chore, perf, ci.
- Update UI tests in the same change as the UI they cover.
