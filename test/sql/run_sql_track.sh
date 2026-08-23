#!/usr/bin/env bash
# Run SQL-track golden tests from the repository root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
if ! command -v duckdb >/dev/null 2>&1; then
	echo "duckdb CLI not found on PATH" >&2
	exit 127
fi
exec duckdb -bail < test/sql/sql_track.test.sql
