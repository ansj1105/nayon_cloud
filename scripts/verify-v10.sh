#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v10.XXXXXX)"
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

test -f "$repo_dir/db/migration/V10__create_first_purchase_rewards.sql"
test -f "$repo_dir/db/rollback/U10__drop_first_purchase_rewards.sql"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
if ! "$pg_bin/pg_ctl" -D "$data_dir" -l "$work_dir/postgres.log" \
    -o "-F -k $socket_dir -h ''" -w start >/dev/null; then
  sed -n '1,120p' "$work_dir/postgres.log" >&2
  exit 1
fi
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in 1 2 3 4 5 6 7 8 9; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/migration/V10__create_first_purchase_rewards.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values
  ('00000000-0000-0000-0000-000000000001', 'NYAON-FIRST-0001', 'ACTIVE', 'A'),
  ('00000000-0000-0000-0000-000000000002', 'NYAON-FIRST-0002', 'ACTIVE', 'B');

insert into store_products(id, offer_id, platform, store_product_id, product_type, active)
select '00000000-0000-0000-0000-000000000101', id,
       'GOOGLE_PLAY', 'nayon.diamond.100', 'ONE_TIME', true
  from store_offers where offer_code = 'diamond_100';

insert into store_product_versions(
    id, product_id, version, reward_asset_type, reward_asset_code,
    reward_amount, valid_from, active)
values ('00000000-0000-0000-0000-000000000201',
        '00000000-0000-0000-0000-000000000101', 1,
        'CURRENCY', 'DIAMOND', 100, now(), true);

insert into store_purchase_receipts(
    id, account_id, request_id, request_hash, platform, store_product_id,
    purchase_token, purchase_token_hash, state, product_id,
    product_version_id, google_order_id, google_purchase_time, verified_at,
    reward_asset_code, reward_amount, total_asset_balance, granted_at)
values
  ('00000000-0000-0000-0000-000000000301',
   '00000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000401', repeat('a', 64),
   'GOOGLE_PLAY', 'nayon.diamond.100', 'token-a', repeat('b', 64), 'GRANTED',
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000201', 'order-a', now(), now(),
   'DIAMOND', 100, 100, now()),
  ('00000000-0000-0000-0000-000000000302',
   '00000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000402', repeat('c', 64),
   'GOOGLE_PLAY', 'nayon.diamond.100', 'token-b', repeat('d', 64), 'GRANTED',
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000201', 'order-b', now(), now(),
   'DIAMOND', 100, 100, now()),
  ('00000000-0000-0000-0000-000000000303',
   '00000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000403', repeat('e', 64),
   'GOOGLE_PLAY', 'nayon.diamond.100', 'token-c', repeat('f', 64), 'GRANTED',
   '00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000201', 'order-c', now(), now(),
   'DIAMOND', 100, 100, now());

insert into player_equipment(id, account_id, equipment_code, grade, source_type, source_id)
values
  ('00000000-0000-0000-0000-000000000501',
   '00000000-0000-0000-0000-000000000001',
   'E41000', 'COMMON', 'FIRST_PURCHASE_REWARD',
   '00000000-0000-0000-0000-000000000601'),
  ('00000000-0000-0000-0000-000000000503',
   '00000000-0000-0000-0000-000000000002',
   'E41002', 'COMMON', 'FIRST_PURCHASE_REWARD',
   '00000000-0000-0000-0000-000000000603'),
  ('00000000-0000-0000-0000-000000000504',
   '00000000-0000-0000-0000-000000000001',
   'E41003', 'COMMON', 'FIRST_PURCHASE_REWARD',
   '00000000-0000-0000-0000-000000000604');

insert into player_first_purchase_rewards(
    id, account_id, qualifying_receipt_id, reward_version_id,
    equipment_id, equipment_code, equipment_grade,
    diamond_amount, gold_amount, diamond_balance, gold_balance, granted_at)
values ('00000000-0000-0000-0000-000000000601',
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000301',
        '00000000-0000-0000-0000-000000001001',
        '00000000-0000-0000-0000-000000000501',
        'E41000', 'COMMON', 50, 10000, 150, 10000, now());

do $$
begin
  begin
    insert into player_first_purchase_rewards(
        id, account_id, qualifying_receipt_id, reward_version_id,
        equipment_id, equipment_code, equipment_grade,
        diamond_amount, gold_amount, diamond_balance, gold_balance, granted_at)
    values ('00000000-0000-0000-0000-000000000602',
            '00000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000302',
            '00000000-0000-0000-0000-000000001001',
            '00000000-0000-0000-0000-000000000502',
            'E41001', 'COMMON', 50, 10000, 150, 10000, now());
    raise exception 'second account reward accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into player_first_purchase_rewards(
        id, account_id, qualifying_receipt_id, reward_version_id,
        equipment_id, equipment_code, equipment_grade,
        diamond_amount, gold_amount, diamond_balance, gold_balance, granted_at)
    values ('00000000-0000-0000-0000-000000000603',
            '00000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000303',
            '00000000-0000-0000-0000-000000001001',
            '00000000-0000-0000-0000-000000000503',
            'E41002', 'COMMON', 50, 10000, 150, 10000, now());
    raise exception 'cross-account receipt accepted';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into first_purchase_reward_versions(
        id, version, equipment_catalog_version, equipment_grade,
        diamond_amount, gold_amount, valid_from, active)
    values ('00000000-0000-0000-0000-000000001002', 2,
            'unity-equipment-2026-08-16', 'COMMON', 50, 10000, now(), true);
    raise exception 'second active reward version accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into player_first_purchase_rewards(
        id, account_id, qualifying_receipt_id, reward_version_id,
        equipment_id, equipment_code, equipment_grade,
        diamond_amount, gold_amount, diamond_balance, gold_balance, granted_at)
    values ('00000000-0000-0000-0000-000000000604',
            '00000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000302',
            '00000000-0000-0000-0000-000000001001',
            '00000000-0000-0000-0000-000000000504',
            'E41003', 'COMMON', 50, 10000, 150, 10000, now());
    raise exception 'cross-account equipment accepted';
  exception when foreign_key_violation then null;
  end;
end
$$;
SQL

test "$("$pg_bin/psql" -Atqc "select count(*) from first_purchase_reward_versions")" = "1"
test "$("$pg_bin/psql" -Atqc "select count(*) from player_first_purchase_rewards")" = "1"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/rollback/U10__drop_first_purchase_rewards.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$("$pg_bin/psql" -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('first_purchase_reward_versions','player_first_purchase_rewards')")" = "0"
test "$("$pg_bin/psql" -Atqc "select count(*) from pg_constraint where conname='store_purchase_receipts_id_account_key'")" = "0"
test "$("$pg_bin/psql" -Atqc "select count(*) from pg_constraint where conname='player_equipment_id_account_key'")" = "0"

echo "V10 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
