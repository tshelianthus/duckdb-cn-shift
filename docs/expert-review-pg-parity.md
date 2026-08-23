# cnshift Implementation Expert Review Report

> **Status (2026-08-23)**: Expert decisions **landed** → see authoritative docs [`docs/DECISIONS.md`](DECISIONS.md).  
> This document is retained as a review-process archive; where it conflicts with DECISIONS, DECISIONS wins.  
> **Rejected risk**: R1 below (“SQL cannot reliably rebuild polygons with holes”) — the decision board concluded Spatial’s `ST_MakePolygon(shell, holes[])` + `ST_Boundary` / `ST_Dump` / `ST_ExteriorRing` paths are acceptable; **do not** use “SQL can’t handle holes” as the default go/no-go for switching to C++.

**Original status**: Pending review (closed)  
**Date**: 2026-08-22  
**Repository**: `duckdb-cn-shift`  
**Related specs**: `.specs/01_PRD.md`, `.specs/02_ARCHITECTURE.md`, `.specs/03_API_CONTRACT.md`; decisions in `docs/DECISIONS.md`

---

## 1. Review purpose

Product decisions:

1. **Do not** join DuckDB Community Extensions (control distribution surface).
2. **Must** support points / lines / polygons / multi-part; caller UX: `SELECT wgs84_to_gcj02(geom)` — do not require users to dump→transform points→loop→rebuild themselves.
3. Engineering-wise, optimize SQL macro function layering and behavior.

This report is for expert review: **which technical path should implement equivalent UX on DuckDB**, and **which PG behaviors must be 1:1 replicas versus intentional deviations**.

---

## 2. Benchmark breakdown (pg-coordtransform)

### 2.1 Distribution model

| Item | pg-coordtransform |
| :--- | :--- |
| Deliverable | Single file `geoc-pg-coordtransform.sql` |
| Install | Install PostGIS → execute the whole file |
| Language | `LANGUAGE plpgsql` |
| No `.so` | Yes |

### 2.2 Function layering (structure worth imitating)

```text
Public entry (dispatch by ST_GeometryType)
  ├─ *_point        ← offset formula kernel
  ├─ *_line         ← while i ≤ ST_NPoints: ST_PointN → transform point → ST_SetPoint
  ├─ *_polygon      ← ST_DumpRings → drop closing vertex → treat as line → re-close → ST_MakePolygon(shell, holes[])
  ├─ *_multipoint / *_multiline / *_multipolygon
  │                 ← ST_Dump parts → transform → ST_Multi(ST_Union(parts))
  └─ ELSE → NULL    ← including GeometryCollection: NULL directly
```

Point kernel isomorphic to common open-source formulas:

- `geoc_transform_lon` / `geoc_transform_lat`
- `geoc_delta` (ellipsoid approximation coeffs `a=6378245`, `ee=0.006693421622965823`)
- `geoc_is_in_china_bbox`: `lon∈[72.004, 137.8347]` ∧ `lat∈[0.8293, 55.8271]`
- GCJ→WGS: **one-shot** approximate `2p - forward(p)` (not iterative)
- GCJ↔BD: polar rotation + constants `0.0065 / 0.006`

### 2.3 PG behavior details that must enter the contract

| # | Behavior | Source fact | Implication for this project |
| :---: | :--- | :--- | :--- |
| A | Geometry entry requires SRID ∈ {4326, 4490}, otherwise **returns NULL** | Each `geoc_*` entry | Copy “silent NULL” or switch to throwing? |
| B | **GeometryCollection unsupported** (ELSE → NULL) | `CASE … ELSE RETURN null` | Draft contract mentioned Collection; inconsistent with PG — pick one |
| C | Multi* rebuild uses `ST_Multi(ST_Union(parts))` | multiline / multipolygon | `ST_Union` may merge touching parts and change topology; **faithful imitation inherits that pitfall** |
| D | Polygon uses `ST_DumpRings` + drop closing vertex then treat as line | `*_polygon` | DuckDB Spatial has **no** `ST_DumpRings` / `ST_InteriorRingN`; SQL path needs an equivalent and proof |
| E | Outside bbox also applied in **BD point functions** | `geoc_gcj02tobd09_point` etc. | Conflicts with some “BD segment applies globally” docs; recommend **follow PG** |
| F | CGCS2000 = `ST_Transform` wrapper, no separate offset formula | `geoc_cgcs2000to*` | This library may omit same-name functions; document transform to 4326 first |
| G | XY only; lines/polygons = per-vertex empirical offset | All | **Does not guarantee** topology preservation, seamlessness, or no self-intersections |

### 2.4 UX benchmark (non-negotiable)

```sql
-- PostGIS
SELECT geoc_wgs84togcj02(geom) FROM parcels;
```

Equivalent goal:

```sql
-- DuckDB (target)
LOAD spatial;
-- inject cnshift once
SELECT wgs84_to_gcj02(geom) FROM parcels;
```

User docs **must not** present “please ST_Dump / write your own loop” as the primary path.

---

## 3. DuckDB constraints (review premises)

| Constraint | Impact |
| :--- | :--- |
| No plpgsql / no procedural `WHILE` | Cannot port line/polygon function bodies verbatim |
| `CREATE MACRO` **forbids recursion** | Multi / Collection cannot self-call the entry macro |
| DuckDB Spatial function set ≠ PostGIS | Missing `ST_DumpRings` etc.; ring decomposition needs verified equivalents |
| v1.5+: `GEOMETRY` is a core type | C++ extension can declare `GEOMETRY` without linking Spatial; SQL macro path still depends on Spatial construct/decompose functions |
| Not on community | No signed `INSTALL FROM community`; choose SQL inject or a custom unsigned repo |

---

## 4. Candidate implementation paths

### Path A — Pure SQL macros (current `.specs` v0.2 mainline)

**Shape**: `sql/cnshift.sql` + startup inject `INSTALL/LOAD spatial` + `.read cnshift.sql`.

**Layering suggestion (align with PG)**:

1. Kernel: `cn__china_bbox` / `cn__transform_lon|lat` / `cn__delta` / six point transforms  
2. Point glue: `STRUCT(lat,lon)` + `ST_Point` / `ST_X`/`ST_Y`  
3. Line: `generate_series` + `ST_PointN` + `ST_MakeLine` (or `list_transform`)  
4. Polygon: `ST_Boundary` → `ST_Dump` → first ring shell, rest holes → `ST_MakePolygon` (**to be proven**)  
5. Multi: `ST_Dump` → `list_transform` over **already-defined non-recursive part macros** → `ST_Collect` / `ST_Multi`  
6. Dispatch: `ST_GeometryType` branches  

**Pros**: Distribution model closest to PG; no unsigned extensions; works in CLI / DBeaver / Python / WASM; distribution surface relatively controllable when not on community.  
**Risks**: Whether polygons-with-holes / MultiPolygon / Collection can **correctly rebuild type and ring order** on Spatial is unproven; macro expression bloat; weaker performance than C++; same-name point/geometry overloads may force `*_geom` splits.

### Path B — C++ extension (GEOMETRY overload as primary path)

**Shape**: `cnshift.duckdb_extension`; internal “visit XY → rebuild by type” like PG; six public names with `(lat,lon)` and `(GEOMETRY)` overloads.

**Pros**: Strongest control for lines/polygons; can precisely avoid `ST_Union` merge traps; easier type fidelity and Z/M policy; best performance.  
**Risks**: Distribution needs a custom repo or hand-shipped binaries + `allow_unsigned_extensions`; higher barrier than `.sql` for ordinary users; combined with “not on community,” UX is a step worse.

### Path C — Hybrid (recommended for expert decision)

| Layer | Choice |
| :--- | :--- |
| External UX | Align with PG: one function takes geom |
| MVP delivery | **Path A** first for points + LineString + simple Polygon; validate ring path with golden geometries |
| Hard gate | ~~If holes cannot be faithful, escalate to B~~ **That default gate is rejected**; holes are required for SQL. C++ remains a fallback (performance / deep nested Collection, etc.) |
| Formulas | Kernel **numeric behavior** aligned with pg `geoc_delta` / transform / BD constants (including bbox, one-shot inverse) |
| Multi rebuild | **Default: do not copy** `ST_Union`; use part collection (`ST_Collect`/`ST_Multi`) and document “intentional deviation from PG to avoid part merging” |

---

## 5. Behavior-fidelity decision table (for expert checkmarks)

| Topic | Option 1: follow PG | Option 2: intentional improvement | Suggested default |
| :--- | :--- | :--- | :--- |
| SRID not 4326/4490 | Return NULL | Throw | Follow PG (NULL) or documented throw — needs decision |
| GeometryCollection | Return NULL | Recursively convert children | **Improve**: support Collection (unless deliberately preserving the PG pitfall) |
| Multi* rebuild | `ST_Union` | `ST_Collect` preserve parts | **Improve**: Collect |
| BD segment outside bbox | BD points also use bbox | BD offsets globally | **Follow PG** (bbox) |
| GCJ→WGS | One-shot `2p-f(p)` | Multi-iteration | **Follow PG** |
| Illegal lat/lon | PG geometry path rarely validates | Point overload throws/NULL | Points: error or NULL; geometry: per vertex |
| CGCS2000 same-name functions | Implement ST_Transform wrappers | Docs only | **Docs only** (smaller API surface) |
| Function naming | `geoc_wgs84togcj02` | `wgs84_to_gcj02` | Keep contract snake names; document PG mapping table |

---

## 6. Proposed target API (review draft)

### 6.1 Public surface

Six conversion names, each supporting:

- `f(lat DOUBLE, lon DOUBLE) → STRUCT(lat, lon)`
- `f(geom GEOMETRY) → GEOMETRY` (type-preserving)

Geometry type matrix: **POINT / LINESTRING / POLYGON (with holes) / MULTIPOINT / MULTILINESTRING / MULTIPOLYGON**; Collection per §5 decision.

### 6.2 Startup inject (Path A)

```sql
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql';
```

### 6.3 Non-goals

- Community `INSTALL … FROM community`
- Self-linking GEOS/GDAL/PROJ
- User-written vertex loops
- Topology-preservation promises
- Rigorous CGCS2000 / projection transforms

---

## 7. Verification & acceptance (experts may edit thresholds)

### 7.1 Numeric alignment

- Points: Shanghai / Beijing WGS→GCJ / GCJ→BD vs pg-coordtransform on **same inputs** (suggest `round(..., 7)` or agreed tolerance).
- GCJ→WGS: align with PG’s one-shot approximate result; do not hard-align with “iterative inverse” libraries.

### 7.2 Geometry type matrix

For each supported type at least:

1. In-China geometry: output type unchanged; vertices show observable offset vs input.  
2. Outside points / outside vertices: WGS↔GCJ segment matches bbox identity.  
3. Polygon with holes: holes remain holes; shell/hole vertex counts unchanged (document closing strategy).  
4. MultiPolygon: part count unchanged (if using Collect rather than Union).  
5. NULL / empty geometry.

### 7.3 Regression comparison method

Same WKT inputs:

1. PostGIS + pg-coordtransform → result WKT  
2. DuckDB + cnshift → result WKT  
3. Vertex-level diff (allow float tolerance)

---

## 8. Risk register

| ID | Risk | Severity | Mitigation |
| :--- | :--- | :---: | :--- |
| R1 | ~~DuckDB cannot reliably rebuild polygons with holes (SQL)~~ **Rejected** | ~~High~~ | Decision: use Spatial `ST_MakePolygon` + Boundary/Dump/ExteriorRing; holes are a SQL must-have — see DECISIONS ADR-008 |
| R2 | Copying `ST_Union` merges Multi parts | Medium | Default Collect; document the deviation |
| R3 | Macros cannot overload same name for point/geometry | Low | `*_geom` suffix or single geom entry + STRUCT for points |
| R4 | Spatial function differences across versions | Medium | Pin DuckDB version; CI Spatial smoke |
| R5 | SQL script distribution surface still large | Medium | Private / intranet distribution; stay off community |
| R6 | C++ path install friction for ordinary users | High | Only if R1 triggered; or internal prebuilt repo |

---

## 9. Questions requiring explicit expert answers

1. **Primary deliverable**: insist on “single-file SQL inject” like PG, or accept “C++ extension + prebuilts” to guarantee line/polygon correctness?  
2. **Multi rebuild**: agree **not** to replicate `ST_Union`, and use part-preserving Collect instead?  
3. **GeometryCollection**: follow PG (NULL), or support it?  
4. **BD + China bbox**: force consistency with pg source (BD points also use bbox)?  
5. **SRID checks**: NULL vs error?  
6. **Failure fallback**: if a SQL spike fails hole-polygon acceptance, authorize immediate Path B without further macro complexity?  
7. **Naming**: is `wgs84_to_gcj02` acceptable externally (with PG `geoc_*` mapping), or must names be identical for compatibility?

---

## 10. Suggested conclusion (for oppose / approve)

**Product UX must imitate PG (one function, lines/polygons built in). Numeric, bbox, and inverse strategies should imitate PG source. Multi `ST_Union` and Collection=NULL are recommended intentional improvements, called out in comparison tests.**

**Engineering (decision-board revision)**: Path A (SQL) is the preferred deliverable; polygons with holes are a **SQL must-have**, not a default trigger to Path B. Path B is a deferred fallback.

## Appendix A — Public function mapping

| Legacy format | Modern cnshift |
| :--- | :--- |
| `geoc_wgs84togcj02` | `wgs84_to_gcj02` |
| `geoc_gcj02towgs84` | `gcj02_to_wgs84` |
| `geoc_gcj02tobd09` | `gcj02_to_bd09` |
| `geoc_bd09togcj02` | `bd09_to_gcj02` |
| `geoc_wgs84tobd09` | `wgs84_to_bd09` |
| `geoc_bd09towgs84` | `bd09_to_wgs84` |
| `geoc_cgcs2000to*` / `*tocgcs2000` | Not implemented; docs: `ST_Transform` → 4326 then call |

## Appendix B — Document status

- Authoritative: `docs/DECISIONS.md`, `.specs/03_API_CONTRACT.md`
