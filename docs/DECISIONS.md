# Architecture Decision Records — duckdb-cn-shift

**Status**: Decided (2026-08-23)  
**Scope**: All deliverable forms and documentation in this repository; any older specs that conflict with this document are superseded by this one.

---

## ADR-001 — Dual-track delivery, same repo, no community submission

### Decision

- **Dual delivery, same repository**: Primary deliverable is the SQL macro script (`sql/cnshift.sql`); the C++ extension (`ext/` / existing scaffold) is a later **fallback** path.
- **Private distribution**: Both are self-hosted / privately distributed. Engineering quality aligns with DuckDB Community Extensions norms (build, tests, vectorization, zero-crash, etc.), but community listing is **not** a product goal.
- **Only difference**: Artifact form — `.sql` (bootstrap injection) vs `.duckdb_extension` (`LOAD` binary).

### Consequences

- README / PRD must not primarily push `INSTALL … FROM community`.
- Engineering checklists may keep “align with community quality”; they must not require a PR to `duckdb/community-extensions`.

---

## ADR-002 — Legal boundary: do not submit to community-extensions

### Decision

This repository **does not** submit extension descriptors or release PRs to [`duckdb/community-extensions`](https://github.com/duckdb/community-extensions).

**Reason: legal / compliance considerations (not lack of technical capability, not insufficient engineering quality).**

Engineering standards still align with community norms (cross-platform builds, SQLLogicTest, dependency declarations, license, etc.); only the distribution channel is self-hosted / private.

### Consequences

- `docs/community-extension-release-spec.md` is marked **SUPERSEDED** (archived); clauses requiring a community PR are void.
- `docs/community/description.yml` is labeled **NOT FOR SUBMISSION**.
- Later maintainers / Agents **must not** treat “get listed in the community” as a milestone or open community PRs on their own.

---

## ADR-003 — SQL first, extension later

### Decision

1. **Implement first** the SQL registration path (`INSTALL/LOAD spatial` + `.read sql/cnshift.sql`) so it is usable.
2. **Separately later** implement the C++ extension path as a fallback / performance / geometry hard-path offering.
3. `ext/` currently holds the C++ fallback (`ext/src/`) plus this document’s install notes. Submodules (`duckdb`, `extension-ci-tools`) are added **because this track is in progress**. Root `CMakeLists.txt` / `Makefile` stay at the repo root (required by `extension-ci-tools`); root `src/` is a pointer, not a second copy. **Do not** open PRs against `duckdb/community-extensions`.

### Consequences

- Product primary-path docs follow the SQL bootstrap.
- Formal extension sources live in `ext/src/`; root `src/` must not carry a second copy of the algorithm.

---

## ADR-004 — `docs/ALGORITHM.md` is the sole algorithm source of truth

### Decision

Ellipsoid constants, delta formulae, China bbox, BD polar constants, one-shot GCJ→WGS inversion, and related material are **all** written in [`docs/ALGORITHM.md`](ALGORITHM.md).

Future SQL and C++ implementations **may only reference** that document (comments / README links). They **must not** each maintain a separate constant table or drifting formulae.

### Consequences

- Formula changes must update `ALGORITHM.md` first, then both implementations and the shared golden tests.
- Hard-coded constants with no back-reference found in code review → treat as a defect.

---

## ADR-005 — Shared golden fixtures

### Decision

Point + geometry WKT inputs/expected values live under `testdata/golden/`. Future SQL tests and C++ SQLLogicTest **both** consume the same fixtures to avoid divergence.

### Consequences

- Adding/changing expected values only touches `testdata/golden/` (and generator scripts if any); both runners only adapt format.

---

## ADR-006 — CI path filters

### Decision

- Changes that only touch `sql/`, `testdata/golden/` (and pure SQL docs) **must not** trigger the (future) full C++ cross-platform build matrix.
- Changes under `ext/**`, `src/**`, or related CMake/Makefile/submodule paths: run the full extension matrix.
- The SQL path uses a light job (`LOAD spatial` + inject script + golden compare); may start as a TODO placeholder.

Details: [`docs/CI.md`](CI.md) and comments in `.github/workflows/MainDistributionPipeline.yml`.

---

## ADR-007 — Independent version tags

### Decision

| Delivery line | Tag prefix | Example |
| :--- | :--- | :--- |
| SQL macros | `sql-v*` | `sql-v0.1.0` |
| C++ extension | `ext-v*` | `ext-v0.1.0` |

**Do not** share a bare `v0.1.0` as representing both tracks. See [`docs/VERSIONING.md`](VERSIONING.md).

---

## ADR-008 — Behavioral fidelity and intentional deviations

Aligned with [geocompass/pg-coordtransform](https://github.com/geocompass/pg-coordtransform) and post-expert-review decisions:

| Topic | Decision | vs PG |
| :--- | :--- | :--- |
| Multi* rebuild | `ST_Collect` / `ST_Multi`; **do not** use `ST_Union` | **Intentional deviation** (avoid merging adjacent parts) |
| GeometryCollection | Support flat dump→transform→collect; nested Collections may be limited depth, or deferred to C++ | **Intentional improvement** (PG uses ELSE→NULL) |
| Polygon with holes | Rely on Spatial: `ST_MakePolygon(shell, holes[])` + `ST_Boundary` / `ST_Dump` / `ST_ExteriorRing`, etc. | **Follow capability, not API names**; reject the outdated claim that “SQL cannot handle holes” |
| BD segment + China bbox | BD point functions also apply bbox (matches pg source) | **Follow PG** |
| GCJ→WGS | One-shot `2p - forward(p)`, not iterative | **Follow PG** |
| CGCS2000 | **Do not** implement same-named APIs; document `ST_Transform` to 4326 first | **Reduced surface** (PG has wrapper functions) |
| Public function names | `wgs84_to_gcj02`, etc.; docs include `geoc_*` mapping | **Naming deviation** (UX alignment) |
| Numeric constants / delta | See `ALGORITHM.md` (aligned with pg `geoc_delta`) | **Follow PG** |

Geometry paths transform XY only; **no guarantee** of topology preservation, seamlessness, or no self-intersections (same class of limits as PG).

---

## Related document index

| Document | Role |
| :--- | :--- |
| [`ALGORITHM.md`](ALGORITHM.md) | Sole algorithm source of truth |
| [`bootstrap.md`](bootstrap.md) | SQL bootstrap injection |
| [`VERSIONING.md`](VERSIONING.md) | Dual-track tags |
| [`CI.md`](CI.md) | Paths strategy |
| [`community-extension-release-spec.md`](community-extension-release-spec.md) | **SUPERSEDED** (quality alignment still useful reference) |
| [`.specs/03_API_CONTRACT.md`](../.specs/03_API_CONTRACT.md) | Public SQL surface |
