# ALGORITHM — China CRS offset formulae (sole source of truth)

**Authority**: This document is the **sole algorithm source of truth** for `duckdb-cn-shift`.  
Future `sql/cnshift.sql` and C++ extension implementations **must reference this document** (file-header comment or equivalent link). They **must not** each maintain another copy of constants or formulae without a change to this document.

**Reference implementation**: [geocompass/pg-coordtransform](https://github.com/geocompass/pg-coordtransform) (`geoc_delta` / `geoc_transform_*` / `geoc_is_in_china_bbox` / BD polar segment).  
**Product decisions**: see [`DECISIONS.md`](DECISIONS.md).

**Convention**: Planar coordinates **X = lon (longitude)**, **Y = lat (latitude)**, in degrees. Point API argument order is `(lat, lon)` (per the public contract); kernel formulae are often described as `(lon, lat)` to match pg.

---

## 1. Constants

| Symbol | Value | Purpose |
| :--- | :--- | :--- |
| `a` | `6378245` | Ellipsoid semi-major axis (meters); used to project delta into degrees |
| `ee` | `0.006693421622965823` | Ellipsoid eccentricity-related constant (matches pg `geoc_delta`; **do not** swap to eviltransform’s `…94323` unless this document is updated first and goldens are re-pinned) |
| `x_pi` | `π * 3000.0 / 180.0` | BD polar rotation (pg hard-codes `3.14159265358979324 * 3000.0 / 180.0`) |
| BD translation | `0.0065` (lon), `0.006` (lat) | GCJ↔BD |
| BD fine-tune | `0.00002`, `0.000003` | Polar radius / angle perturbation |

China bounding box (`geoc_is_in_china_bbox`):

```text
lon ∈ [72.004, 137.8347]
lat ∈ [0.8293, 55.8271]
```

Outside the box → that segment’s offset is **identity** (return input). **The BD segment also applies this bbox** (follow pg source; not the “BD applies globally” convention).

---

## 2. `transform_lat` / `transform_lon`

Inputs are offsets from the China center: `x = lon - 105`, `y = lat - 35`.

### `transform_lat(x, y)` (aligned with `geoc_transform_lat`)

```text
ret  = -100 + 2*x + 3*y + 0.2*y² + 0.1*x*y + 0.2*√|x|
ret += (20*sin(6*x*π) + 20*sin(2*x*π)) * 2/3
ret += (20*sin(y*π) + 40*sin(y/3*π)) * 2/3
ret += (160*sin(y/12*π) + 320*sin(y*π/30)) * 2/3
```

### `transform_lon(x, y)` (aligned with `geoc_transform_lon`)

```text
ret  = 300 + x + 2*y + 0.1*x² + 0.1*x*y + 0.1*√|x|
ret += (20*sin(6*x*π) + 20*sin(2*x*π)) * 2/3
ret += (20*sin(x*π) + 40*sin(x/3*π)) * 2/3
ret += (150*sin(x/12*π) + 300*sin(x/30*π)) * 2/3
```

---

## 3. `delta(lon, lat)` → `(dLon, dLat)`

Aligned with `geoc_delta`:

```text
dLon0 = transform_lon(lon - 105, lat - 35)
dLat0 = transform_lat(lon - 105, lat - 35)
radLat = lat / 180 * π
magic  = 1 - ee * sin(radLat)²
sqrtMagic = √magic

dLon = (dLon0 * 180) / (a / sqrtMagic * cos(radLat) * π)
dLat = (dLat0 * 180) / ((a * (1 - ee)) / (magic * sqrtMagic) * π)
```

---

## 4. WGS-84 ↔ GCJ-02

### 4.1 Identity outside China

If `NOT in_china_bbox(lon, lat)` → return original `(lon, lat)` / original point.

### 4.2 WGS → GCJ (forward)

```text
(dLon, dLat) = delta(lon, lat)
gcj_lon = lon + dLon
gcj_lat = lat + dLat
```

### 4.3 GCJ → WGS (one-shot inversion, not iterative)

Aligned with pg `geoc_gcj02towgs84_point`:

```text
p' = forward_wgs_to_gcj(p)     -- feed the GCJ point as “fake WGS” into forward
wgs = 2 * p - p'               -- components: lon*2 - p'_lon, lat*2 - p'_lat
```

**Do not** default to eviltransform’s multi-round `gcj2wgs_exact` iteration; goldens align with PG’s one-shot approximation.

---

## 5. GCJ-02 ↔ BD-09 (polar)

Always run the China bbox check first; identity outside the box.

### 5.1 GCJ → BD (aligned with `geoc_gcj02tobd09_point`)

```text
z     = √(lon² + lat²) + 0.00002 * sin(lat * x_pi)
theta = atan2(lat, lon) + 0.000003 * cos(lon * x_pi)
bd_lon = z * cos(theta) + 0.0065
bd_lat = z * sin(theta) + 0.006
```

### 5.2 BD → GCJ (aligned with `geoc_bd09togcj02_point`)

```text
x = lon - 0.0065
y = lat - 0.006
z     = √(x² + y²) - 0.00002 * sin(y * x_pi)
theta = atan2(y, x) - 0.000003 * cos(x * x_pi)
gcj_lon = z * cos(theta)
gcj_lat = z * sin(theta)
```

---

## 6. Composite paths

| Public name | Composition |
| :--- | :--- |
| `wgs84_to_bd09` | WGS→GCJ → GCJ→BD |
| `bd09_to_wgs84` | BD→GCJ → GCJ→WGS |

Intermediate steps remain subject to their own bbox rules.

---

## 7. Geometry semantics (algorithm layer)

- Lines / polygons / Multi*: apply the corresponding point transform **per vertex**; topology is not guaranteed.
- Multi* rebuild: use `ST_Collect` / `ST_Multi` (**not** `ST_Union`) — see DECISIONS ADR-008.
- Polygon with holes: transform shell and hole vertices separately, then `ST_MakePolygon(shell, holes[])`.
- GeometryCollection: flat dump→transform→collect; deep nesting may be limited depth or deferred to C++.
- CGCS2000: no separate offset formula; `ST_Transform` to EPSG:4326 first, then call the functions above.

---

## 8. Implementation back-reference requirement

Any implementation file (SQL / C++) must note prominently:

```text
Algorithm constants and formulae: docs/ALGORITHM.md (single source of truth).
Do not diverge without updating that document and shared golden fixtures.
```

Change process: update this document → update `testdata/golden/` → then change SQL / C++.
