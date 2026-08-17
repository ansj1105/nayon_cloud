#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v9.XXXXXX)"
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

test -f "$repo_dir/db/migration/V9__create_store_purchase_tables.sql"
test -f "$repo_dir/db/rollback/U9__drop_store_purchase_tables.sql"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in 1 2 3 4 5 6 7 8; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/migration/V9__create_store_purchase_tables.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values
  ('00000000-0000-0000-0000-000000000001', 'NYAON-STORE-0001', 'ACTIVE', 'A'),
  ('00000000-0000-0000-0000-000000000002', 'NYAON-STORE-0002', 'ACTIVE', 'B');

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
    purchase_token, purchase_token_hash, state, product_id)
values ('00000000-0000-0000-0000-000000000301',
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000401', repeat('a', 64),
        'GOOGLE_PLAY', 'nayon.diamond.100', 'test-purchase-token-a', repeat('b', 64),
        'PENDING_VERIFICATION',
        '00000000-0000-0000-0000-000000000101');

do $$
begin
  begin
    insert into store_products(id, offer_id, platform, store_product_id, product_type, active)
    select '00000000-0000-0000-0000-000000000102', id,
           'GOOGLE_PLAY', 'nayon.diamond.100.alt', 'ONE_TIME', true
      from store_offers where offer_code = 'diamond_100';
    raise exception 'second active platform product accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into store_product_versions(
        id, product_id, version, reward_asset_type, reward_asset_code,
        reward_amount, valid_from, active)
    values ('00000000-0000-0000-0000-000000000202',
            '00000000-0000-0000-0000-000000000101', 2,
            'CURRENCY', 'DIAMOND', 200, now(), true);
    raise exception 'second active reward version accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into store_purchase_receipts(
        id, account_id, request_id, request_hash, platform, store_product_id,
        purchase_token, purchase_token_hash, state, product_id)
    values ('00000000-0000-0000-0000-000000000302',
            '00000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000402', repeat('c', 64),
            'GOOGLE_PLAY', 'nayon.diamond.100', 'test-purchase-token-a', repeat('b', 64),
            'PENDING_VERIFICATION',
            '00000000-0000-0000-0000-000000000101');
    raise exception 'duplicate purchase token accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into store_product_versions(
        id, product_id, version, reward_asset_type, reward_asset_code,
        reward_amount, valid_from, active)
    values ('00000000-0000-0000-0000-000000000203',
            '00000000-0000-0000-0000-000000000101', 3,
            'CURRENCY', 'DIAMOND', 0, now(), false);
    raise exception 'zero reward accepted';
  exception when check_violation then null;
  end;
end
$$;
SQL

test "$($pg_bin/psql -Atqc "select count(*) from store_offers")" = "6"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('store_offers','store_products','store_product_versions','store_purchase_receipts')")" = "4"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/rollback/U9__drop_store_purchase_tables.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('store_offers','store_products','store_product_versions','store_purchase_receipts')")" = "0"

echo "V9 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
