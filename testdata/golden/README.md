# testdata/golden/ — shared golden fixtures

**SQL macro tests** and **C++ extension SQLLogicTests** share this directory so expectations do not fork.

## Files

| File | Content |
| :--- | :--- |
| `points.csv` | Points: `id,op,in_lat,in_lon,expect_lat,expect_lon,note` |
| `geometries.jsonl` | Geometries: input WKT, op name, expect type / part count / holes / vertices `[lon,lat]` |
| `generate.py` | Regenerate the test fixtures |

Coverage:

- In-China points and bbox corners: all canonical `op`s.
- Outside points (NYC, `(0,0)`, outside bbox): WGS↔GCJ and BD stages are identity.
- GCJ→WGS: one-shot `2p - forward(p)`; do not hard-align to iterative solvers.
- Geometries: Point / LineString / Polygon (with holes) / Multi* (adjacent part count unchanged) / flat GeometryCollection.
- Nested point-only `GEOMETRYCOLLECTION`: after `ST_Dump` flatten, `ST_Collect` may yield `MULTIPOINT` (intentional flatten).

## Rules

1. When changing fixtures, run `python3 testdata/golden/generate.py`, then `test/sql/run_sql_track.sh`.
2. Runners only adapt format (read fixture → assert); do not embed a second expectation table.
3. Decision background: [`docs/DECISIONS.md`](../../docs/DECISIONS.md) ADR-005.
