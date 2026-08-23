# SUPERSEDED — Former “Community Extension Release Spec”

> **Status: SUPERSEDED / archived (2026-08-23)**  
> **Formal decision**: This repository **will not** submit to `duckdb/community-extensions`.  
> **Reason**: Legal/compliance considerations (**not** lack of technical capability or engineering quality).  
> **Authoritative doc**: [`docs/DECISIONS.md`](DECISIONS.md) ADR-002.  
> **Version tags**: Use `sql-v*` / `ext-v*`; do not follow the bare `v0.1.0` + community PR flow below.

Below is retained only as a reference checklist for **“engineering quality aligned with community standards”** (still useful for self-hosted / private distribution rigor in build and test). **All clauses requiring a community PR, `INSTALL FROM community`, or pushing `description.yml` to community-extensions are void.**

---

# (Archived) DuckDB Community Extension Quality Alignment Checklist (cnshift)

## 1. Engineering requirements (still useful as reference)

Extension/script projects should satisfy:

- Clear source hosting; explicit license (this repo: **Apache-2.0**).
- C++ extension track: CMake; consistent naming; no undeclared private dependencies.
- Releases point at a fixed Git commit / tag (this repo uses `ext-v*` / `sql-v*`).
- Installable / loadable / basic functionality works; must not crash DuckDB.

SQL primary path extras: declare `spatial` dependency clearly; bootstrap must be reproducible (`docs/bootstrap.md`).

## 2. Build and test gates (self-hosted)

C++ track (when `ext/` / `src/` work starts):

```bash
git submodule update --init --recursive
make debug && make test_debug
make release && make test_release
make format-check
make tidy-check
```

These are the same Makefile targets as [`duckdb/extension-template`](https://github.com/duckdb/extension-template) CI (`_extension_distribution.yml` + `_extension_code_quality.yml`). CI wiring: [`docs/CI.md`](CI.md).

## 3. Functional test requirements (still applicable)

Each public function covers: normal input, boundaries, illegal input, NULL, batches; CRS also covers in-China offset, bbox identity, round-trip, polygons with holes, Multi part counts.

## 4. Branching and versioning (revised)

1. Finish implementation and tests on `dev`.
2. PR into `main`.
3. Tag: `sql-vX.Y.Z` and/or `ext-vX.Y.Z` (see `docs/VERSIONING.md`).
4. ~~Submit to community-extensions~~ **Forbidden**.

## 5–9. Former “Community description file / Community PR” sections

**Entire sections void.** Draft `docs/community/description.yml` is historical placeholder only; header already marked NOT FOR SUBMISSION.

## Private-distribution checklist (replaces community PR checklist)

- [ ] Behavior matches API contract.
- [ ] Shared goldens updated.
- [ ] Corresponding SQL or extension-track tests pass.
- [ ] README / bootstrap do not advertise community INSTALL.
- [ ] Correctly prefixed tags applied (`sql-v*` / `ext-v*`).
- [ ] `ext-v*` GitHub Release has unsigned per-platform `cnshift.duckdb_extension` assets (not Actions artifacts, not community).
- [ ] **Confirm no** PR opened against `duckdb/community-extensions`.
