# duckdb-cn-shift

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> [!WARNING]
> **DISCLAIMER & COMPLIANCE WARNING**: This software provides mathematical approximations based on open-source community empirical models. It is **NOT** an official surveying standard, carries **NO** official certification or legal validity, and is strictly prohibited for commercial surveying, cadastral mapping, or navigation. Users must independently ensure compliance with all applicable surveying and geospatial data regulations. See [DISCLAIMER.md](DISCLAIMER.md).

SQL macros and utility functions for geometric coordinate transformations (WGS-84 ↔ GCJ-02 ↔ BD-09 ↔ SHCS2000) in DuckDB.

Provides unified mathematical transform interfaces for spatial analytics across points, lines, and polygons.

- **Primary delivery**: `sql/cnshift.sql` (SQL macros + official `spatial`)
- **Optional**: C++ extension (`ext/`) — [download a prebuilt binary](#c-extension-optional-fallback) or [build from source](ext/README.md#build-from-source)
- **Not published** to [`duckdb/community-extensions`](https://github.com/duckdb/community-extensions) (legal/compliance). Engineering quality still tracks community norms. See [`docs/DECISIONS.md`](docs/DECISIONS.md).

## How to use (no `make`)

Primary artifact is one SQL file: [`sql/cnshift.sql`](sql/cnshift.sql). Install any [official DuckDB client](https://duckdb.org/docs/current/clients/overview.html). No compilation is required (do not run `make` or attempt `INSTALL cnshift FROM community`). There is no separate language package (`pip` / `install.packages("cnshift")`, etc.).

Same steps on every client:

1. Obtain `sql/cnshift.sql` (clone the repo or copy the file).
2. On the **current connection**: `INSTALL spatial;` (once per machine) → `LOAD spatial;` (once per process/connection).
3. Execute the **full** `cnshift.sql` into that database (macros land in the catalog).
4. `SELECT wgs84_to_gcj02(31.2304, 121.4737);` or `SELECT wgs84_to_gcj02(geom) FROM parcels;`

Point overload is **`(lat, lon)`**; geometry `ST_Point` remains **`(lon, lat)`**. `.read` exists **only in the CLI**. In-memory DBs need the script every new process; a persistent `.duckdb` needs injection once (new connections still need `LOAD spatial`).

Sections below follow the official Client Overview table order (Primary, then Secondary). Jump links:

**Primary:** [C](#c) · [CLI](#cli) · [Java](#java-jdbc) · [Go](#go) · [Node.js](#nodejs-node-neo) · [ODBC](#odbc) · [Python](#python) · [R](#r) · [Rust](#rust) · [Wasm](#webassembly-wasm)

**Secondary:** [ADBC](#adbc-arrow) · [C#](#c-net) · [C++ client](#c-client)

### C

[`libduckdb` / C API](https://duckdb.org/docs/current/clients/c/overview.html). `duckdb_query` is one statement at a time; split the full script with `duckdb_extract_statements`, or CLI `.read` into a persistent file then `duckdb_open`.

```c
duckdb_database db;
duckdb_connection con;
duckdb_result res;
duckdb_open(NULL, &db);          /* or duckdb_open("analysis.duckdb", &db) */
duckdb_connect(db, &con);
duckdb_query(con, "INSTALL spatial;", &res);
duckdb_destroy_result(&res);
duckdb_query(con, "LOAD spatial;", &res);
duckdb_destroy_result(&res);
/* then extract + prepare cnshift.sql, or open a pre-injected analysis.duckdb */
duckdb_query(con, "SELECT wgs84_to_gcj02(31.2304, 121.4737);", &res);
```

### CLI

[CLI client](https://duckdb.org/docs/current/clients/cli/overview.html). Paths are relative to the **current working directory**.

```bash
cd /path/to/duckdb-cn-shift
duckdb                  # in-memory: reinject every new CLI session
# duckdb analysis.duckdb  # persistent: inject once
```

```sql
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql'   -- or absolute .read '/abs/path/sql/cnshift.sql'
SELECT wgs84_to_gcj02(31.2304, 121.4737);
SELECT wgs84_to_gcj02(ST_Point(121.4737, 31.2304));
```

Inject once into a persistent file for other languages to share:

```bash
duckdb analysis.duckdb <<'EOF'
INSTALL spatial;
LOAD spatial;
.read 'sql/cnshift.sql'
EOF
```

### Java (JDBC)

[`jdbc:duckdb:`](https://duckdb.org/docs/current/clients/java/overview.html) (Maven: `org.duckdb:duckdb_jdbc`). JDBC is usually one statement at a time; split the script or use `Files.readString` carefully. Or open a CLI-injected file: `jdbc:duckdb:analysis.duckdb`.

```java
Connection conn = DriverManager.getConnection("jdbc:duckdb:"); // or jdbc:duckdb:analysis.duckdb
try (Statement stmt = conn.createStatement()) {
    stmt.execute("INSTALL spatial");
    stmt.execute("LOAD spatial");
    stmt.execute(Files.readString(Path.of("sql/cnshift.sql"))); // if multi-statement fails, open a pre-injected .duckdb
    try (ResultSet rs = stmt.executeQuery(
            "SELECT wgs84_to_gcj02(31.2304, 121.4737)")) {
        rs.next();
        System.out.println(rs.getObject(1));
    }
}
```

In DBeaver and similar IDEs: **Execute SQL Script** on `cnshift.sql`, not only the statement under the cursor.

### Go

Official [`github.com/duckdb/duckdb-go/v2`](https://duckdb.org/docs/current/clients/go.html) + `database/sql`.

```go
import (
    "database/sql"
    "os"
    _ "github.com/duckdb/duckdb-go/v2"
)

db, _ := sql.Open("duckdb", "") // or "analysis.duckdb"
defer db.Close()
db.Exec("INSTALL spatial")
db.Exec("LOAD spatial")
script, _ := os.ReadFile("sql/cnshift.sql")
db.Exec(string(script)) // if multi-statement is rejected, Open a pre-injected file
row := db.QueryRow("SELECT wgs84_to_gcj02(31.2304, 121.4737)")
```

### Node.js (node-neo)

Official [`@duckdb/node-api`](https://duckdb.org/docs/current/clients/node_neo/overview.html). Use `extractStatements` for multi-statement scripts.

```javascript
import { readFileSync } from 'node:fs';
import { DuckDBInstance } from '@duckdb/node-api';

const instance = await DuckDBInstance.create(); // or create('analysis.duckdb')
const connection = await instance.connect();
await connection.run('INSTALL spatial');
await connection.run('LOAD spatial');
const script = readFileSync('sql/cnshift.sql', 'utf8');
const extracted = await connection.extractStatements(script);
for (let i = 0; i < extracted.count; i++) {
  const prepared = await extracted.prepare(i);
  await prepared.run();
}
await connection.runAndReadAll('SELECT wgs84_to_gcj02(31.2304, 121.4737)');
```

### ODBC

[ODBC driver](https://duckdb.org/docs/current/clients/odbc/overview.html) (Excel, Tableau, DBeaver, custom `SQLExecDirect`). After connect, run the same SQL: `INSTALL` / `LOAD spatial`, then execute `cnshift.sql` as a **script**. `SQLExecDirect` is usually one statement; BI tools should use “execute script”. Or CLI-inject `analysis.duckdb` and open that file via ODBC.

### Python

[`duckdb` on PyPI](https://duckdb.org/docs/current/clients/python/overview.html). Verified on 1.5.x that one `execute` can run the whole file:

```python
from pathlib import Path
import duckdb

con = duckdb.connect()  # or duckdb.connect("analysis.duckdb")
con.execute("INSTALL spatial")
con.execute("LOAD spatial")
con.execute(Path("sql/cnshift.sql").read_text())
print(con.sql("SELECT wgs84_to_gcj02(31.2304, 121.4737)").fetchall())
print(con.sql("SELECT wgs84_to_gcj02(ST_Point(121.4737, 31.2304))").fetchall())
```

### R

[`duckdb` on CRAN](https://duckdb.org/docs/current/clients/r.html) + DBI.

```r
library(DBI)
library(duckdb)

con <- dbConnect(duckdb::duckdb())  # or duckdb("analysis.duckdb")
dbExecute(con, "INSTALL spatial")
dbExecute(con, "LOAD spatial")
dbExecute(con, paste(readLines("sql/cnshift.sql"), collapse = "\n"))
dbGetQuery(con, "SELECT wgs84_to_gcj02(31.2304, 121.4737)")
```

If your version rejects multi-statement executes, use `dbConnect(duckdb::duckdb(), "analysis.duckdb")` after a CLI `.read` injection.

### Rust

[`duckdb` on crates.io](https://duckdb.org/docs/current/clients/rust.html) (`duckdb-rs`). Use `execute_batch` for scripts:

```rust
use duckdb::Connection;
use std::fs;

let conn = Connection::open_in_memory()?; // or Connection::open("analysis.duckdb")
conn.execute_batch("INSTALL spatial; LOAD spatial;")?;
conn.execute_batch(&fs::read_to_string("sql/cnshift.sql")?)?;
let row: String = conn.query_row(
    "SELECT wgs84_to_gcj02(31.2304, 121.4737)::VARCHAR",
    [],
    |r| r.get(0),
)?;
```

### WebAssembly (Wasm)

[`@duckdb/duckdb-wasm`](https://duckdb.org/docs/current/clients/wasm/overview.html). Same SQL; pick a Wasm bundle that [supports `spatial`](https://duckdb.org/docs/current/clients/wasm/extensions.html).

```javascript
// after official Wasm instantiation of conn:
await conn.query('INSTALL spatial;');
await conn.query('LOAD spatial;');
// split cnshift.sql and query statement-by-statement, or load a native CLI-injected file (Wasm is often in-memory)
await conn.query('SELECT wgs84_to_gcj02(31.2304, 121.4737);');
```

### ADBC (Arrow)

Secondary. [DuckDB ADBC](https://duckdb.org/docs/current/clients/adbc.html). Python example:

```python
from pathlib import Path
import adbc_driver_duckdb.dbapi

with adbc_driver_duckdb.dbapi.connect("analysis.duckdb") as conn, conn.cursor() as cur:
    cur.execute("INSTALL spatial")
    cur.execute("LOAD spatial")
    cur.execute(Path("sql/cnshift.sql").read_text())  # if multi-statement fails, CLI-inject the file first
    cur.execute("SELECT wgs84_to_gcj02(31.2304, 121.4737)")
    print(cur.fetchall())
```

### C# (.NET)

Secondary. [DuckDB.NET](https://duckdb.net/) (NuGet; official table maintainer Giorgi).

```csharp
using DuckDB.NET.Data;

using var conn = new DuckDBConnection("Data Source=:memory:"); // or Data Source=analysis.duckdb
conn.Open();
using var cmd = conn.CreateCommand();
cmd.CommandText = "INSTALL spatial;";
cmd.ExecuteNonQuery();
cmd.CommandText = "LOAD spatial;";
cmd.ExecuteNonQuery();
cmd.CommandText = File.ReadAllText("sql/cnshift.sql");
cmd.ExecuteNonQuery(); // if multi-statement fails, open a pre-injected file
cmd.CommandText = "SELECT wgs84_to_gcj02(31.2304, 121.4737);";
using var reader = cmd.ExecuteReader();
```

### C++ client

Secondary. [C++ client](https://duckdb.org/docs/current/clients/cpp.html) (distinct from the `ext/` loadable extension in this repo).

```cpp
#include "duckdb.hpp"

duckdb::DuckDB db;                 // or DuckDB("analysis.duckdb")
duckdb::Connection con(db);
con.Query("INSTALL spatial");
con.Query("LOAD spatial");
// Query cnshift.sql statement-by-statement, or open a CLI-injected file
con.Query("SELECT wgs84_to_gcj02(31.2304, 121.4737)");
```

Tertiary clients (Dart / Julia / PHP / Swift, etc.): [Tertiary Clients](https://duckdb.org/docs/current/clients/tertiary_clients/overview.html) — same pattern: `LOAD spatial` + full `cnshift.sql`.

No CGCS2000-named APIs: `ST_Transform` to EPSG:4326 first. Bootstrap notes: [docs/bootstrap.md](docs/bootstrap.md). Optional self-hosted Metabase: [docs/metabase.md](docs/metabase.md).

## Public functions (contract)

| Function | Point | Geometry | Description |
| :--- | :--- | :--- | :--- |
| `wgs84_to_gcj02` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | WGS-84 to GCJ-02 |
| `gcj02_to_wgs84` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | GCJ-02 to WGS-84 |
| `gcj02_to_bd09` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | GCJ-02 to BD-09 |
| `bd09_to_gcj02` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | BD-09 to GCJ-02 |
| `wgs84_to_bd09` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | WGS-84 to BD-09 |
| `bd09_to_wgs84` | `(lat, lon) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | BD-09 to WGS-84 |
| `wgs84_to_shcs2000` | `(lat, lon) → STRUCT(x, y)` | `(geom) → GEOMETRY` | WGS-84 to SHCS2000 (meters) |
| `shcs2000_to_wgs84` | `(x, y) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | SHCS2000 (meters) to WGS-84 |
| `gcj02_to_shcs2000` | `(lat, lon) → STRUCT(x, y)` | `(geom) → GEOMETRY` | GCJ-02 to SHCS2000 (meters) |
| `shcs2000_to_gcj02` | `(x, y) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | SHCS2000 (meters) to GCJ-02 |
| `bd09_to_shcs2000` | `(lat, lon) → STRUCT(x, y)` | `(geom) → GEOMETRY` | BD-09 to SHCS2000 (meters) |
| `shcs2000_to_bd09` | `(x, y) → STRUCT(lat, lon)` | `(geom) → GEOMETRY` | SHCS2000 (meters) to BD-09 |

Invalid or non-finite coordinates return `NULL` in the SQL macro track, and raise `OutOfRangeException` in the C++ extension. Outside the China bounding box, coordinates pass through unchanged (for geographic transforms). Full semantics: [`.specs/03_API_CONTRACT.md`](.specs/03_API_CONTRACT.md). Version tags: `sql-v*` / `ext-v*` — [docs/VERSIONING.md](docs/VERSIONING.md).

Maintainer regression: `bash test/sql/run_sql_track.sh` (requires a local `duckdb` CLI).

## C++ extension (optional fallback)

Private, unsigned `cnshift.duckdb_extension`. Same six SQL names as the macros; **not** listed on community-extensions. There is no `INSTALL cnshift FROM community`.

**Most users should stay on [`sql/cnshift.sql`](#how-to-use-no-make)** (no extension binary). Use this track only if you want a loadable `.duckdb_extension`.

### Download a prebuilt (no `make`)

1. Use DuckDB **v1.5.5** (`SELECT version();`) and note `PRAGMA platform;` (for example `osx_arm64`).
2. Open the latest [`ext-v*` GitHub Release](https://github.com/tshelianthus/duckdb-cn-shift/releases) and download  
   `cnshift-<tag>-duckdb-v1.5.5-<platform>.duckdb_extension`.
3. Allow unsigned extensions and `LOAD` the file:

```bash
duckdb -unsigned
```

```sql
LOAD '/abs/path/cnshift-ext-v0.1.0-duckdb-v1.5.5-osx_arm64.duckdb_extension';
SELECT wgs84_to_gcj02(31.2304, 121.4737);
```

Python:

```python
import duckdb
con = duckdb.connect(config={"allow_unsigned_extensions": "true"})
con.execute("LOAD '/abs/path/cnshift.duckdb_extension'")
```

Platform table, Wasm assets, and checksums: [ext/README.md](ext/README.md). Do not download GitHub Actions artifacts (they expire).

### Build from source

Needs git submodules (DuckDB + `extension-ci-tools`). Use this when no Release asset matches your DuckDB version or platform, or when developing the C++ track.

```bash
git submodule update --init --recursive
make release
make test_release
```

Then `LOAD` `build/release/extension/cnshift/cnshift.duckdb_extension` with the unsigned flag above. Format/tidy gates and layout: [ext/README.md](ext/README.md). Root `src/` is a pointer, not a second implementation.

## Docs index

| Doc | Content |
| :--- | :--- |
| [docs/DECISIONS.md](docs/DECISIONS.md) | ADRs: dual-track, no community submit, intentional divergences |
| [docs/bootstrap.md](docs/bootstrap.md) | Bootstrap / injection |
| [docs/CI.md](docs/CI.md) | Path filters; `ext-v*` GitHub Release |
| [docs/metabase.md](docs/metabase.md) | Self-hosted Metabase + community DuckDB driver (optional) |
| [testdata/golden/](testdata/golden/) | Shared golden fixtures |

## Acknowledgments

This project acknowledges [geocompass/pg-coordtransform](https://github.com/geocompass/pg-coordtransform) for inspiring the SQL macro functional layout and coordinate offset patterns.

## Disclaimer

This software is provided "AS IS", without warranty of any kind. 

1. **Purpose Limitation**: Intended strictly for technical computing, internal data cleaning, and experimental analytics. Prohibited for state secrets, military installations, or commercial mapping requiring statutory licenses.
2. **User Responsibility**: Users bear sole responsibility for regulatory compliance, legal data sourcing, and obtaining requisite licenses under applicable surveying and data security laws.
3. **Approximation & No Warranty**: Algorithms are open-source community empirical approximations carrying zero legal validity and no surveying accuracy warranty.
4. **Limitation of Liability**: Authors and contributors assume no liability for any direct, indirect, regulatory, or consequential damages.

For full terms and user confirmation conditions, see [DISCLAIMER.md](DISCLAIMER.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
