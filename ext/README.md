# ext/ — C++ extension (planned)

**Status: planned.** Until work starts, this directory keeps only this README.

- Product decisions, dual-track delivery, no community submit: [`docs/DECISIONS.md`](../docs/DECISIONS.md).
- Algorithm source of truth: [`docs/ALGORITHM.md`](../docs/ALGORITHM.md) (implementations must back-reference; no private constant tables).
- Version tags: `ext-v*` (see [`docs/VERSIONING.md`](../docs/VERSIONING.md)).

## Forbidden for now

- Do **not** `git submodule add` or pull a full extension-template into this directory yet.
- Do **not** open PRs against `duckdb/community-extensions` (legal/compliance boundary, not a technical gap).
- If a root C++ scaffold still exists, treat it as legacy/experimental; **the formal extension workspace is this directory** (migrate when work starts).

## When to start

After the SQL path is demable and goldens are stable, land extension builds and privately distributed binaries here.
