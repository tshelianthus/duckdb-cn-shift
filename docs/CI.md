# CI strategy (path filters)

Goal: changes under `sql/` must **not** trigger the (future) full C++ extension build matrix.

## Suggested paths

| Job | Trigger paths (draft) | Work |
| :--- | :--- | :--- |
| **sql-smoke** (light) | `sql/**`, `testdata/golden/**`, `docs/ALGORITHM.md`, `docs/bootstrap.md`, related tests | `INSTALL/LOAD spatial` → `.read sql/cnshift.sql` → golden / SQLLogic-style asserts |
| **ext-matrix** (full) | `ext/**`, `src/**`, `CMakeLists.txt`, `Makefile`, `extension_config.cmake`, `vcpkg.json`, `.gitmodules`, extension workflows | `extension-ci-tools` multi-platform build/test |

Pure docs (e.g. narrative-only edits to `docs/DECISIONS.md`) may skip heavy jobs, or run lint/link checks only (optional).

## Current repo state

- **sql-smoke**: `.github/workflows/sql-smoke.yml` — runs `LOAD spatial` + goldens when `sql/**`, `testdata/golden/**`, related tests, or algorithm docs change.
- **ext-matrix**: `.github/workflows/MainDistributionPipeline.yml` — only `ext/**`, `src/**`, build files, etc.; `sql/**`-only changes do not run the C++ matrix.

**Note**: These pipelines are for **self-hosted engineering quality** aligned with community norms; they do **not** mean submission to community-extensions. See [`DECISIONS.md`](DECISIONS.md) ADR-002 / ADR-006.
