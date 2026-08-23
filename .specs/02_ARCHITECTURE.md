# Architecture Specification

## 1. Product shape (dual-track, same repo)

| Track | Artifact | Status |
| :--- | :--- | :--- |
| **Primary path** | `sql/cnshift.sql` + [`docs/bootstrap.md`](../docs/bootstrap.md) | Implement first |
| **Fallback** | `ext/` → `cnshift.duckdb_extension` | Planned (README only for now) |

Both are privately distributed with engineering quality aligned to community standards; **not listed** on community-extensions ([`docs/DECISIONS.md`](../docs/DECISIONS.md)).

## 2. Why this maps to pg-coordtransform

| pg-coordtransform | cnshift (DuckDB) |
| :--- | :--- |
| `geoc-pg-coordtransform.sql` | `sql/cnshift.sql` |
| `LANGUAGE plpgsql` + `FOR … ST_Dump` | `CREATE MACRO` + `list_transform` / `ST_Dump` / `unnest` |
| Depends on PostGIS | Depends on DuckDB `spatial` |
| `geoc_wgs84togcj02(geom)` | `wgs84_to_gcj02` (with geoc_* mapping) |
| Multi via `ST_Union` | **Intentional deviation**: `ST_Collect` / `ST_Multi` |

User path: `startup inject → SELECT f(geom)`; intermediate loops must not appear in primary user docs.

## 3. Layering inside `cnshift.sql`

1. **Kernel**: bbox, `transform_lat/lon`, `delta`, WGS↔GCJ, GCJ↔BD, SHCS2000 projections.
2. **Point glue**: `STRUCT(lat,lon)`; geometry Point ↔ `ST_X`/`ST_Y`.
3. **Vertex map**: LineString → `generate_series` / `ST_PointN` / `ST_MakeLine`.
4. **Ring / Polygon**: `ST_ExteriorRing` / `ST_Boundary`→`ST_Dump` → `ST_MakePolygon(shell, holes[])` (polygons with holes are a required capability, not “SQL can’t do holes”).
5. **Multi / Collection**: `ST_Dump` → part macros → `ST_Collect` / `ST_Multi`; flat Collection; nested may be limited depth or left to C++.
6. **Dispatch**: `ST_GeometryType` branching.

No recursive macros; Multi/Collection apply `list_transform` over already-defined part macros.

## 4. Directory Layout (target)

```
duckdb-cn-shift/
├── .specs/
├── sql/
│   ├── README.md
│   └── cnshift.sql          # primary deliverable
├── ext/
│   └── README.md            # planned; do not add submodule before kickoff
├── testdata/golden/         # golden fixtures shared by SQL and C++
├── docs/
│   ├── DECISIONS.md
│   ├── bootstrap.md
│   ├── VERSIONING.md
│   └── CI.md
├── src/                     # legacy scaffold (not mainline); formal extension moves to ext/
├── test/sql/                # runner; expected values should come from testdata/golden
├── README.md
└── AGENTS.md
```

## 5. Testing

- Shared: `testdata/golden/` (points + geometry WKT).
- Points: in-China offset, outside identity, one-shot inverse, range checks.
- Geometry: polygons with holes, Multi* part count preserved (Collect), flat Collection.
- Harness: `LOAD spatial` first, then inject the macro script.
- CI: `sql/**` must not trigger the full C++ matrix (see `docs/CI.md`).

## 6. What we deliberately do not link

- Do not link GEOS/GDAL/PROJ in this repository.
- Spatial is provided by the official extension in the user’s environment.
- Do not submit to community-extensions.
