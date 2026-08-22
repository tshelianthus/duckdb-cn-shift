---
schema_version: "1.0"
tech_stack:
  language: "DuckDB SQL (primary) + C++17 (optional extension track)"
  backend_framework: "SQL macros + official spatial; optional DuckDB C++ extension-template"
  frontend_framework: "N/A"
  database: "DuckDB (SQL path: any recent with spatial; C++ path pin v1.5.5 when building ext)"
  migration_tool: "N/A"
  package_manager:
    backend: "N/A for SQL track; vcpkg+CMake for extension track"
    frontend: "N/A"
conventions:
  naming:
    api_path_style: "SQL snake_case CRS names (wgs84_to_gcj02); extension name cnshift if built"
    db_object_style: "N/A"
    component_style: "N/A"
    error_code_style: "DuckDB errors where applicable; SQL macros may NULL when cannot throw"
  api:
    version_prefix: "sql-v* / ext-v* (see docs/VERSIONING.md)"
  commit:
    format: "Conventional Commits (feat/fix/chore/docs/refactor/test)"
toolchain:
  lint:
    backend: ["clang-format for C++ when ext active"]
    frontend: []
  test:
    backend: ["shared testdata/golden; SQL bootstrap tests; optional make test_debug for ext"]
    frontend: []
ci:
  platform: "github-actions"
  pipeline_path: ".github/workflows/MainDistributionPipeline.yml"
  notes: "paths filter: sql/** should not trigger full C++ matrix (docs/CI.md)"
issues:
  - code: COMMUNITY_SUBMISSION_FORBIDDEN
    severity: info
    message: "This repository does not submit to duckdb/community-extensions (legal/compliance). Do not list community PRs as tasks."
    blocking: false
    owner: pm-agent
    action: "Follow docs/DECISIONS.md ADR-002."
---

# duckdb-cn-shift engineering conventions

## Product positioning

**Dual-track, same repo, no community submission**:

1. **Primary deliverable**: `sql/cnshift.sql` — bootstrap-injected macros, depends on official `spatial`, UX aligned with pg-coordtransform.
2. **Fallback**: C++ `cnshift` extension (`ext/` planned) — privately distributed binary.
3. **Legal boundary**: Do not submit to `duckdb/community-extensions`; reason is compliance, not insufficient quality.

Sole algorithm source of truth: `docs/ALGORITHM.md`. Decisions: `docs/DECISIONS.md`.

## Difference from the old “Community Extension as sole product” positioning

Initialization originally landed as a community-extension scaffold. The decided model is now SQL-first + dual-track private distribution; the community release-spec doc is marked SUPERSEDED. Agents **must not** restore “must open a community PR” as a milestone.

## Directory tree (target)

```
duckdb-cn-shift/
├── sql/cnshift.sql          # primary deliverable
├── ext/src/                 # C++ fallback (cnshift.duckdb_extension)
├── testdata/golden/         # shared goldens
├── docs/DECISIONS.md
├── docs/ALGORITHM.md
├── docs/bootstrap.md
├── .specs/
├── src/README.md            # pointer to ext/src
└── ...
```

## Branch strategy

- Working branch: `dev`
- Release merge: PR → `main`
- Tags: `sql-v*` / `ext-v*`
- Commits: Conventional Commits

## Do-not list

- Do not submit to community-extensions.
- Do not introduce GEOS/GDAL/PROJ / Rust.
- Do not treat user dump/loops as primary UX.
- Do not use `ST_Union` for Multi* (use Collect).
