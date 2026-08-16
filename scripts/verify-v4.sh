#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v4.XXXXXX)"
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
for version in 1 2 3; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done
up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 \
  -f "$repo_dir/db/migration/V4__create_battle_records.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values ('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A');
insert into battle_sessions(id, account_id, request_id, request_hash,
    stage_code, stage_snapshot, client_build, status, response_payload,
    started_at, expires_at)
values ('00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000201', repeat('a', 64),
    'STAGE_1', '{}'::jsonb, 'test', 'ACTIVE', '{}'::jsonb, now(), now() + interval '1 hour');
insert into battle_completions(id, battle_id, account_id, request_id, request_hash,
    outcome, elapsed_seconds, kill_count, total_damage, reached_wave,
    client_ended_at, metrics_payload, response_payload)
values ('00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000401', repeat('b', 64),
    'CLEAR', 300, 100, 1000, 10, now(), '{}'::jsonb, '{}'::jsonb);
insert into battle_anomalies(id, battle_id, rule_code, severity,
    observed_value, expected_value, details)
values ('00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000101', 'DAMAGE_ABOVE_MAX',
    'CRITICAL', '1000', '<=900', '{}'::jsonb);
insert into battle_rewards(id, battle_id, account_id, state, gold,
    account_exp, decision_details)
values ('00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001', 'HELD', 1000, 5, '{}'::jsonb);

do $$
begin
  begin
    insert into battle_rewards(id, battle_id, account_id, state, decision_details)
    values ('00000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000101',
        '00000000-0000-0000-0000-000000000001', 'GRANTED', '{}'::jsonb);
    raise exception 'second reward decision accepted';
  exception when unique_violation then null;
  end;
end
$$;
SQL

test "$($pg_bin/psql -Atqc "select count(*) from pg_indexes where indexname in ('battle_sessions_account_started_idx', 'battle_anomalies_rule_created_idx', 'battle_rewards_account_decided_idx')")" = "3"
down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/rollback/U4__drop_battle_records.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$($pg_bin/psql -Atqc "select count(*) from pg_class where relkind = 'r' and relname like 'battle_%'")" = "0"
echo "V4 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
