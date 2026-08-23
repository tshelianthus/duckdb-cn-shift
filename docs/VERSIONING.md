# Versioning and tag rules

This repository has dual-track delivery. **Version tags are independent**. Do not share a bare `v0.1.0` as representing both SQL and the extension.

| Delivery line | Tag format | Example | Artifact |
| :--- | :--- | :--- | :--- |
| SQL macros | `sql-vMAJOR.MINOR.PATCH` | `sql-v0.1.0` | `sql/cnshift.sql` + docs |
| C++ extension | `ext-vMAJOR.MINOR.PATCH` | `ext-v0.1.0` | `cnshift.duckdb_extension` |

## Rules

1. SemVer evolves separately: a SQL formula fix may bump only `sql-v*`; an extension binary fix may bump only `ext-v*`.
2. When shared `testdata/golden/` changes: if both tracks are implemented, both tags should note the compatible fixture version (call it out in release notes).
3. **Do not** create a bare `v0.1.0` as an official product tag (avoids later confusion with a single-track community-extension release).
4. Do not publish to `duckdb/community-extensions`; tags are only for private distribution and change tracking in this repo. See [`DECISIONS.md`](DECISIONS.md).
5. **Automated Release via `main` merge**: Update the root `VERSION` file (e.g. `0.3.0`) during development on `dev`. When `dev` is merged and pushed to `main`, GitHub Actions workflow [`.github/workflows/ext-github-release.yml`](../.github/workflows/ext-github-release.yml) automatically detects the unreleased version, tags `sql-v*` and `ext-v*`, creates the SQL release, and builds/publishes multi-arch unsigned extension binaries to GitHub Release.
6. Pushing an **`ext-v*`** tag directly also triggers the release workflow, provided the commit is already on `main`. Tags on `dev` or feature branches do not publish releases.

## Relation to document versions

- API contract files may carry document versions such as `v0.2.0`; those are independent of git tag prefix rules, but release notes should cross-reference the matching `sql-v*` / `ext-v*`.
