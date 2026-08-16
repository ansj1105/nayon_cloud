#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v6.XXXXXX)"
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

test -f "$repo_dir/db/migration/V6__create_player_settings_and_share_reward.sql"
test -f "$repo_dir/db/rollback/U6__drop_player_settings_and_share_reward.sql"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in 1 2 3 4 5; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 \
  -f "$repo_dir/db/migration/V6__create_player_settings_and_share_reward.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values
  ('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A'),
  ('00000000-0000-0000-0000-000000000002', 'NYAON-TEST-0002', 'ACTIVE', 'B');

insert into player_settings(account_id, language_code)
values ('00000000-0000-0000-0000-000000000001', 'ko');

insert into player_share_rewards(id, account_id, shared, shared_at)
values ('00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000001', true, now());

do $$
begin
  begin
    update player_share_rewards
       set reward_claimed = true,
           reward_claimed_at = now(),
           shared = false,
           shared_at = null
     where account_id = '00000000-0000-0000-0000-000000000001';
    raise exception 'reward without share accepted';
  exception when check_violation then null;
  end;

  begin
    insert into player_settings(account_id, language_code)
    values ('00000000-0000-0000-0000-000000000001', 'xx');
    raise exception 'unsupported language accepted';
  exception when check_violation then null;
  end;

  begin
    insert into player_settings(account_id, language_code)
    values ('00000000-0000-0000-0000-000000000001', 'en');
    raise exception 'duplicate settings account accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into player_share_rewards(id, account_id)
    values ('00000000-0000-0000-0000-000000000102',
        '00000000-0000-0000-0000-000000000001');
    raise exception 'duplicate share reward account accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into player_share_rewards(id, account_id)
    values ('00000000-0000-0000-0000-000000000101',
        '00000000-0000-0000-0000-000000000002');
    raise exception 'duplicate share reward id accepted';
  exception when unique_violation then null;
  end;
end
$$;
SQL

test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('player_settings', 'player_share_rewards')")" = "2"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'player_settings'")" = "11"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'player_share_rewards'")" = "9"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 \
  -f "$repo_dir/db/rollback/U6__drop_player_settings_and_share_reward.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('player_settings', 'player_share_rewards')")" = "0"

echo "V6 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
