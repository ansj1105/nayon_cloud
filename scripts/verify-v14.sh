#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v14.XXXXXX)"
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

forward="$repo_dir/db/migration/V14__create_weekly_gift.sql"
rollback="$repo_dir/db/rollback/U14__drop_weekly_gift.sql"
test -f "$forward"
test -f "$rollback"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -l "$work_dir/postgres.log" \
  -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres

for version in $(seq 1 13); do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$forward" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values ('00000000-0000-0000-0000-000000014001',
        'NYAON-WEEKLY-0001', 'ACTIVE', 'weekly-test');

insert into weekly_gift_reward_versions(
    id, version, reward_asset_type, reward_asset_code,
    reward_amount, valid_from, active)
values ('00000000-0000-0000-0000-000000014101', 1,
        'CURRENCY', 'DIAMOND', 1, now(), true);

insert into player_weekly_gift_weeks(account_id, week_start)
values ('00000000-0000-0000-0000-000000014001', date '2026-08-17');

insert into player_weekly_gift_login_days(account_id, week_start, login_date)
values
  ('00000000-0000-0000-0000-000000014001', date '2026-08-17', date '2026-08-17'),
  ('00000000-0000-0000-0000-000000014001', date '2026-08-17', date '2026-08-19');

insert into player_weekly_gift_login_days(account_id, week_start, login_date)
values ('00000000-0000-0000-0000-000000014001',
        date '2026-08-17', date '2026-08-19')
on conflict do nothing;

do $$
begin
  begin
    insert into player_weekly_gift_weeks(account_id, week_start)
    values ('00000000-0000-0000-0000-000000014001', date '2026-08-18');
    raise exception 'non-Monday week_start accepted';
  exception when check_violation then null;
  end;

  begin
    insert into player_weekly_gift_login_days(account_id, week_start, login_date)
    values ('00000000-0000-0000-0000-000000014001',
            date '2026-08-17', date '2026-08-24');
    raise exception 'login_date outside week accepted';
  exception when check_violation then null;
  end;

  begin
    update player_weekly_gift_weeks
       set claimed_at = now(), claim_request_id = gen_random_uuid(),
           claim_response = '{}'::jsonb
     where account_id = '00000000-0000-0000-0000-000000014001';
    raise exception 'claim without reward version accepted';
  exception when check_violation then null;
  end;
end
$$;
SQL

test "$("$pg_bin/psql" -Atqc "select count(*) from player_weekly_gift_login_days")" = "2"
test "$("$pg_bin/psql" -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('weekly_gift_reward_versions','player_weekly_gift_weeks','player_weekly_gift_login_days')")" = "3"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"

test "$("$pg_bin/psql" -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('weekly_gift_reward_versions','player_weekly_gift_weeks','player_weekly_gift_login_days')")" = "0"

echo "V14 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
