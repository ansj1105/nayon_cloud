#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v13.XXXXXX)"
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

forward="$repo_dir/db/migration/V13__create_subscriptions_and_level_rewards.sql"
rollback="$repo_dir/db/rollback/U13__drop_subscriptions_and_level_rewards.sql"
test -f "$forward"
test -f "$rollback"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -l "$work_dir/postgres.log" \
  -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in $(seq 1 12); do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$forward" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values
  ('00000000-0000-0000-0000-000000013001', 'NYAON-SUB-0001', 'ACTIVE', 'A'),
  ('00000000-0000-0000-0000-000000013002', 'NYAON-SUB-0002', 'ACTIVE', 'B');

insert into store_products(id, offer_id, platform, store_product_id, product_type, active)
select '00000000-0000-0000-0000-000000013101', id,
       'GOOGLE_PLAY', 'test.monthly.growth', 'SUBSCRIPTION', true
  from store_offers where offer_code = 'monthly_growth';

insert into store_product_versions(
    id, product_id, version, reward_asset_type, reward_asset_code,
    reward_amount, fulfillment_type, valid_from, active)
values ('00000000-0000-0000-0000-000000013201',
        '00000000-0000-0000-0000-000000013101', 1,
        null, null, null, 'SUBSCRIPTION', now(), true);

insert into player_subscriptions(
    id, account_id, plan_id, purchase_token, purchase_token_hash,
    state, started_at, expires_at, auto_renewing,
    acknowledgement_state, last_verified_at)
select '00000000-0000-0000-0000-000000013301',
       '00000000-0000-0000-0000-000000013001', id,
       'test-subscription-token-a', repeat('a', 64), 'ACTIVE', now(),
       now() + interval '30 days', true, 'ACKNOWLEDGED', now()
  from subscription_plans where plan_code = 'MONTHLY_GROWTH';

insert into level_reward_versions(
    id, catalog_version, track_code, required_level,
    reward_asset_type, reward_asset_code, reward_amount,
    valid_from, active)
values ('00000000-0000-0000-0000-000000013401', 1, 'PREMIUM', 5,
        'CURRENCY', 'DIAMOND', 100, now(), true);

insert into economy_ledger(
    id, account_id, asset_type, asset_code, delta,
    balance_before, balance_after, reason_code,
    reference_type, reference_id, request_id)
values ('00000000-0000-0000-0000-000000013501',
        '00000000-0000-0000-0000-000000013001',
        'CURRENCY', 'DIAMOND', 100, 0, 100,
        'LEVEL_REWARD', 'LEVEL_REWARD_CLAIM',
        '00000000-0000-0000-0000-000000013601',
        '00000000-0000-0000-0000-000000013701');

insert into player_level_reward_claims(
    id, account_id, request_id, request_hash,
    track_code, required_level, reward_version_id,
    reward_asset_type, reward_asset_code, reward_amount,
    ledger_id, response_payload, claimed_at)
values ('00000000-0000-0000-0000-000000013601',
        '00000000-0000-0000-0000-000000013001',
        '00000000-0000-0000-0000-000000013701', repeat('b', 64),
        'PREMIUM', 5, '00000000-0000-0000-0000-000000013401',
        'CURRENCY', 'DIAMOND', 100,
        '00000000-0000-0000-0000-000000013501', '{}'::jsonb, now());

do $$
begin
  begin
    insert into store_products(id, offer_id, platform, store_product_id, product_type)
    select '00000000-0000-0000-0000-000000013102', id,
           'GOOGLE_PLAY', 'test.bad.product', 'RECURRING'
      from store_offers where offer_code = 'monthly_advanced';
    raise exception 'unknown product type accepted';
  exception when check_violation then null;
  end;

  begin
    insert into player_subscriptions(
        id, account_id, plan_id, purchase_token, purchase_token_hash,
        state, acknowledgement_state)
    select '00000000-0000-0000-0000-000000013302',
           '00000000-0000-0000-0000-000000013002', id,
           'test-subscription-token-b', repeat('a', 64),
           'PENDING', 'PENDING'
      from subscription_plans where plan_code = 'MONTHLY_ADVANCED';
    raise exception 'duplicate purchase token hash accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into level_reward_versions(
        id, catalog_version, track_code, required_level,
        reward_asset_type, reward_asset_code, reward_amount,
        valid_from, active)
    values ('00000000-0000-0000-0000-000000013402', 2, 'PREMIUM', 5,
            'CURRENCY', 'DIAMOND', 200, now(), true);
    raise exception 'second active level reward accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into player_level_reward_claims(
        id, account_id, request_id, request_hash,
        track_code, required_level, reward_version_id,
        reward_asset_type, reward_asset_code, reward_amount,
        ledger_id, response_payload, claimed_at)
    values ('00000000-0000-0000-0000-000000013602',
            '00000000-0000-0000-0000-000000013001',
            '00000000-0000-0000-0000-000000013702', repeat('c', 64),
            'PREMIUM', 5, '00000000-0000-0000-0000-000000013401',
            'CURRENCY', 'DIAMOND', 100,
            '00000000-0000-0000-0000-000000013501', '{}'::jsonb, now());
    raise exception 'duplicate lifetime level reward accepted';
  exception when unique_violation then null;
  end;
end
$$;
SQL

test "$($pg_bin/psql -Atqc "select count(*) from subscription_plans")" = "2"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('subscription_plans','subscription_benefit_versions','player_subscriptions','subscription_verification_requests','google_play_rtdn_events','level_reward_versions','player_level_reward_claims','player_subscription_initial_rewards','player_subscription_daily_rewards')")" = "9"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.columns where table_schema='public' and table_name='subscription_verification_requests' and column_name in ('store_product_id','purchase_token','purchase_token_hash') and is_nullable='NO'")" = "3"

"$pg_bin/psql" -v ON_ERROR_STOP=1 -c "delete from player_level_reward_claims" >/dev/null
"$pg_bin/psql" -v ON_ERROR_STOP=1 -c "delete from economy_ledger where reason_code='LEVEL_REWARD'" >/dev/null
"$pg_bin/psql" -v ON_ERROR_STOP=1 -c "delete from level_reward_versions" >/dev/null
"$pg_bin/psql" -v ON_ERROR_STOP=1 -c "delete from player_subscriptions" >/dev/null
"$pg_bin/psql" -v ON_ERROR_STOP=1 -c "delete from store_product_versions where fulfillment_type='SUBSCRIPTION'" >/dev/null
"$pg_bin/psql" -v ON_ERROR_STOP=1 -c "delete from store_products where product_type='SUBSCRIPTION'" >/dev/null

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"

test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('subscription_plans','subscription_benefit_versions','player_subscriptions','subscription_verification_requests','google_play_rtdn_events','level_reward_versions','player_level_reward_claims','player_subscription_initial_rewards','player_subscription_daily_rewards')")" = "0"

echo "V13 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
