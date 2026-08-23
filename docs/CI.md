# CI strategy (path filters)

Goal: changes under `sql/` must **not** trigger the full C++ extension build matrix.

C++ CI **quality bar matches** [`duckdb/extension-template`](https://github.com/duckdb/extension-template) / `extension-ci-tools` (the same toolchain community-extensions uses to build listed extensions). This repo still **does not submit** to community-extensions (ADR-002).

## Suggested paths

| Job | Trigger paths | Work |
| :--- | :--- | :--- |
| **sql-smoke** (light) | `sql/**`, `testdata/golden/**`, `docs/bootstrap.md`, SQL-track tests | `INSTALL/LOAD spatial` → `.read sql/cnshift.sql` → golden / SQLLogic-style asserts |
| **ext-matrix** (full) | `ext/**`, `src/**`, `test/sql/*.test`, `CMakeLists.txt`, `Makefile`, `extension_config.cmake`, `vcpkg.json`, `.gitmodules`, extension workflows | Community-equivalent C++ gates (below) |
| **ext GitHub Release** | `ext-v*` tags whose commit is on `main` | Guard → rebuild full matrix → attach unsigned binaries |

Pure docs (e.g. narrative-only edits to `docs/DECISIONS.md`) may skip heavy jobs.

## C++ gates (aligned with extension-template)

Workflow: `.github/workflows/MainDistributionPipeline.yml`

| Gate | Mechanism | What it verifies |
| :--- | :--- | :--- |
| **duckdb-stable-build** | `extension-ci-tools` `_extension_distribution.yml@v1.5-variegata` | Multi-platform build of `cnshift.duckdb_extension` + SQLLogicTest (`make test_*`), DuckDB **v1.5.5** |
| **code-quality-check** | `_extension_code_quality.yml@v1.5-variegata` with `format_checks: format;tidy` | `make format-check` (clang-format 11 / cmake-format / black, same as DuckDB) and `make tidy-check` (clang-tidy, warnings as errors) |

Local equivalents (need submodules):

```bash
git submodule update --init --recursive
make debug && make test_debug
make release && make test_release
make format-check
make tidy-check
```

Style files are the same as the official template: `.clang-format` / `.clang-tidy` / `.editorconfig` symlink to `duckdb/`.

**Not in CI (on purpose):** community deploy (`_extension_deploy.yml`), `INSTALL FROM community`, community-extensions `description.yml`.

**GitHub Releases (private unsigned binaries):** pushing an `ext-v*` tag runs [`.github/workflows/ext-github-release.yml`](../.github/workflows/ext-github-release.yml). A first job checks that the tagged commit is already on `origin/main` (tags on `dev` / feature branches fail immediately). Path filters on `MainDistributionPipeline.yml` do not match tag-only pushes, so a passing guard then rebuilds the matrix rather than reusing PR artifacts. Download + `LOAD`: [`ext/README.md`](../ext/README.md).

## Current repo state

- **sql-smoke**: `.github/workflows/sql-smoke.yml` — runs `LOAD spatial` + goldens when `sql/**`, `testdata/golden/**`, SQL-track tests, or algorithm docs change. C++ `test/sql/*.test` files do **not** trigger this job.
- **ext-matrix**: `.github/workflows/MainDistributionPipeline.yml` — `ext/**`, `src/**`, `test/sql/*.test`, build files, `.gitmodules`; `sql/**`-only and golden-only changes do not run the C++ matrix (ADR-006).
- **ext GitHub Release**: `.github/workflows/ext-github-release.yml` — `push` of `ext-v*` tags only, and only if that commit is on `main`; attaches unsigned `cnshift.duckdb_extension` assets. `sql-v*` does not run this job.

See [`DECISIONS.md`](DECISIONS.md) ADR-002 / ADR-006 / ADR-009.
