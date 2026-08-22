# Tasks & Execution Roadmap

## Decision anchors

- Dual-track, SQL-first, not on community, ALGORITHM as SoT, shared goldens, separate tags: [`docs/DECISIONS.md`](../docs/DECISIONS.md).
- **Do not** open a PR against `duckdb/community-extensions`.
- **Do not** run `git submodule add` under `ext/` right now.

## [x] Phase D0: Docs and directory layout (this iteration)

- [x] `docs/DECISIONS.md` / `ALGORITHM.md` / `bootstrap.md` / `VERSIONING.md` / `CI.md`
- [x] `sql/` placeholder + `ext/README.md` + `testdata/golden/README.md`
- [x] Specs / README / AGENTS / community docs archive aligned

## [x] Phase S1: SQL kernel (points)

- [x] Implement bbox / transform / delta / six-point conversions in `sql/cnshift.sql` (constants point back to ALGORITHM)
- [x] Point STRUCT API + golden point fixtures
- [x] Bootstrap smoke docs and minimal automation (`.github/workflows/sql-smoke.yml`)

## [x] Phase S2: SQL geometry

- [x] Point / LineString / simple Polygon
- [x] Polygon with holes (`ST_MakePolygon` + Boundary/Dump/ExteriorRing)
- [x] Multi* via `ST_Collect`/`ST_Multi`
- [x] Flat GeometryCollection; nested-depth policy documented
- [x] Geometry WKT goldens cross-checked against ALGORITHM / pg formulas

## [ ] Phase S3: SQL release

- [ ] Tag `sql-v0.1.0` (private distribution; not tagged this iteration)
- [x] README / bootstrap examples locked in

## [~] Phase 0 (legacy): C++ extension-template scaffold

- [x] Existing in-repo C++ skeleton and `00_load.test` (not the product mainline)
- [ ] Optionally keep load-smoke green after submodule checkout (does not block SQL)
- [ ] **Cancel** former “Phase 2 Community Submission” — superseded by DECISIONS

## [ ] Phase E1 (deferred): ext/ extension fallback

- [ ] Populate `ext/` at kickoff (migrate/new template); algorithm points back to ALGORITHM
- [ ] Consume the same `testdata/golden/`
- [ ] Tag `ext-v0.1.0`; full CI matrix only on `ext/**`/`src/**` triggers
- [ ] Private binary distribution; **still not on community**

## Explicitly cancelled legacy tasks

- [ ] ~~Submit `description.yml` to `duckdb/community-extensions`~~ **CANCELLED (legal boundary)**
- [ ] ~~Shared bare tag `v0.1.0`~~ **CANCELLED** (use `sql-v*` / `ext-v*` instead)
