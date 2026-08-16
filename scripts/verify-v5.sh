#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v5.XXXXXX)"
data_dir="$work_dir/data"
socket_dir="$work_dir/socket"
mkdir -p "$socket_dir"

cleanup() {
  if test -f "$data_dir/postmaster.pid"; then
    "$pg_bin/pg_ctl" -D "$data_dir" -m fast stop >/dev/null
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres

for version in 1 2 3 4; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 \
  -f "$repo_dir/db/migration/V5__create_offline_battle_submissions.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname) values
('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A'),
('00000000-0000-0000-0000-000000000002', 'NYAON-TEST-0002', 'ACTIVE', 'B');

insert into offline_play_budgets(
    account_id, window_id, opened_at, expires_at, rules_version, rules_snapshot)
values ('00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000101', now(), now() + interval '1 hour',
    'test-v1', '{}'::jsonb);

insert into offline_battle_submissions(
    id, account_id, request_id, request_hash, window_id,
    requested_seconds, reward_state, response_payload)
values ('00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000301', repeat('a', 64),
    '00000000-0000-0000-0000-000000000101', 300, 'GRANTED', '{}'::jsonb);

do $$
begin
  begin
    insert into offline_battle_runs(
        id, submission_id, account_id, run_id, stage_code, outcome,
        elapsed_seconds, kill_count, total_damage, reached_wave, metrics_payload)
    values ('00000000-0000-0000-0000-000000000401',
        '00000000-0000-0000-0000-000000000201',
        '00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000501', 'STAGE_1', 'CLEAR',
        300, 100, 1000, 16, '{}'::jsonb);
    raise exception 'cross-account run accepted';
  exception when foreign_key_violation then null;
  end;
end
$$;
SQL

test "$($pg_bin/psql -Atqc "select count(*) from pg_class where relkind = 'r' and relname like 'offline_%'")" = "5"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.columns where table_name = 'offline_play_budgets' and column_name in ('rules_version', 'rules_snapshot')")" = "2"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 \
  -f "$repo_dir/db/rollback/U5__drop_offline_battle_submissions.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$($pg_bin/psql -Atqc "select count(*) from pg_class where relkind = 'r' and relname like 'offline_%'")" = "0"

echo "V5 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
