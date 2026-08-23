# SQL bootstrap (injection)

Primary delivery is `sql/cnshift.sql`. Users only need DuckDB + official `spatial` — **no `make` / no build of this repo**.

Each new session (or first init of a persistent DB), in order:

```sql
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql'   -- DuckDB CLI; path relative to cwd, or absolute
```

Other clients have no `.read`. Python / R / Java / Go / Node.js / ODBC / C / Rust / Wasm / ADBC / C# / C++ examples (official Client Overview order) are in the root [README.md](../README.md) “How to use” section (in-page anchors; GitHub has no tab UI). Or CLI-inject into `analysis.duckdb`, then open that file from any language.

## Notes

- **`spatial` is required** (official DuckDB core extension). Without `LOAD spatial`, geometry overloads and construct/decompose functions are unavailable.
- Macros register in the current database catalog; a persistent `.duckdb` can reuse them after one injection; in-memory DBs usually need injection every session.
- **Do not** ask users to `ST_Dump` / loop vertices themselves; that stays inside the script.
- This repo does **not** offer `INSTALL cnshift FROM community` (legal/compliance: not submitted to community). See [`DECISIONS.md`](DECISIONS.md).

## Smoke examples

```sql
SELECT wgs84_to_gcj02(31.2304, 121.4737);
SELECT wgs84_to_gcj02(ST_Point(121.4737, 31.2304));
SELECT wgs84_to_gcj02(geom) FROM parcels;
```

Point overload argument order is `(lat, lon)`, returns `STRUCT(lat, lon)`. Geometry overload only changes XY (X=lon, Y=lat).

Invalid lat/lon (out of range / NaN / Inf) → point overload returns `NULL` (macros cannot throw). Outside the China bbox, that stage is identity (including BD). GCJ→WGS is one-shot `2p - forward(p)`.

**CGCS2000**: no same-named functions; `ST_Transform(..., 'EPSG:4326')` first, then this library.

Golden tests: `bash test/sql/run_sql_track.sh` ([`testdata/golden/`](../testdata/golden/)).

Version tags: [`VERSIONING.md`](VERSIONING.md).
