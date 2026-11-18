# Local migration harness

Runs `20261103000100_harden_security.sql` against a throwaway Postgres with
stubbed tables (no Supabase needed). The stubs are NOT the real schema, so a pass
proves the new SQL's logic, not that it fits the live database.

    initdb -D /tmp/pgt -U postgres && pg_ctl -D /tmp/pgt -o "-p 54399" start
    createdb -h 127.0.0.1 -p 54399 -U postgres t
    for f in tests/local/00_stub.sql migrations/20261103000100_harden_security.sql tests/local/10_harden_security.sql; do
      psql -h 127.0.0.1 -p 54399 -U postgres -d t -v ON_ERROR_STOP=1 -f supabase/$f; done

Expect the last line to read `ALL PASS`.

## Phase 2 against the checked-in snapshot

Use a **disposable PostgreSQL cluster**, not a linked or production project.
`00_snapshot_bootstrap.sql` supplies minimal Supabase roles, `auth.uid()`, an
`auth.users` table, and pgcrypto. The snapshot itself supplies the application
schema, policies and RPCs. The test inserts storage metadata to represent uploads;
it does not exercise the Storage API, PostgREST, or an iOS binary. It also does
not establish that the 2026-11-03 snapshot matches the current live schema.

For PostgreSQL 17 or later, with a fresh empty database at `DB_URL`:

```sh
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/local/00_snapshot_bootstrap.sql \
  -f supabase/baseline/remote_schema_2026-11-03.sql \
  -f supabase/tests/local/60_phase2_snapshot.sql
```

PostgreSQL 16 does not support the snapshot's `MAINTAIN` table privilege. For
that version only, copy the snapshot to a temporary file with `,MAINTAIN`
removed and use that copy in the command above. No table, policy or function is
changed by that compatibility adjustment. The last line should be `ALL PASS`.
The test applies the Phase 2 migrations and the later audience migration locally,
checks legacy and current posting, and exercises the migration rollbacks.

## Runtime reads and draft cleanup

On a fresh disposable database with the snapshot loaded, apply the
`20261107000100`, `20261107000200`, `20261107000500` and
`20261108000100` migrations before the two runtime migrations. Then run
`70_runtime_read_paths.sql` and `80_claim_draft_cleanup.sql` with
`psql -v ON_ERROR_STOP=1`. Both tests roll back their fixtures.

The assertions cover audience and comment visibility, vote privacy, cursor
ties and timestamp precision, bounded group previews, and publishing after
a cleanup claim. The checks use Storage metadata to model uploaded objects.
