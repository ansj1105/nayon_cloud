# nayon_cloud

Flyway-owned PostgreSQL schema for NYAON HUNTERS services.

## Layout

- `db/migration`: forward Flyway migrations
- `db/rollback`: operator-run rollback SQL
- `scripts`: isolated PostgreSQL verification
- `docs`: release and recovery runbooks

## Verify migrations

```bash
bash scripts/verify-v1.sh
bash scripts/verify-v2.sh
bash scripts/verify-v3.sh
```

Override the bundled PostgreSQL tool location with `PG_BIN=/path/to/postgres/bin` when needed.
