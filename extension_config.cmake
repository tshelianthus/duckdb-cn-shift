# This file is included by DuckDB's build system. It specifies which extension to load

# Extension from this repo
duckdb_extension_load(cnshift
    SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR}
)

# In-tree json so geometry SQLLogicTests can read testdata/golden/geometries.jsonl.
# Not a runtime dependency of LOAD cnshift.
duckdb_extension_load(json)

