# CI strategy (path filters)

Goal: changes under `sql/` must **not** trigger the (future) full C++ extension build matrix.

## Suggested paths

| Job | Trigger paths (draft) | Work |
| :--- | :--- | :--- |
| **sql-smoke** (light) | `sql/**`, `testdata/golden/**`, `docs/ALGORITHM.md`, `docs/bootstrap.md`, related tests | `INSTALL/LOAD spatial` → `.read sql/cnshift.sql` → golden / SQLLogic-style asserts |
| **ext-matrix** (full) | `ext/**`, `src/**`, `test/sql/*.test`, `CMakeLists.txt`, `Makefile`, `extension_config.cmake`, `vcpkg.json`, `.gitmodules`, extension workflows | `extension-ci-tools` multi-platform build/test |

Pure docs (e.g. narrative-only edits to `docs/DECISIONS.md`) may skip heavy jobs, or run lint/link checks only (optional).

## Current repo state

- **sql-smoke**: `.github/workflows/sql-smoke.yml` — runs `LOAD spatial` + goldens when `sql/**`, `testdata/golden/**`, SQL-track tests, or algorithm docs change. C++ `test/sql/*.test` files do **not** trigger this job.
- **ext-matrix**: `.github/workflows/MainDistributionPipeline.yml` — `ext/**`, `src/**`, `test/sql/*.test`, build files, `.gitmodules`; `sql/**`-only and golden-only changes do not run the C++ matrix (ADR-006).

**Note**: These pipelines are for **self-hosted engineering quality** aligned with community norms; they do **not** mean submission to community-extensions. See [`DECISIONS.md`](DECISIONS.md) ADR-002 / ADR-006.
