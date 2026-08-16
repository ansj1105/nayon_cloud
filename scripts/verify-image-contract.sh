#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dockerfile="$repo_root/Dockerfile"

test -f "$dockerfile"
grep -Eq '^FROM flyway/flyway:[^ ]+-alpine$' "$dockerfile"
grep -Fq 'COPY db/migration /flyway/sql' "$dockerfile"

echo "nayon_cloud image contract verified"
