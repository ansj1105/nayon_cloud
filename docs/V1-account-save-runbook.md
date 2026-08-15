# V1 Account and Save Migration Runbook

## Schema delta

- Creates `player_accounts`, `auth_identities`, `player_save_states`, and `save_imports`.
- Creates unique constraints for public IDs, social identities, one identity per account, import request IDs, and imported save checksums.
- Stores the completed import response as JSON so an identical idempotent retry can return the original outcome.
- Creates one account/import-history index.
- Does not alter, drop, or backfill an existing table.

## Deploy order

1. Confirm the target database and schema are dedicated to NYAON.
2. Apply `db/migration/V1__create_player_account_and_save.sql` through Flyway.
3. Run table/constraint checks.
4. Deploy the compatible `nayon_api` V1 build.
5. Enable Unity V1 login/save only after the API health and authenticated smoke tests pass.

## Lock and performance risk

All `CREATE TABLE` operations acquire locks only on newly created relations. There is no existing-row rewrite or backfill. The only index is built on a newly created empty table, so initial runtime risk is low. The local verification timing is recorded after each run rather than treated as a production estimate.

## Rollback

Forward path:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f db/migration/V1__create_player_account_and_save.sql
```

Manual down path:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f db/rollback/U1__drop_player_account_and_save.sql
```

The down path is permitted only before production account/save rows exist. Roll it back when the migration fails or the API release is cancelled before accepting traffic. Once production writes exist, roll back the API while retaining the additive schema; do not drop user data.

## Verification

```bash
bash scripts/verify-v1.sh
```

The verifier creates an isolated PostgreSQL 16 cluster under `/tmp`, applies the migration, checks identity uniqueness and revision constraints, applies the rollback, and proves that no V1 tables remain.

## Observed local timings

Timings are workstation observations emitted by `scripts/verify-v1.sh`; they are not production SLOs.

- 2026-08-15, PostgreSQL 16.3, empty isolated cluster: forward 18 ms, rollback 12 ms
- 2026-08-15, PostgreSQL 16.3 after import-result constraint: forward 59 ms, rollback 9 ms
