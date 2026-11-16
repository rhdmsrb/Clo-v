# Local migration harness

Runs `20261103000100_harden_security.sql` against a throwaway Postgres with
stubbed tables (no Supabase needed). The stubs are NOT the real schema, so a pass
proves the new SQL's logic, not that it fits the live database.

    initdb -D /tmp/pgt -U postgres && pg_ctl -D /tmp/pgt -o "-p 54399" start
    createdb -h 127.0.0.1 -p 54399 -U postgres t
    for f in tests/local/00_stub.sql migrations/20261103000100_harden_security.sql tests/local/10_harden_security.sql; do
      psql -h 127.0.0.1 -p 54399 -U postgres -d t -v ON_ERROR_STOP=1 -f supabase/$f; done

Expect the last line to read `ALL PASS`.
