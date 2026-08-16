#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pg_bin="${PG_BIN:-/home/ubuntu/work/.tools/postgresql/16.3/bin}"
work_dir="$(mktemp -d /tmp/nayon-cloud-v8.XXXXXX)"
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
for version in 1 2 3 4 5 6 7; do
  migration="$(find "$repo_dir/db/migration" -maxdepth 1 -name "V${version}__*.sql" -print -quit)"
  test -n "$migration"
  "$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
done

up_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/migration/V8__create_legal_documents.sql" >/dev/null
up_finished="$(date +%s%N)"

"$pg_bin/psql" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into legal_documents(id, document_type, locale, version, title, content, effective_at, active)
values ('00000000-0000-0000-0000-000000000801', 'PRIVACY_POLICY', 'ko', 'test-v1',
        '테스트 개인정보 처리방침', '검증 전용 본문', now(), true);

do $$
begin
  begin
    insert into legal_documents(id, document_type, locale, version, title, content, effective_at, active)
    values ('00000000-0000-0000-0000-000000000802', 'PRIVACY_POLICY', 'ko', 'test-v2',
            '중복 활성 문서', '검증 전용 본문', now(), true);
    raise exception 'duplicate active legal document accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into legal_documents(id, document_type, locale, version, title, content, effective_at, active)
    values ('00000000-0000-0000-0000-000000000803', 'UNKNOWN', 'ko', 'test-v1',
            '잘못된 유형', '검증 전용 본문', now(), false);
    raise exception 'unknown legal document type accepted';
  exception when check_violation then null;
  end;

  begin
    insert into legal_documents(id, document_type, locale, version, title, content, effective_at, active)
    values ('00000000-0000-0000-0000-000000000804', 'TERMS_OF_SERVICE', 'KO', 'test-v1',
            '잘못된 로케일', '검증 전용 본문', now(), false);
    raise exception 'non-normalized locale accepted';
  exception when check_violation then null;
  end;
end
$$;
SQL

test "$($pg_bin/psql -Atqc "select count(*) from legal_documents where active")" = "1"

down_started="$(date +%s%N)"
"$pg_bin/psql" -v ON_ERROR_STOP=1 -f "$repo_dir/db/rollback/U8__drop_legal_documents.sql" >/dev/null
down_finished="$(date +%s%N)"
test "$($pg_bin/psql -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name='legal_documents'")" = "0"

echo "V8 verification PASS forward_ms=$(((up_finished-up_started)/1000000)) rollback_ms=$(((down_finished-down_started)/1000000))"
