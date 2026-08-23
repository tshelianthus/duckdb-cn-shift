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
5. Pushing an **`ext-v*`** tag publishes unsigned `cnshift.duckdb_extension` binaries as **GitHub Release** assets (workflow [`.github/workflows/ext-github-release.yml`](../.github/workflows/ext-github-release.yml)), **only if the tagged commit is already on `main`**. Tag after `dev` → `main`; do not tag `dev` or a feature branch. `sql-v*` does not attach C++ binaries. Actions artifacts from PR/push CI are ephemeral; do not treat them as the download channel.

## Relation to document versions

- API contract files may carry document versions such as `v0.2.0`; those are independent of git tag prefix rules, but release notes should cross-reference the matching `sql-v*` / `ext-v*`.
