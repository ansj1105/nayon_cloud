#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v11.XXXXXX)"
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

forward="$repo_dir/db/migration/V11__create_limited_benefit_campaigns.sql"
rollback="$repo_dir/db/rollback/U11__drop_limited_benefit_campaigns.sql"
test -f "$forward"
test -f "$rollback"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -l "$work_dir/postgres.log" \
  -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in 1 2 3 4 5 6 7 8 9 10; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$forward" >/dev/null
up_finished="$(date +%s%N)"

test "$("$pg_bin/psql" -Atqc "select count(*) from limited_benefit_campaign_versions")" = "1"
test "$("$pg_bin/psql" -Atqc "select count(*) from limited_benefit_offers")" = "24"
test "$("$pg_bin/psql" -Atqc "select count(*) from limited_benefit_offer_rewards")" = "56"
test "$("$pg_bin/psql" -Atqc "select count(*) from store_offers where offer_code like 'limited_%'")" = "4"
test "$("$pg_bin/psql" -Atqc "select count(*) from store_product_versions where fulfillment_type <> 'DIRECT_CURRENCY'")" = "0"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values
  ('00000000-0000-0000-0000-000000000001', 'NYAON-LIMITED-0001', 'ACTIVE', 'A'),
  ('00000000-0000-0000-0000-000000000002', 'NYAON-LIMITED-0002', 'ACTIVE', 'B');

insert into player_limited_benefit_claims(
    id, account_id, campaign_version_id, offer_id, cycle_date,
    request_id, request_hash, proof_type, response_payload, claimed_at)
select '00000000-0000-0000-0000-000000000101',
       '00000000-0000-0000-0000-000000000001',
       o.campaign_version_id, o.id, date '2026-08-17',
       '00000000-0000-0000-0000-000000000201', repeat('a', 64),
       'FREE', '{}'::jsonb, now()
  from limited_benefit_offers o where o.offer_code = 'free_01';

do $$
declare
  campaign_id uuid := '00000000-0000-0000-0000-000000011101';
  free_offer_id uuid;
begin
  select id into free_offer_id from limited_benefit_offers
   where campaign_version_id = campaign_id and offer_code = 'free_01';

  begin
    insert into player_limited_benefit_claims(
        id, account_id, campaign_version_id, offer_id, cycle_date,
        request_id, request_hash, proof_type, response_payload, claimed_at)
    values ('00000000-0000-0000-0000-000000000102',
            '00000000-0000-0000-0000-000000000001', campaign_id,
            free_offer_id, date '2026-08-17',
            '00000000-0000-0000-0000-000000000202', repeat('b', 64),
            'FREE', '{}'::jsonb, now());
    raise exception 'duplicate daily offer claim accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into limited_benefit_campaign_versions(
        id, campaign_code, version, zone_id, valid_from, active)
    values ('00000000-0000-0000-0000-000000011102',
            'daily_limited_benefit', 2, 'Asia/Seoul', now(), true);
    raise exception 'second active campaign accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into limited_benefit_offer_rewards(
        offer_id, campaign_version_id, reward_order,
        reward_type, reward_code, amount)
    values (free_offer_id, campaign_id, 9, 'ITEM', 'CLIENT_GEMS', 1);
    raise exception 'invalid reward code accepted';
  exception when check_violation then null;
  end;

  begin
    insert into admob_reward_callbacks(
        transaction_id, ad_session_id, raw_query, key_id,
        verified, received_at)
    values ('tx-duplicate', null, 'a=b', 1, false, now()),
           ('tx-duplicate', null, 'c=d', 1, false, now());
    raise exception 'duplicate AdMob transaction accepted';
  exception when unique_violation then null;
  end;
end
$$;
SQL

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"

test "$("$pg_bin/psql" -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name like '%limited_benefit%'")" = "0"
test "$("$pg_bin/psql" -Atqc "select count(*) from information_schema.columns where table_name='store_product_versions' and column_name='fulfillment_type'")" = "0"
test "$("$pg_bin/psql" -Atqc "select count(*) from store_offers where offer_code like 'limited_%'")" = "0"

echo "V11 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
