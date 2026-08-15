#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
migration="$repo_dir/db/migration/V1__create_player_account_and_save.sql"
rollback="$repo_dir/db/rollback/U1__drop_player_account_and_save.sql"

test -f "$migration"
test -f "$rollback"

work_dir="$(mktemp -d /tmp/nayon-cloud-v1.XXXXXX)"
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

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into player_accounts(id, public_id, status, nickname)
values ('00000000-0000-0000-0000-000000000001', 'NYAON-TEST-0001', 'ACTIVE', 'A');

insert into auth_identities(id, account_id, provider, provider_subject)
values ('00000000-0000-0000-0000-000000000011',
        '00000000-0000-0000-0000-000000000001', 'GOOGLE', 'subject-a');

insert into player_save_states(account_id, schema_version, revision, payload, checksum, client_build)
values ('00000000-0000-0000-0000-000000000001', 1, 0, '{}'::jsonb,
        repeat('a', 64), 'test-build');

select result from save_imports where false;

do $$
begin
  begin
    insert into auth_identities(id, account_id, provider, provider_subject)
    values ('00000000-0000-0000-0000-000000000012',
            '00000000-0000-0000-0000-000000000001', 'GOOGLE', 'subject-a');
    raise exception 'duplicate provider subject was accepted';
  exception
    when unique_violation then null;
  end;

  begin
    update player_save_states set revision = -1
     where account_id = '00000000-0000-0000-0000-000000000001';
    raise exception 'negative revision was accepted';
  exception
    when check_violation then null;
  end;
end
$$;
SQL

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$rollback" >/dev/null
down_finished="$(date +%s%N)"

remaining="$($pg_bin/psql -Atqc "select count(*) from pg_class where relkind = 'r' and relname in ('player_accounts', 'auth_identities', 'player_save_states', 'save_imports')")"
test "$remaining" = "0"

up_ms="$(((up_finished - up_started) / 1000000))"
down_ms="$(((down_finished - down_started) / 1000000))"
echo "V1 verification PASS forward_ms=$up_ms rollback_ms=$down_ms"
