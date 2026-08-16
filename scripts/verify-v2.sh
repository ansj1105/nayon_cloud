#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
v1="$repo_dir/db/migration/V1__create_player_account_and_save.sql"
v2="$repo_dir/db/migration/V2__create_player_economy.sql"
rollback="$repo_dir/db/rollback/U2__drop_player_economy.sql"

test -f "$v1"
test -f "$v2"
test -f "$rollback"

work_dir="$(mktemp -d /tmp/nayon-cloud-v2.XXXXXX)"
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

export PGHOST="$socket_dir"
export PGUSER=postgres
export PGDATABASE=postgres

"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$v1" >/dev/null

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$v2" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values ('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A');

insert into player_wallets(account_id, currency_code, balance)
values ('00000000-0000-0000-0000-000000000001', 'DIAMOND', 100);

insert into player_items(account_id, item_code, quantity)
values ('00000000-0000-0000-0000-000000000001', 'SILVER_KEY', 2);

insert into player_equipment(
    id, account_id, equipment_code, grade, source_type, source_id)
values (
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001',
    'Weapon_01', 'COMMON', 'BOOTSTRAP',
    '00000000-0000-0000-0000-000000000201');

insert into economy_ledger(
    id, account_id, asset_type, asset_code, delta,
    balance_before, balance_after, reason_code,
    reference_type, reference_id, request_id)
values (
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000001',
    'CURRENCY', 'DIAMOND', 100, 0, 100, 'BOOTSTRAP',
    'BOOTSTRAP', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000201');

insert into economy_bootstraps(
    account_id, request_id, request_hash, response_payload)
values (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000201',
    repeat('a', 64), '{}'::jsonb);

do $$
begin
  begin
    update player_wallets set balance = -1
     where account_id = '00000000-0000-0000-0000-000000000001';
    raise exception 'negative wallet balance was accepted';
  exception when check_violation then null;
  end;

  begin
    insert into economy_bootstraps(account_id, request_id, request_hash, response_payload)
    values (
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000202', repeat('b', 64), '{}'::jsonb);
    raise exception 'second account bootstrap was accepted';
  exception when unique_violation then null;
  end;
end
$$;

select 1
from pg_indexes
where indexname = 'economy_ledger_account_created_idx';

select 1
from pg_indexes
where indexname = 'player_equipment_account_created_idx';
SQL

index_count="$($pg_bin/psql -Atqc "select count(*) from pg_indexes where indexname in ('economy_ledger_account_created_idx', 'economy_ledger_reference_idx', 'player_equipment_account_created_idx', 'player_equipment_source_idx')")"
test "$index_count" = "4"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"

remaining="$($pg_bin/psql -Atqc "select count(*) from pg_class where relkind = 'r' and relname in ('player_wallets', 'player_items', 'player_equipment', 'economy_ledger', 'economy_bootstraps')")"
test "$remaining" = "0"

account_count="$($pg_bin/psql -Atqc "select count(*) from player_accounts")"
test "$account_count" = "1"

up_ms="$(((up_finished - up_started) / 1000000))"
down_ms="$(((down_finished - down_started) / 1000000))"
echo "V2 verification PASS forward_ms=$up_ms rollback_ms=$down_ms"
