# Metabase + cnshift (optional / personal)

Notes for self-hosted Metabase + the community [DuckDB driver](https://github.com/motherduckdb/metabase_duckdb_driver). Not the product main path.

There is **no** Metabase plugin named cnshift. The driver embeds DuckDB in the Metabase process; macros still come from SQL injected into the **current connection**.

Use driver **≥ 1.4.3.1** ([Init SQL per connection](https://github.com/motherduckdb/metabase_duckdb_driver/releases/tag/1.4.3.1)). Metabase Cloud does not support custom drivers. Official **Alpine** images fail on glibc with this JAR; use the driver’s Debian image.

## Do not confuse these

| Item | Persistent `.duckdb` file | `:memory:` database |
| :--- | :--- | :--- |
| `CREATE MACRO` | Stored in catalog while the file exists | **Gone when the connection dies**; rebuild on every Init |
| `LOAD spatial` | Every new connection | Every new connection |
| `INSTALL spatial` | Once per machine/container | Usually also in the same Init (idempotent) |

`.read` is a CLI dot-command; Init SQL / JDBC **do not** have it. Never put `.read 'sql/cnshift.sql'` in Init SQL.

---

## In-memory: required prep

Habit: Database file = `:memory:`, Init SQL on every connection. Memory has **no** macros from last time, so Init must include all of:

1. `INSTALL spatial;`
2. `LOAD spatial;`
3. The **full** `sql/cnshift.sql` (all `CREATE MACRO`)

Do not put only `LOAD spatial` in Init — point kernels may work; geometry overloads fail without Spatial constructors.

### 1. Build a merged script (prep)

From the repo root:

```bash
bash sql/build-init-memory.sh
```

Writes `sql/init-memory.sql` (gitignored; do not hand-edit). Re-run after changing `cnshift.sql`. In Docker, run the same command before `up` or in an entrypoint.

### 2. Compose: mount the script (no `.duckdb` required)

```yaml
services:
  metabase:
    image: metabase_duckdb:latest
    ports:
      - "3000:3000"
    environment:
      MB_PLUGINS_DIR: /plugins
    volumes:
      - ./plugins:/plugins
      - ./sql/init-memory.sql:/sql/init-memory.sql:ro
```

Put [duckdb.metabase-driver.jar](https://github.com/MotherDuck-Open-Source/metabase_duckdb_driver/releases/latest) under `plugins/`.

### 3. Metabase connection (in-memory)

Admin → Databases → Add → **DuckDB**:

| Field | Value |
| :--- | :--- |
| Database file | `:memory:` |
| Read-only | **Off** (Init needs `CREATE MACRO`) |
| Init SQL | See two options below; **pick one**, do not run both |

**Option A (preferred):** Additional DuckDB connection string options:

```text
session_init_sql_file=/sql/init-memory.sql
```

DuckDB JDBC session init file (driver ~1.3.1+). Leave the Init SQL box empty. Container path must match the volume.

**Option B:** Paste the **entire** `sql/init-memory.sql` into Init SQL. Use A if the box is too small or JDBC rejects multi-statement `execute`.

Do not put only `INSTALL spatial; LOAD spatial;` in Init — macros vanish on the next memory connection.

### 4. Queries

Native query:

```sql
SELECT
  wgs84_to_gcj02(lat, lon).lat AS gcj_lat,
  wgs84_to_gcj02(lat, lon).lon AS gcj_lon
FROM your_table;
```

Lines/polygons: `SELECT wgs84_to_gcj02(geom) FROM parcels;`  
GEOMETRY columns may display poorly in Metabase ([issue #49](https://github.com/motherduckdb/metabase_duckdb_driver/issues/49)); STRUCT or `ST_X` / `ST_Y` is safer for points.

---

## Alternative: persistent file

For a file DB, inject macros once; Init SQL only needs spatial:

```bash
mkdir -p data
duckdb data/gis.duckdb -c "INSTALL spatial; LOAD spatial; .read 'sql/cnshift.sql'"
```

Database file = `/data/gis.duckdb` (mount `./data:/data`). Init SQL:

```sql
INSTALL spatial;
LOAD spatial;
```

Read-only may be on (do not create macros at connect time).
