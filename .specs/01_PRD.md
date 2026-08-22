# PRD: duckdb-cn-shift (cnshift)

## 1. Vision & Objectives

- **Target**: Provide China CRS offset conversion functions that can be called directly from DuckDB SQL.
- **Positioning**: Cover WGS-84 ↔ GCJ-02 (Mars coordinates) ↔ BD-09 (Baidu coordinates); support **points, lines, polygons, and multi-part geometries** with a one-function UX on par with `geocompass/pg-coordtransform`: `SELECT wgs84_to_gcj02(geom)` — callers do not dump vertices or write loops by hand.
- **Tech Stack (primary path)**: **Pure SQL `CREATE MACRO` + official `spatial` extension**. Formulas and geometry rebuild are delivered as `sql/cnshift.sql` (aligned with pg-coordtransform’s “copy SQL and run” distribution model).
- **Tech Stack (fallback)**: Same-repo C++ extension (`ext/`, planned) as a later option; engineering quality aligned with community standards, **private distribution**.
- **Distribution**: **Do not** submit to `duckdb/community-extensions` (**legal/compliance**, not a technical or quality limitation). See [`docs/DECISIONS.md`](../docs/DECISIONS.md).
- **Algorithm SoT**: [`docs/ALGORITHM.md`](../docs/ALGORITHM.md) is the sole algorithm source of truth; implementations must not maintain separate constants.
- **Naming**: Repo `duckdb-cn-shift`; public function names in `.specs/03_API_CONTRACT.md`; version tags `sql-v*` / `ext-v*` (see [`docs/VERSIONING.md`](../docs/VERSIONING.md)).

## 2. Rationale: Why SQL macros first (pg-coordtransform style)

- **UX alignment**: The PG solution’s value is “load once → convert lines/polygons directly.” DuckDB hides dump → transform points → rebuild inside macros via `CREATE MACRO` + Spatial.
- **Inject at startup**: `INSTALL/LOAD spatial` + `.read sql/cnshift.sql` (see [`docs/bootstrap.md`](../docs/bootstrap.md)).
- **Stay off community**: Reduces distribution surface and compliance risk; SQL is friendlier for CLI / Python / DBeaver / intranet use.
- **C++ later**: Ensure SQL works first, then offer the extension as a fallback (performance / nested Collections, etc.).

## 3. Dependency Strategy

| Tier | Scope | Dependencies |
| :--- | :--- | :--- |
| **Tier 0 (MVP / primary path)** | Point `(lat,lon)` STRUCT + `GEOMETRY` (Point/Line/Polygon/Multi*/flat Collection) | Official **`spatial`**. Do not self-link GEOS/GDAL/PROJ. CGCS2000: document that callers first `ST_Transform` to 4326. |
| **Tier 1 (fallback)** | Same-formula C++ extension | After `ext/` work starts; algorithm still points back to `ALGORITHM.md`. |

## 4. Target Persona & Use Cases

1. **Domestic GIS / location analysts**: Mixed parcel / road / POI tables; one SQL statement to align CRS.
2. **DuckDB / GeoParquet pipelines**: Inject macros via startup script, then apply offsets in SQL.
3. **Private-distribution users**: Receive `cnshift.sql` + bootstrap and go; no community `INSTALL` required.

## 5. Non-Goals (Scope Boundaries)

- **Do NOT** submit to or promote community install via `duckdb/community-extensions` (legal boundary; see DECISIONS).
- **Do NOT** implement rigorous surveying projections / CGCS2000 same-name APIs.
- **Do NOT** introduce GEOS/GDAL/PROJ link dependencies or Rust/Cargo.
- **Do NOT** require callers to dump / loop vertices themselves.
- **Do NOT** claim topology preservation or official surveying accuracy.
- **Do NOT** use bare `v0.1.0` to tag both SQL and extension (use `sql-v*` / `ext-v*`).
