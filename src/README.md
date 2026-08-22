# src/ — extension-template glue (not a second algorithm)

DuckDB's extension codegen includes `{name}_extension.hpp` from **`src/include/`**. That header is the `Extension` class only.

CRS formulae, WKB geometry, and scalar registration live in [`ext/src/`](../ext/src/). Do not re-introduce transform constants here.

Root `CMakeLists.txt` / `Makefile` stay at the repository root because `extension-ci-tools` expects them there. See [`ext/README.md`](../ext/README.md).
