# Agent Execution Guidelines: duckdb-cn-shift

You are an expert systems engineer working on `duckdb-cn-shift` (China CRS offset transforms for DuckDB).

## 0. Product tracks (read decisions first)

- **Primary path**: SQL macros — `sql/cnshift.sql` + `INSTALL/LOAD spatial` + `.read` (see `docs/bootstrap.md`).
- **Fallback path**: C++ extension — `ext/src/` → `cnshift.duckdb_extension` (private / unsigned). Root `src/` is a pointer only.
- **No community submission**: This repository **does not** submit to `duckdb/community-extensions` (legal/compliance, not a technical reason). See `docs/DECISIONS.md`.
- **Sole algorithm source of truth**: `docs/ALGORITHM.md`. Implementations may only reference it; do not maintain separate constants.
- **Version tags**: `sql-v*` / `ext-v*` (`docs/VERSIONING.md`); no bare `v0.1.0`.
- **Languages**: Primary SQL deliverable is DuckDB SQL; extension track is **C++17**. Do not introduce Cargo/Rust. Do not self-link GEOS/GDAL/PROJ.

## 1. Core Principles

- **Strict Spec Adherence**: Before changing APIs, read `.specs/` and `docs/DECISIONS.md`. Function names/semantics follow `.specs/03_API_CONTRACT.md`.
- **SQL-first**: Keep the macro script usable; the C++ track is optional fallback, not a SQL-release blocker.
- **Shared goldens**: Point/geometry expectations live in `testdata/golden/`; SQL and C++ tests share them.
- **CI paths**: Changes under `sql/` should not trigger the full C++ platform matrix (`docs/CI.md`).
- **ext/ C++ track**: Formal sources are `ext/src/`. Root `CMakeLists.txt` / `Makefile` / submodules stay at repo root for `extension-ci-tools`. `git submodule update --init --recursive` is required to **build** the extension; do not pull submodules just to edit SQL docs.
- **Zero Panic** (C++ track): No `abort`/UB/uncaught exceptions; use DuckDB exception types.
- **Vectorized First** (C++ track): `UnaryExecutor`/`BinaryExecutor`, etc.; do not implement batch processing with per-row scalar loops.
- **TDD**: Features land with `.test` / goldens in sync.
- **Do not copy pintail Geohash/WKB business code**.

## 2. Naming

- Repo: `duckdb-cn-shift`
- Public functions: `wgs84_to_gcj02`, etc. (document `geoc_*` mapping as needed)
- Extension name (fallback): `cnshift` → `LOAD cnshift;` → `cnshift.duckdb_extension`

## 3. Essential commands

**SQL track (primary)**

```sql
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql'
```

**C++ track (fallback)**

- `git submodule update --init --recursive`
- `make debug` / `make test_debug`
- `make format-check` / `make tidy-check` (same as `duckdb/extension-template`)
- Private `LOAD`: see `ext/README.md` (`allow_unsigned_extensions`; never `FROM community`)
