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

## ADR-008 — Behavioral specifications and geometry handling decisions

Design decisions for geometry transforms:

| Topic | Decision | Note |
| :--- | :--- | :--- |
| Multi* rebuild | `ST_Collect` / `ST_Multi`; **do not** use `ST_Union` | Avoid merging adjacent parts |
| GeometryCollection | Support flat dump→transform→collect; nested Collections handled via leaf extraction | Preserve heterogeneous collections |
| Polygon with holes | Rely on Spatial: `ST_MakePolygon(shell, holes[])` + `ST_Boundary` / `ST_Dump` / `ST_ExteriorRing`, etc. | Robust interior ring handling |
| BD segment + China bbox | BD point functions apply bbox checks | Identity transform outside bounding box |
| GCJ→WGS | One-shot `2p - forward(p)` | Fast non-iterative inversion |
| CGCS2000 | **Do not** implement redundant wrapper APIs; document `ST_Transform` to 4326 first | Clean, minimal surface |
| Public function names | `wgs84_to_gcj02`, `wgs84_to_shcs2000`, etc. | Concise and ergonomic |
| Numeric constants / delta | See `ALGORITHM.md` | Single source of truth |

Geometry paths transform XY only; **no guarantee** of topology preservation, seamlessness, or absence of self-intersections.

---

## ADR-009 — GitHub Releases host unsigned prebuilt extension binaries

### Decision

Users who want a loadable `cnshift.duckdb_extension` without running `make` download **GitHub Release** assets from this repository, attached when an `ext-v*` tag is pushed **on a commit that is already on `main`**.

- Channel: this repo’s Releases (not `duckdb/community-extensions`, not DuckDB org S3, not `INSTALL … FROM community`).
- Binaries stay **unsigned**; callers use `allow_unsigned_extensions` / `duckdb -unsigned` and `LOAD` a local path.
- Asset names: `cnshift-<ext-tag>-duckdb-<duckdb-version>-<arch>.duckdb_extension` (Wasm: `.duckdb_extension.wasm`).
- Building from source (`git submodule update --init --recursive` + `make release`) remains documented for maintainers and users whose DuckDB version or platform is not in the Release.
- Integration work stays on `dev`; do not publish prebuilts from `dev` or feature branches. Workflow: merge to `main`, then `git tag ext-v…` on that commit and push the tag.

### Consequences

- Do not tell users to scrape GitHub Actions artifacts (they expire).
- Do not add `_extension_deploy.yml` / community publish steps.
- README keeps SQL-first as the zero-build path; prebuilt C++ is optional; `make` is the source-build fallback.
- A tag whose commit is not on `origin/main` fails the release workflow before the platform matrix (no GitHub Release).

---

## Related document index

| Document | Role |
| :--- | :--- |
| [`ALGORITHM.md`](ALGORITHM.md) | Sole algorithm source of truth |
| [`bootstrap.md`](bootstrap.md) | SQL bootstrap injection |
| [`VERSIONING.md`](VERSIONING.md) | Dual-track tags; `ext-v*` → GitHub Release assets |
| [`CI.md`](CI.md) | Paths strategy + GitHub Release workflow |
| [`community-extension-release-spec.md`](community-extension-release-spec.md) | **SUPERSEDED** (quality alignment still useful reference) |
| [`.specs/03_API_CONTRACT.md`](../.specs/03_API_CONTRACT.md) | Public SQL surface |
