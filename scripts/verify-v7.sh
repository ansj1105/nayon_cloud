#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v7.XXXXXX)"
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

test -f "$repo_dir/db/migration/V7__create_korion_wallet_links.sql"
test -f "$repo_dir/db/rollback/U7__drop_korion_wallet_links.sql"

"$pg_bin/initdb" -D "$data_dir" -A trust -U postgres >/dev/null
"$pg_bin/pg_ctl" -D "$data_dir" -o "-F -k $socket_dir -h ''" -w start >/dev/null
export PGHOST="$socket_dir" PGUSER=postgres PGDATABASE=postgres
for version in 1 2 3 4 5 6; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/migration/V7__create_korion_wallet_links.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values
  ('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A'),
  ('00000000-0000-0000-0000-000000000002', 'NYAON-TEST-0002', 'ACTIVE', 'B');

insert into korion_wallet_link_requests(id, account_id, address, status, expires_at)
values ('00000000-0000-0000-0000-000000000101',
        '00000000-0000-0000-0000-000000000001',
        'TTestWalletAddress111111111111111111', 'PENDING', now() + interval '10 minutes');

do $$
begin
  begin
    insert into korion_wallet_link_requests(id, account_id, address, status, expires_at)
    values ('00000000-0000-0000-0000-000000000102',
            '00000000-0000-0000-0000-000000000001',
            'TTestWalletAddress222222222222222222', 'PENDING', now() + interval '10 minutes');
    raise exception 'duplicate pending account accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into player_korion_wallet_links(account_id, address, verified_request_id, verified_at)
    values ('00000000-0000-0000-0000-000000000002',
            'TTestWalletAddress111111111111111111',
            '00000000-0000-0000-0000-000000000101', now());
    raise exception 'cross-account verified request accepted';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into player_account_link_rewards(id, account_id, reward_claimed, reward_claimed_at)
    values ('00000000-0000-0000-0000-000000000201',
            '00000000-0000-0000-0000-000000000001', false, now());
    raise exception 'unclaimed reward timestamp accepted';
  exception when check_violation then null;
  end;
end
$$;

update korion_wallet_link_requests
set status = 'APPROVED', completed_at = now(), updated_at = now()
where id = '00000000-0000-0000-0000-000000000101';

insert into player_korion_wallet_links(account_id, address, verified_request_id, verified_at)
values ('00000000-0000-0000-0000-000000000001',
        'TTestWalletAddress111111111111111111',
        '00000000-0000-0000-0000-000000000101', now());

insert into player_account_link_rewards(id, account_id)
values ('00000000-0000-0000-0000-000000000201',
        '00000000-0000-0000-0000-000000000001');
SQL

test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('korion_wallet_link_requests','player_korion_wallet_links','player_account_link_rewards')")" = "3"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/rollback/U7__drop_korion_wallet_links.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('korion_wallet_link_requests','player_korion_wallet_links','player_account_link_rewards')")" = "0"

echo "V7 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
