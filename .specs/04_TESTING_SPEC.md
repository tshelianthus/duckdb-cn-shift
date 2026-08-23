# Testing & Verification Specification

## Dual-track and shared goldens

| Track | Runner | Expected-value source |
| :--- | :--- | :--- |
| **SQL (primary)** | `LOAD spatial` + `.read sql/cnshift.sql` + assertion scripts | **`testdata/golden/`** (shared) |
| **C++ (fallback)** | `make test_debug` / SQLLogicTest (`test/sql/`) | **The same** `testdata/golden/` |

Do not let SQL and C++ maintain forked golden tables. Coordinate transformation behavior changes must update goldens and both sides' tests in sync. See [`docs/DECISIONS.md`](../docs/DECISIONS.md).

## SQL primary-path gates (priority)

1. Can inject per [`docs/bootstrap.md`](../docs/bootstrap.md).
2. Point matrix: in-China offset, outside identity, round-trip (GCJ→WGS is one-shot inverse), NULL, range.
3. Geometry matrix: Point / LineString / Polygon (**with holes**) / Multi* (part count unchanged) / flat GeometryCollection.
4. Compare against pg-coordtransform on the same inputs (suggest `round(..., 7)` or an agreed tolerance).

CI: `sql/**` changes run a lightweight SQL job and **must not** trigger the full C++ platform matrix ([`docs/CI.md`](../docs/CI.md)).

## C++ extension gates (fallback)

When submodules are available and `ext/**` / `src/**` / build files are touched:

1. `make debug` / `make test_debug` (and release).
2. `make format-check` and `make tidy-check` (same as `duckdb/extension-template`).
3. Load-smoke (`test/sql/00_load.test`) stays green.
4. CRS behavior aligns with the SQL track on the same goldens (`points_golden.test`, `geometry_golden.test`).
5. Point out-of-range / NaN / Inf **throw** (`api_errors.test`); SQL macros return NULL for the same inputs.

**Out of scope**: `INSTALL cnshift FROM community` (this repo is not listed on community).

Private `LOAD` + unsigned flag + GitHub Release downloads: [`ext/README.md`](../ext/README.md).

## Phase: point-operator matrix (excerpt)

| City | lat | lon |
| :--- | ---: | ---: |
| Shanghai | 31.2304 | 121.4737 |
| Beijing | 39.9042 | 116.4074 |

Outside example: New York `40.7128, -74.0060`; `0.0, 0.0`.

- WGS↔GCJ identity outside China; BD segment also applies bbox like pg.
- Illegal lat/lon → error or documented NULL.
- Combined paths match step-by-step results.

## Geometry acceptance checklist

1. In-China: type unchanged; vertices show observable offset.
2. With holes: holes remain holes; shell/hole vertex-count policy documented and tested.
3. MultiPolygon: part count unchanged (Collect, not Union).
4. NULL / empty geometry.
