#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
v1="$repo_dir/db/migration/V1__create_player_account_and_save.sql"
v2="$repo_dir/db/migration/V2__create_player_economy.sql"
v3="$repo_dir/db/migration/V3__create_gacha_history.sql"
rollback="$repo_dir/db/rollback/U3__drop_gacha_history.sql"

test -f "$v1"; test -f "$v2"; test -f "$v3"; test -f "$rollback"
work_dir="$(mktemp -d /tmp/nayon-cloud-v3.XXXXXX)"
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
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$v1" >/dev/null
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$v2" >/dev/null

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$v3" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values ('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A');
insert into gacha_pity_states(account_id, banner_code, hero_pity, legendary_pity)
values ('00000000-0000-0000-0000-000000000001', 'CHROMA_SEASON_01', 9, 49);
insert into gacha_draws(id, account_id, request_id, request_hash, banner_code,
    payment_asset_type, payment_asset_code, payment_amount, draw_count, response_payload)
values ('00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000201', repeat('a', 64),
    'CHROMA_SEASON_01', 'ITEM', 'CHROMA_FRAGMENT', 30, 1, '{}'::jsonb);
insert into player_equipment(id, account_id, equipment_code, grade, source_type, source_id)
values ('00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000001', 'S01_W01_L', 'UNIQUE', 'GACHA',
    '00000000-0000-0000-0000-000000000101');
insert into gacha_draw_results(draw_id, result_index, equipment_id, equipment_code, grade, chroma)
values ('00000000-0000-0000-0000-000000000101', 0,
    '00000000-0000-0000-0000-000000000301', 'S01_W01_L', 'UNIQUE', true);

do $$
begin
  begin
    insert into gacha_draws(id, account_id, request_id, request_hash, banner_code,
        payment_asset_type, payment_asset_code, payment_amount, draw_count, response_payload)
    values ('00000000-0000-0000-0000-000000000102',
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000201', repeat('b', 64),
        'COMMON', 'ITEM', 'SILVER_KEY', 1, 1, '{}'::jsonb);
    raise exception 'duplicate account request was accepted';
  exception when unique_violation then null;
  end;
  begin
    update gacha_pity_states set hero_pity = -1
     where account_id = '00000000-0000-0000-0000-000000000001';
    raise exception 'negative pity was accepted';
  exception when check_violation then null;
  end;
end
$$;
SQL

index_count="$($pg_bin/psql -Atqc "select count(*) from pg_indexes where indexname in ('gacha_draws_account_created_idx', 'gacha_draw_results_equipment_code_idx')")"
test "$index_count" = "2"
down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"
remaining="$($pg_bin/psql -Atqc "select count(*) from pg_class where relkind = 'r' and relname in ('gacha_pity_states', 'gacha_draws', 'gacha_draw_results')")"
test "$remaining" = "0"
test "$($pg_bin/psql -Atqc "select count(*) from player_equipment")" = "1"
up_ms="$(((up_finished - up_started) / 1000000))"
down_ms="$(((down_finished - down_started) / 1000000))"
echo "V3 verification PASS forward_ms=$up_ms rollback_ms=$down_ms"
