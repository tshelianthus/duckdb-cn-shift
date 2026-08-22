# sql/ — primary delivery (SQL macros)

This directory is the **preferred cnshift deliverable**.

| File | Role |
| :--- | :--- |
| `cnshift.sql` | Bootstrap macros (point `STRUCT(lat, lon)` + `GEOMETRY` overloads) |

## Usage

User-facing steps live in the root [README.md](../README.md) “How to use”: copy/clone `sql/cnshift.sql` → `LOAD spatial` → CLI `.read` or execute the file as a script. **No `make`.**

```sql
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql'

SELECT wgs84_to_gcj02(31.2304, 121.4737);
SELECT wgs84_to_gcj02(geom) FROM parcels;
```

Vertex walks for lines / polygons / Multi* / flat GeometryCollection stay inside the macros; callers must not `ST_Dump` themselves.

Merged script for in-memory / Metabase per-connection init: `bash sql/build-init-memory.sh` → `sql/init-memory.sql` (see [docs/metabase.md](../docs/metabase.md)).

## Tests

From the repo root:

```bash
bash test/sql/run_sql_track.sh
```

Expectations come from [`testdata/golden/`](../testdata/golden/).

## Implementation constraints

- **Algorithm constants / formulae**: only back-reference [`docs/ALGORITHM.md`](../docs/ALGORITHM.md); do not maintain a second constant table here.
- **Product decisions / intentional divergences**: [`docs/DECISIONS.md`](../docs/DECISIONS.md) (Multi* uses `ST_Collect` / `ST_Multi`, not `ST_Union`).
- **CGCS2000**: no same-named API; `ST_Transform` to EPSG:4326 first.
- **No community submit**: private distribution; do not PR to `duckdb/community-extensions`.
- Version tags: `sql-v*` (see [`docs/VERSIONING.md`](../docs/VERSIONING.md)).
