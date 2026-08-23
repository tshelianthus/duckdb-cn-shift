# ext/ — C++ extension (fallback / private binary)

**Status: implemented (private distribution).** This is **not** the product main path. Prefer [`sql/cnshift.sql`](../sql/cnshift.sql) + `LOAD spatial` unless you need a loadable `cnshift.duckdb_extension`.

- Product decisions, dual-track, **no community submit**: [`docs/DECISIONS.md`](../docs/DECISIONS.md) (ADR-001 / ADR-002).
- Algorithm source of truth: [`docs/ALGORITHM.md`](../docs/ALGORITHM.md) (implementations must back-reference; no private constant tables).
- Public SQL surface: [`.specs/03_API_CONTRACT.md`](../.specs/03_API_CONTRACT.md).
- Version tags: **`ext-v*`** only (e.g. `ext-v0.1.0`). Do **not** use a bare `v0.1.0`. See [`docs/VERSIONING.md`](../docs/VERSIONING.md).
- Shared goldens: [`testdata/golden/`](../testdata/golden/) (same fixtures as the SQL track).

Do **not** open PRs against [`duckdb/community-extensions`](https://github.com/duckdb/community-extensions) (legal/compliance boundary, not a technical gap). There is no `INSTALL cnshift FROM community`.

## Layout

| Path | Role |
| :--- | :--- |
| `ext/src/` | C++17 sources (kernel, WKB geometry, function registration) |
| `src/include/cnshift_extension.hpp` | DuckDB codegen glue (`Extension` class only — not a second algorithm) |
| Root `CMakeLists.txt` / `Makefile` / `vcpkg.json` / `extension_config.cmake` | Required by `extension-ci-tools` at repo root |
| Root `src/README.md` | Pointer only — **not** a second implementation |
| `test/sql/*.test` | SQLLogicTest; reads `testdata/golden/` |
| `duckdb/`, `extension-ci-tools/` | Submodules (DuckDB **v1.5.5**, ci-tools **v1.5-variegata**) |

## Build

```bash
git submodule update --init --recursive
make debug          # or: make release
make test_debug     # or: make test_release
make format-check   # clang-format 11; same as community template
make tidy-check     # clang-tidy; same as community template
```

Artifact (after release): `build/release/extension/cnshift/cnshift.duckdb_extension`.

The six point functions have **no GIS link** (no GEOS / GDAL / PROJ). `GEOMETRY` overloads use DuckDB 1.5 core `GEOMETRY` (little-endian ISO WKB). SQLLogicTests also use core WKT casts, so `make test_debug` does not build `spatial`. `LOAD spatial` is only needed if you want `ST_*` helpers at runtime.

## Private install (`allow_unsigned_extensions`)

Binaries from this repo are **unsigned**. DuckDB will refuse them unless unsigned extensions are allowed. Layout for a self-hosted drop:

```text
{duckdb_version}/{platform}/cnshift.duckdb_extension[.gz]
# example:
# v1.5.5/osx_arm64/cnshift.duckdb_extension
# v1.5.5/linux_amd64/cnshift.duckdb_extension.gz
```

`platform` matches DuckDB extension-ci-tools names (`linux_amd64`, `linux_arm64`, `osx_amd64`, `osx_arm64`, `windows_amd64`, …). Gzip is optional.

CLI:

```bash
duckdb -unsigned
```

```sql
LOAD '/abs/path/v1.5.5/osx_arm64/cnshift.duckdb_extension';
SELECT wgs84_to_gcj02(31.2304, 121.4737);
SELECT wgs84_to_gcj02('POINT(121.4737 31.2304)'::GEOMETRY);
```

Python (and other clients):

```python
import duckdb
con = duckdb.connect(config={"allow_unsigned_extensions": "true"})
con.execute("LOAD '/abs/path/cnshift.duckdb_extension'")
con.execute("SELECT wgs84_to_gcj02(31.2304, 121.4737)").fetchall()
```

Persistent session flag:

```sql
SET allow_unsigned_extensions = true;
LOAD '/abs/path/cnshift.duckdb_extension';
```

Do **not** document `INSTALL cnshift FROM community`.

## Public functions

Same six names as the SQL track, with two overloads:

- `(lat DOUBLE, lon DOUBLE) → STRUCT(lat DOUBLE, lon DOUBLE)`
- `(GEOMETRY) → GEOMETRY` (type-preserving; Multi* parts are collected, never `ST_Union`)

Out-of-range / NaN / Inf on the **point** overload throws `OutOfRangeException` (the SQL macros return `NULL` because macros cannot throw). `NULL` arguments stay `NULL`. Outside the China bbox, that stage is identity (including BD). GCJ→WGS is one-shot `2p - forward(p)`.

CGCS2000: no same-named APIs.

## Tests

SQLLogicTest consumes **`testdata/golden/`** (not a forked expectation table):

- `test/sql/points_golden.test`
- `test/sql/geometry_golden.test` (core `GEOMETRY` / WKT; no `spatial` build dependency)

## Release tag

After merge to the release branch, tag **`ext-v0.1.0`** (or the next `ext-v*`). Never tag a product release as bare `v0.1.0`.
