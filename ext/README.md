# ext/ — C++ extension (fallback / private binary)

**Status: implemented (private distribution).** This is **not** the product main path. Prefer [`sql/cnshift.sql`](../sql/cnshift.sql) + `LOAD spatial` unless you need a loadable `cnshift.duckdb_extension`.

- Product decisions, dual-track, **no community submit**: [`docs/DECISIONS.md`](../docs/DECISIONS.md) (ADR-001 / ADR-002 / ADR-009).
- Public SQL surface: [`.specs/03_API_CONTRACT.md`](../.specs/03_API_CONTRACT.md).
- Version tags: **`ext-v*`** only (e.g. `ext-v0.1.0`). Do **not** use a bare `v0.1.0`. See [`docs/VERSIONING.md`](../docs/VERSIONING.md).
- Shared goldens: [`testdata/golden/`](../testdata/golden/) (same fixtures as the SQL track).

Do **not** open PRs against [`duckdb/community-extensions`](https://github.com/duckdb/community-extensions) (legal/compliance boundary, not a technical gap). There is no `INSTALL cnshift FROM community`.

## Download a prebuilt binary (no `make`)

Current CI builds against **DuckDB v1.5.5**. After maintainers push an `ext-v*` tag, unsigned binaries are attached to that [GitHub Release](https://github.com/tshelianthus/duckdb-cn-shift/releases).

Asset names:

```text
cnshift-ext-v0.1.0-duckdb-v1.5.5-osx_arm64.duckdb_extension
cnshift-ext-v0.1.0-duckdb-v1.5.5-linux_amd64.duckdb_extension
# Wasm: …-wasm_mvp.duckdb_extension.wasm
```

1. Confirm the client: `SELECT version();` must be **v1.5.5** for these assets, and `PRAGMA platform;` must match `<arch>`.
2. Download the matching file from the `ext-v*` release (not from GitHub Actions artifacts — those expire). Each release also has a `SHA256SUMS` file.
3. `LOAD` it as an unsigned extension (next section).

| OS / CPU | `<arch>` |
| :--- | :--- |
| macOS Apple Silicon | `osx_arm64` |
| macOS Intel | `osx_amd64` |
| Linux x86_64 (glibc) | `linux_amd64` |
| Linux aarch64 (glibc) | `linux_arm64` |
| Windows x64 (MSVC) | `windows_amd64` |
| Windows x64 (MinGW) | `windows_amd64_mingw` |
| DuckDB Wasm | `wasm_mvp` / `wasm_eh` / `wasm_threads` |

If your DuckDB version or platform is not in the Release, use [Build from source](#build-from-source) instead. Do not scrape workflow artifacts.

## Private install (`allow_unsigned_extensions`)

Binaries from this repo are **unsigned**. DuckDB will refuse them unless unsigned extensions are allowed.

CLI:

```bash
duckdb -unsigned
```

```sql
LOAD '/abs/path/cnshift-ext-v0.1.0-duckdb-v1.5.5-osx_arm64.duckdb_extension';
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

Self-hosted drop layout (if you mirror files yourself, not required for GitHub Releases):

```text
{duckdb_version}/{platform}/cnshift.duckdb_extension[.gz]
# example:
# v1.5.5/osx_arm64/cnshift.duckdb_extension
# v1.5.5/linux_amd64/cnshift.duckdb_extension.gz
```

`platform` matches DuckDB extension-ci-tools names (`linux_amd64`, `linux_arm64`, `osx_amd64`, `osx_arm64`, `windows_amd64`, …). Gzip is optional.

## Build from source

For contributors, or when no Release asset matches your DuckDB version / platform:

```bash
git submodule update --init --recursive
make debug          # or: make release
make test_debug     # or: make test_release
make format-check   # clang-format 11; same as community template
make tidy-check     # clang-tidy; same as community template
```

Artifact (after release): `build/release/extension/cnshift/cnshift.duckdb_extension`. Then `LOAD` it with the unsigned flag above.

The six point functions have **no GIS link** (no GEOS / GDAL / PROJ). `GEOMETRY` overloads use DuckDB 1.5 core `GEOMETRY` (little-endian ISO WKB). SQLLogicTests also use core WKT casts, so `make test_debug` does not build `spatial`. `LOAD spatial` is only needed if you want `ST_*` helpers at runtime.

## Layout

| Path | Role |
| :--- | :--- |
| `ext/src/` | C++17 sources (kernel, WKB geometry, function registration) |
| `src/include/cnshift_extension.hpp` | DuckDB codegen glue (`Extension` class only — not a second algorithm) |
| Root `CMakeLists.txt` / `Makefile` / `vcpkg.json` / `extension_config.cmake` | Required by `extension-ci-tools` at repo root |
| Root `src/README.md` | Pointer only — **not** a second implementation |
| `test/sql/*.test` | SQLLogicTest; reads `testdata/golden/` |
| `duckdb/`, `extension-ci-tools/` | Submodules (DuckDB **v1.5.5**, ci-tools **v1.5-variegata**) |

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

After merge to **`main`**, tag **`ext-v0.1.0`** (or the next `ext-v*`) on that commit and push the tag. Never tag a product release as bare `v0.1.0`. Do **not** tag `dev` or a feature branch: the release workflow refuses to publish unless the commit is already on `origin/main`. Pushing a valid tag runs [`.github/workflows/ext-github-release.yml`](../.github/workflows/ext-github-release.yml) and attaches the binaries to a GitHub Release.
