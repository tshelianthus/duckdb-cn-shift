# API Contract Specification (v0.2.0 — SQL-first / dual-track)

The public SQL surface provides unified coordinate conversions for scalar points and `GEOMETRY` objects with single-function convenience; vertex traversal stays inside the implementation.

- **Fallback**: a C++ extension exposes the same surface with identical mathematical behavior.
- **Decisions**: [`docs/DECISIONS.md`](../docs/DECISIONS.md). Not listed on community.

---

## Bootstrap (one-time startup inject)

```sql
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql'
```

See [`docs/bootstrap.md`](../docs/bootstrap.md).

- `spatial` is a hard dependency.
- Do not require users to write dump / loops themselves.

---

## Return types

### A. Point-coordinate overload

```text
STRUCT(lat DOUBLE, lon DOUBLE)
```

Field order: `lat` then `lon`.

### B. Geometry overload

```text
GEOMETRY → GEOMETRY
```

- Output type matches input (including polygons with holes and Multi*).
- Only X/Y change (X=lon, Y=lat).
- Z/M: MVP prioritizes preserving XY; if rebuild drops dimensions, record that in tests.
- `NULL` → `NULL`; empty geometries returned as-is.

---

## Coordinate systems

| Name | Meaning |
| :--- | :--- |
| WGS-84 | GPS / international geographic coordinates |
| GCJ-02 | Mars coordinates |
| BD-09 | Baidu coordinates (further offset on top of GCJ) |
| SHCS2000 | Shanghai Coordinate System 2000 (Gauss–Krüger projected planar, meters) |

---

## Public functions

| Name | Point form | Geometry form | Description |
| :--- | :--- | :--- | :--- |
| `wgs84_to_gcj02` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | WGS84 to GCJ-02 |
| `gcj02_to_wgs84` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | GCJ-02 to WGS84 |
| `gcj02_to_bd09` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | GCJ-02 to BD-09 |
| `bd09_to_gcj02` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | BD-09 to GCJ-02 |
| `wgs84_to_bd09` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | WGS84 to BD-09 |
| `bd09_to_wgs84` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | BD-09 to WGS84 |
| `wgs84_to_shcs2000` | `(lat, lon) → STRUCT(x, y)` | `(geom) → GEOMETRY` | WGS84 to SHCS2000 (m) |
| `shcs2000_to_wgs84` | `(x, y) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | SHCS2000 (m) to WGS84 |
| `gcj02_to_shcs2000` | `(lat, lon) → STRUCT(x, y)` | `(geom) → GEOMETRY` | GCJ-02 to SHCS2000 (m) |
| `shcs2000_to_gcj02` | `(x, y) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | SHCS2000 (m) to GCJ-02 |
| `bd09_to_shcs2000` | `(lat, lon) → STRUCT(x, y)` | `(geom) → GEOMETRY` | BD-09 to SHCS2000 (m) |
| `shcs2000_to_bd09` | `(x, y) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | SHCS2000 (m) to BD-09 |

If the engine cannot overload the same name: allow a `*_geom` suffix, but README examples should lead with geometry usage.

### Geometry type matrix

| Type | Behavior |
| :--- | :--- |
| `POINT` | Single-point offset |
| `LINESTRING` | Per-vertex → `ST_MakeLine` |
| `POLYGON` | Exterior + holes → `ST_MakePolygon(shell, holes[])` |
| `MULTI*` | `ST_Dump` → transform → **`ST_Collect` / `ST_Multi` (do not use `ST_Union`)** |
| `GEOMETRYCOLLECTION` | Flat dump→transform→collect; nested may be limited depth or left to C++ |

```sql
SELECT wgs84_to_gcj02(geom) FROM parcels;
SELECT wgs84_to_gcj02(31.2304, 121.4737);
```

---

## Semantics shared by CRS operators

- **NULL**: any argument `NULL` ⇒ `NULL`.
- **Range (points)**: `lat ∈ [-90,90]`, `lon ∈ [-180,180]`; out-of-range / NaN / Inf prefer errors; if macros cannot throw, may return `NULL` and document that.
- **China bbox** (including the **BD segment**, matching pg):  
  `lon ∈ [72.004, 137.8347]` ∧ `lat ∈ [0.8293, 55.8271]`; outside the box that segment is identity.
- **Geometry**: apply bbox / offset per vertex.
- **GCJ→WGS**: one-shot `2p - forward(p)` (not iterative).
- **Deterministic**; **does not guarantee** seamless topology.

---

## CGCS2000

**Do not** provide `cgcs2000_to_*`. First:

```sql
-- Signature follows current DuckDB Spatial
ST_Transform(ST_SetSRID(geom, 4490), 'EPSG:4326')
```

Then call this library’s WGS↔GCJ/BD functions.

---

## Non-goals

- Community `INSTALL cnshift FROM community`.
- UTM / Gauss–Krüger / rigorous CGCS2000.
- User-written vertex loops.
- Copying PG’s Multi `ST_Union`.
