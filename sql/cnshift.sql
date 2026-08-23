-- cnshift.sql — DuckDB China CRS offset macros (primary delivery)
--
-- Algorithm constants and formulae: docs/ALGORITHM.md (single source of truth).
-- Do not diverge without updating that document and shared golden fixtures.
--
-- Product decisions:                 docs/DECISIONS.md
-- Bootstrap:                         docs/bootstrap.md
-- Version tags:                      sql-v* (see docs/VERSIONING.md)
-- Public SQL surface:                .specs/03_API_CONTRACT.md
--
-- NOT submitted to duckdb/community-extensions (legal / compliance; see DECISIONS).
--
-- Requires: INSTALL spatial; LOAD spatial;
-- Geometry rebuild uses ST_Collect / ST_Multi (never ST_Union). Polygon holes
-- use ST_MakePolygon(shell, holes[]) + ST_ExteriorRing / ST_Dump(ST_Boundary).
-- GeometryCollection: ST_Dump flattens nested collections (limited depth);
-- homogeneous collections may collect back as Multi* (documented flatten).

-- ---------------------------------------------------------------------------
-- Kernel (docs/ALGORITHM.md §§1–6)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE MACRO cn__a() AS 6378245.0;                     -- ellipsoid a
CREATE OR REPLACE MACRO cn__ee() AS 0.006693421622965823;          -- ee (pg geoc_delta)
CREATE OR REPLACE MACRO cn__x_pi() AS (pi() * 3000.0 / 180.0);     -- BD polar rotation
CREATE OR REPLACE MACRO cn__bd_lon() AS 0.0065;
CREATE OR REPLACE MACRO cn__bd_lat() AS 0.006;
CREATE OR REPLACE MACRO cn__bd_z() AS 0.00002;
CREATE OR REPLACE MACRO cn__bd_theta() AS 0.000003;

CREATE OR REPLACE MACRO cn__in_china_bbox(lon, lat) AS (
	lon >= 72.004 AND lon <= 137.8347 AND lat >= 0.8293 AND lat <= 55.8271
);

CREATE OR REPLACE MACRO cn__finite_latlon(lat, lon) AS (
	lat IS NOT NULL AND lon IS NOT NULL
	AND NOT isnan(lat) AND NOT isnan(lon)
	AND NOT isinf(lat) AND NOT isinf(lon)
	AND lat >= -90.0 AND lat <= 90.0
	AND lon >= -180.0 AND lon <= 180.0
);

-- transform_lat(x, y) with x = lon-105, y = lat-35
CREATE OR REPLACE MACRO cn__transform_lat(x, y) AS (
	(-100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x)))
	+ (20.0 * sin(6.0 * x * pi()) + 20.0 * sin(2.0 * x * pi())) * 2.0 / 3.0
	+ (20.0 * sin(y * pi()) + 40.0 * sin(y / 3.0 * pi())) * 2.0 / 3.0
	+ (160.0 * sin(y / 12.0 * pi()) + 320.0 * sin(y * pi() / 30.0)) * 2.0 / 3.0
);

-- transform_lon(x, y) with x = lon-105, y = lat-35
CREATE OR REPLACE MACRO cn__transform_lon(x, y) AS (
	(300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x)))
	+ (20.0 * sin(6.0 * x * pi()) + 20.0 * sin(2.0 * x * pi())) * 2.0 / 3.0
	+ (20.0 * sin(x * pi()) + 40.0 * sin(x / 3.0 * pi())) * 2.0 / 3.0
	+ (150.0 * sin(x / 12.0 * pi()) + 300.0 * sin(x / 30.0 * pi())) * 2.0 / 3.0
);

CREATE OR REPLACE MACRO cn__magic(lat) AS (
	1.0 - cn__ee() * sin(lat / 180.0 * pi()) * sin(lat / 180.0 * pi())
);

CREATE OR REPLACE MACRO cn__delta_lon(lon, lat) AS (
	(cn__transform_lon(lon - 105.0, lat - 35.0) * 180.0)
	/ (cn__a() / sqrt(cn__magic(lat)) * cos(lat / 180.0 * pi()) * pi())
);

CREATE OR REPLACE MACRO cn__delta_lat(lon, lat) AS (
	(cn__transform_lat(lon - 105.0, lat - 35.0) * 180.0)
	/ ((cn__a() * (1.0 - cn__ee())) / (cn__magic(lat) * sqrt(cn__magic(lat))) * pi())
);

-- XY kernels return STRUCT(lon, lat). Public point API is (lat, lon) → STRUCT(lat, lon).

CREATE OR REPLACE MACRO cn__wgs84_to_gcj02_xy(lon, lat) AS (
	CASE
		WHEN NOT cn__in_china_bbox(lon, lat) THEN {'lon': lon, 'lat': lat}
		ELSE {'lon': lon + cn__delta_lon(lon, lat), 'lat': lat + cn__delta_lat(lon, lat)}
	END
);

-- GCJ→WGS: one-shot 2p - forward(p). Not iterative.
CREATE OR REPLACE MACRO cn__gcj02_to_wgs84_xy(lon, lat) AS (
	CASE
		WHEN NOT cn__in_china_bbox(lon, lat) THEN {'lon': lon, 'lat': lat}
		ELSE {
			'lon': lon * 2.0 - cn__wgs84_to_gcj02_xy(lon, lat).lon,
			'lat': lat * 2.0 - cn__wgs84_to_gcj02_xy(lon, lat).lat
		}
	END
);

CREATE OR REPLACE MACRO cn__gcj02_to_bd09_xy(lon, lat) AS (
	CASE
		WHEN NOT cn__in_china_bbox(lon, lat) THEN {'lon': lon, 'lat': lat}
		ELSE {
			'lon': (sqrt(lon * lon + lat * lat) + cn__bd_z() * sin(lat * cn__x_pi()))
				* cos(atan2(lat, lon) + cn__bd_theta() * cos(lon * cn__x_pi()))
				+ cn__bd_lon(),
			'lat': (sqrt(lon * lon + lat * lat) + cn__bd_z() * sin(lat * cn__x_pi()))
				* sin(atan2(lat, lon) + cn__bd_theta() * cos(lon * cn__x_pi()))
				+ cn__bd_lat()
		}
	END
);

CREATE OR REPLACE MACRO cn__bd09_to_gcj02_xy(lon, lat) AS (
	CASE
		WHEN NOT cn__in_china_bbox(lon, lat) THEN {'lon': lon, 'lat': lat}
		ELSE {
			'lon': (
				sqrt((lon - cn__bd_lon()) * (lon - cn__bd_lon())
					+ (lat - cn__bd_lat()) * (lat - cn__bd_lat()))
				- cn__bd_z() * sin((lat - cn__bd_lat()) * cn__x_pi())
			) * cos(
				atan2(lat - cn__bd_lat(), lon - cn__bd_lon())
				- cn__bd_theta() * cos((lon - cn__bd_lon()) * cn__x_pi())
			),
			'lat': (
				sqrt((lon - cn__bd_lon()) * (lon - cn__bd_lon())
					+ (lat - cn__bd_lat()) * (lat - cn__bd_lat()))
				- cn__bd_z() * sin((lat - cn__bd_lat()) * cn__x_pi())
			) * sin(
				atan2(lat - cn__bd_lat(), lon - cn__bd_lon())
				- cn__bd_theta() * cos((lon - cn__bd_lon()) * cn__x_pi())
			)
		}
	END
);

CREATE OR REPLACE MACRO cn__wgs84_to_bd09_xy(lon, lat) AS (
	cn__gcj02_to_bd09_xy(
		cn__wgs84_to_gcj02_xy(lon, lat).lon,
		cn__wgs84_to_gcj02_xy(lon, lat).lat
	)
);

CREATE OR REPLACE MACRO cn__bd09_to_wgs84_xy(lon, lat) AS (
	cn__gcj02_to_wgs84_xy(
		cn__bd09_to_gcj02_xy(lon, lat).lon,
		cn__bd09_to_gcj02_xy(lon, lat).lat
	)
);

CREATE OR REPLACE MACRO cn__xy(kind, lon, lat) AS (
	CASE kind
		WHEN 'wgs84_to_gcj02' THEN cn__wgs84_to_gcj02_xy(lon, lat)
		WHEN 'gcj02_to_wgs84' THEN cn__gcj02_to_wgs84_xy(lon, lat)
		WHEN 'gcj02_to_bd09' THEN cn__gcj02_to_bd09_xy(lon, lat)
		WHEN 'bd09_to_gcj02' THEN cn__bd09_to_gcj02_xy(lon, lat)
		WHEN 'wgs84_to_bd09' THEN cn__wgs84_to_bd09_xy(lon, lat)
		WHEN 'bd09_to_wgs84' THEN cn__bd09_to_wgs84_xy(lon, lat)
		ELSE {'lon': lon, 'lat': lat}
	END
);

CREATE OR REPLACE MACRO cn__point_out(kind, lat, lon) AS (
	CASE
		WHEN NOT cn__finite_latlon(lat, lon) THEN NULL
		ELSE {
			'lat': cn__xy(kind, lon, lat).lat,
			'lon': cn__xy(kind, lon, lat).lon
		}
	END
);

-- ---------------------------------------------------------------------------
-- Geometry: vertex map (no user dump). Macros are not recursive.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE MACRO cn__point_geom(kind, g) AS (
	ST_Point(
		cn__xy(kind, ST_X(g), ST_Y(g)).lon,
		cn__xy(kind, ST_X(g), ST_Y(g)).lat
	)
);

CREATE OR REPLACE MACRO cn__line_geom(kind, g) AS (
	ST_MakeLine(
		list_transform(
			generate_series(1, ST_NPoints(g)::BIGINT),
			lambda i: ST_Point(
				cn__xy(
					kind,
					ST_X(ST_PointN(g, i::INTEGER)),
					ST_Y(ST_PointN(g, i::INTEGER))
				).lon,
				cn__xy(
					kind,
					ST_X(ST_PointN(g, i::INTEGER)),
					ST_Y(ST_PointN(g, i::INTEGER))
				).lat
			)
		)
	)
);

-- Holes: ST_Boundary of a Polygon-with-holes is MultiLineString; ST_Dump path[1]>1
-- are interior rings. Simple polygons dump a LineString with empty path → no holes.
CREATE OR REPLACE MACRO cn__poly_geom(kind, g) AS (
	ST_MakePolygon(
		cn__line_geom(kind, ST_ExteriorRing(g)),
		list_transform(
			list_filter(
				ST_Dump(ST_Boundary(g)),
				lambda ring: len(ring.path) > 0 AND ring.path[1] > 1
			),
			lambda ring: cn__line_geom(kind, ring.geom)
		)
	)
);

CREATE OR REPLACE MACRO cn__atomic_geom(kind, g) AS (
	CASE ST_GeometryType(g)
		WHEN 'POINT' THEN cn__point_geom(kind, g)
		WHEN 'LINESTRING' THEN cn__line_geom(kind, g)
		WHEN 'POLYGON' THEN cn__poly_geom(kind, g)
		ELSE NULL
	END
);

-- Multi*: dump parts → atomic → ST_Collect (not ST_Union) → ST_Multi
CREATE OR REPLACE MACRO cn__multi_geom(kind, g) AS (
	ST_Multi(
		ST_Collect(
			list_transform(
				ST_Dump(g),
				lambda part: cn__atomic_geom(kind, part.geom)
			)
		)
	)
);

-- GeometryCollection: flatten via ST_Dump (nested collections included), then collect.
CREATE OR REPLACE MACRO cn__collection_geom(kind, g) AS (
	ST_Collect(
		list_transform(
			ST_Dump(g),
			lambda part: cn__atomic_geom(kind, part.geom)
		)
	)
);

CREATE OR REPLACE MACRO cn__geom(kind, g) AS (
	CASE
		WHEN g IS NULL THEN NULL
		WHEN ST_IsEmpty(g) THEN g
		WHEN ST_GeometryType(g) = 'POINT' THEN cn__point_geom(kind, g)
		WHEN ST_GeometryType(g) = 'LINESTRING' THEN cn__line_geom(kind, g)
		WHEN ST_GeometryType(g) = 'POLYGON' THEN cn__poly_geom(kind, g)
		WHEN ST_GeometryType(g) IN ('MULTIPOINT', 'MULTILINESTRING', 'MULTIPOLYGON')
			THEN cn__multi_geom(kind, g)
		WHEN ST_GeometryType(g) = 'GEOMETRYCOLLECTION' THEN cn__collection_geom(kind, g)
		ELSE NULL
	END
);

-- ---------------------------------------------------------------------------
-- Public API (point STRUCT + GEOMETRY overloads)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE MACRO wgs84_to_gcj02
	(lat, lon) AS cn__point_out('wgs84_to_gcj02', lat, lon),
	(geom) AS cn__geom('wgs84_to_gcj02', geom);

CREATE OR REPLACE MACRO gcj02_to_wgs84
	(lat, lon) AS cn__point_out('gcj02_to_wgs84', lat, lon),
	(geom) AS cn__geom('gcj02_to_wgs84', geom);

CREATE OR REPLACE MACRO gcj02_to_bd09
	(lat, lon) AS cn__point_out('gcj02_to_bd09', lat, lon),
	(geom) AS cn__geom('gcj02_to_bd09', geom);

CREATE OR REPLACE MACRO bd09_to_gcj02
	(lat, lon) AS cn__point_out('bd09_to_gcj02', lat, lon),
	(geom) AS cn__geom('bd09_to_gcj02', geom);

CREATE OR REPLACE MACRO wgs84_to_bd09
	(lat, lon) AS cn__point_out('wgs84_to_bd09', lat, lon),
	(geom) AS cn__geom('wgs84_to_bd09', geom);

CREATE OR REPLACE MACRO bd09_to_wgs84
	(lat, lon) AS cn__point_out('bd09_to_wgs84', lat, lon),
	(geom) AS cn__geom('bd09_to_wgs84', geom);
