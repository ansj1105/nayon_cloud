#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v12.XXXXXX)"
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

forward="$repo_dir/db/migration/V12__support_limited_benefit_store_products.sql"
rollback="$repo_dir/db/rollback/U12__restore_direct_store_product_payload.sql"
test -f "$forward"
test -f "$rollback"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -l "$work_dir/postgres.log" \
  -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in $(seq 1 11); do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$forward" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into store_products(id, offer_id, platform, store_product_id, product_type, active)
values ('00000000-0000-0000-0000-000000012001',
        '00000000-0000-0000-0000-000000009201',
        'GOOGLE_PLAY', 'nayon.limited.3000.a', 'ONE_TIME', true);

insert into store_product_versions(
    id, product_id, version, reward_asset_type, reward_asset_code,
    reward_amount, fulfillment_type, valid_from, active)
values ('00000000-0000-0000-0000-000000012101',
        '00000000-0000-0000-0000-000000012001', 1,
        null, null, null, 'LIMITED_BENEFIT', now(), true);

do $$
begin
  begin
    insert into store_product_versions(
        id, product_id, version, reward_asset_type, reward_asset_code,
        reward_amount, fulfillment_type, valid_from)
    values ('00000000-0000-0000-0000-000000012102',
            '00000000-0000-0000-0000-000000012001', 2,
            'CURRENCY', 'DIAMOND', 10, 'LIMITED_BENEFIT', now());
    raise exception 'limited benefit accepted a direct reward payload';
  exception when check_violation then null;
  end;

  begin
    insert into store_product_versions(
        id, product_id, version, reward_asset_type, reward_asset_code,
        reward_amount, fulfillment_type, valid_from)
    values ('00000000-0000-0000-0000-000000012103',
            '00000000-0000-0000-0000-000000012001', 3,
            null, null, null, 'DIRECT_CURRENCY', now());
    raise exception 'direct currency accepted an empty reward payload';
  exception when check_violation then null;
  end;
end
$$;
SQL

"$pg_bin/psql" -v ON_ERROR_STOP=1 -c \
  "delete from store_product_versions where fulfillment_type='LIMITED_BENEFIT'" >/dev/null
down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"

test "$($pg_bin/psql -Atqc "select is_nullable from information_schema.columns where table_name='store_product_versions' and column_name='reward_amount'")" = "NO"

echo "V12 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
