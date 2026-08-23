-- sql_track.test.sql — SQL-path golden + structural tests
-- Run from repository root:
--   duckdb -bail < test/sql/sql_track.test.sql
--
-- Expectation source: testdata/golden/ (shared with future C++ tests).

INSTALL spatial;
LOAD spatial;
.read sql/cnshift.sql

-- ---------------------------------------------------------------------------
-- Point goldens
-- ---------------------------------------------------------------------------

CREATE OR REPLACE MACRO cn_test_point(op, lat, lon) AS (
	CASE op
		WHEN 'wgs84_to_gcj02' THEN wgs84_to_gcj02(lat, lon)
		WHEN 'gcj02_to_wgs84' THEN gcj02_to_wgs84(lat, lon)
		WHEN 'gcj02_to_bd09' THEN gcj02_to_bd09(lat, lon)
		WHEN 'bd09_to_gcj02' THEN bd09_to_gcj02(lat, lon)
		WHEN 'wgs84_to_bd09' THEN wgs84_to_bd09(lat, lon)
		WHEN 'bd09_to_wgs84' THEN bd09_to_wgs84(lat, lon)
		WHEN 'wgs84_to_shcs2000' THEN {
			'lat': wgs84_to_shcs2000(lat, lon).y,
			'lon': wgs84_to_shcs2000(lat, lon).x
		}
		ELSE NULL
	END
);

CREATE TABLE point_failures AS
SELECT
	id,
	op,
	got.lat AS got_lat,
	got.lon AS got_lon,
	expect_lat,
	expect_lon
FROM (
	SELECT
		id,
		op,
		cn_test_point(op, in_lat, in_lon) AS got,
		expect_lat,
		expect_lon
	FROM read_csv_auto('testdata/golden/points.csv')
)
WHERE abs(got.lat - expect_lat) > 1e-6
	OR abs(got.lon - expect_lon) > 1e-6
	OR got IS NULL;

SELECT CASE
	WHEN (SELECT count(*) FROM point_failures) = 0 THEN 'PASS points'
	ELSE error('point golden mismatches: ' || (SELECT string_agg(id, ', ') FROM point_failures))
END AS point_goldens;

-- ---------------------------------------------------------------------------
-- Geometry goldens (type, part count, holes, vertices)
-- ---------------------------------------------------------------------------

CREATE TABLE geom_rows AS
SELECT
	id,
	op,
	note,
	expect_type,
	expect_num_geometries,
	expect_num_interior_rings,
	expect_num_points,
	expect_vertices,
	ST_GeomFromText(input_wkt) AS gin,
	wgs84_to_gcj02(ST_GeomFromText(input_wkt)) AS gout
FROM read_json('testdata/golden/geometries.jsonl', format := 'newline_delimited')
WHERE op = 'wgs84_to_gcj02'
UNION ALL
SELECT
	id,
	op,
	note,
	expect_type,
	expect_num_geometries,
	expect_num_interior_rings,
	expect_num_points,
	expect_vertices,
	ST_GeomFromText(input_wkt) AS gin,
	gcj02_to_bd09(ST_GeomFromText(input_wkt)) AS gout
FROM read_json('testdata/golden/geometries.jsonl', format := 'newline_delimited')
WHERE op = 'gcj02_to_bd09'
UNION ALL
SELECT
	id,
	op,
	note,
	expect_type,
	expect_num_geometries,
	expect_num_interior_rings,
	expect_num_points,
	expect_vertices,
	ST_GeomFromText(input_wkt) AS gin,
	wgs84_to_shcs2000(ST_GeomFromText(input_wkt)) AS gout
FROM read_json('testdata/golden/geometries.jsonl', format := 'newline_delimited')
WHERE op = 'wgs84_to_shcs2000';

CREATE TABLE geom_failures AS
SELECT id, reason
FROM (
	SELECT
		id,
		CASE
			WHEN gout IS NULL THEN 'null output'
			WHEN ST_GeometryType(gout)::VARCHAR != expect_type THEN 'type ' || ST_GeometryType(gout)::VARCHAR || ' != ' || expect_type
			WHEN ST_NumGeometries(gout) IS DISTINCT FROM expect_num_geometries THEN 'num_geometries'
			WHEN expect_num_interior_rings IS NOT NULL
				AND ST_NInteriorRings(gout) IS DISTINCT FROM expect_num_interior_rings THEN 'holes'
			WHEN ST_NPoints(gout) IS DISTINCT FROM expect_num_points THEN 'npoints'
			WHEN len(ST_Dump(ST_Points(gout))) != len(expect_vertices) THEN 'vertex count'
			WHEN list_reduce(
				list_transform(
					generate_series(1, len(expect_vertices)::BIGINT),
					lambda i:
						abs(ST_X(ST_Dump(ST_Points(gout))[i].geom) - expect_vertices[i][1]) > 1e-6
						OR abs(ST_Y(ST_Dump(ST_Points(gout))[i].geom) - expect_vertices[i][2]) > 1e-6
				),
				lambda acc, x: acc OR x
			) THEN 'vertex values'
			ELSE NULL
		END AS reason
	FROM geom_rows
)
WHERE reason IS NOT NULL;

SELECT CASE
	WHEN (SELECT count(*) FROM geom_failures) = 0 THEN 'PASS geometries'
	ELSE error('geometry golden mismatches: ' || (SELECT string_agg(id || ':' || reason, ', ') FROM geom_failures))
END AS geometry_goldens;

-- ---------------------------------------------------------------------------
-- Structural / API behaviour (not duplicated as formula tables)
-- ---------------------------------------------------------------------------

SELECT CASE
	WHEN wgs84_to_gcj02(NULL, 121.4737) IS NULL
		AND wgs84_to_gcj02(31.2304, NULL) IS NULL
		AND wgs84_to_gcj02(NULL::GEOMETRY) IS NULL
		THEN 'PASS null'
	ELSE error('NULL handling')
END AS null_handling;

CREATE TABLE range_check AS
SELECT
	wgs84_to_gcj02(91, 0) AS lat_hi,
	wgs84_to_gcj02(-91, 0) AS lat_lo,
	wgs84_to_gcj02(0, 181) AS lon_hi,
	wgs84_to_gcj02(0, 'inf'::DOUBLE) AS inf_lon,
	wgs84_to_gcj02('nan'::DOUBLE, 0) AS nan_lat;

SELECT CASE
	WHEN lat_hi IS NULL AND lat_lo IS NULL AND lon_hi IS NULL
		AND inf_lon IS NULL AND nan_lat IS NULL
		THEN 'PASS range'
	ELSE error('out-of-range / non-finite should be NULL')
END AS range_handling
FROM range_check;

CREATE TABLE empty_check AS
SELECT
	wgs84_to_gcj02(ST_GeomFromText('POINT EMPTY')) AS p,
	wgs84_to_gcj02(ST_GeomFromText('LINESTRING EMPTY')) AS l,
	wgs84_to_gcj02(ST_GeomFromText('POLYGON EMPTY')) AS poly,
	wgs84_to_gcj02(ST_GeomFromText('MULTIPOLYGON EMPTY')) AS mp;

SELECT CASE
	WHEN ST_IsEmpty(p) AND ST_IsEmpty(l) AND ST_IsEmpty(poly) AND ST_IsEmpty(mp)
		THEN 'PASS empty'
	ELSE error('empty geometry should pass through')
END AS empty_geom
FROM empty_check;

-- Adjacent MultiPolygon parts must not be union-merged (ADR-008).
CREATE TABLE touching_multi AS
SELECT wgs84_to_gcj02(ST_GeomFromText(
	'MULTIPOLYGON (((121.47 31.23, 121.48 31.23, 121.48 31.24, 121.47 31.24, 121.47 31.23)), ((121.48 31.23, 121.49 31.23, 121.49 31.24, 121.48 31.24, 121.48 31.23)))'
)) AS g;

SELECT CASE
	WHEN ST_GeometryType(g)::VARCHAR = 'MULTIPOLYGON' AND ST_NumGeometries(g) = 2
		THEN 'PASS multi-collect'
	ELSE error('MultiPolygon parts were merged; ST_Union must not be used')
END AS multi_collect
FROM touching_multi;

-- Combination path equals composed steps (bind stepwise; nested macros explode).
CREATE TABLE compose_src AS
SELECT
	31.2304 AS lat,
	121.4737 AS lon,
	wgs84_to_gcj02(31.2304, 121.4737) AS wgs_gcj,
	wgs84_to_bd09(31.2304, 121.4737) AS wgs_bd,
	bd09_to_gcj02(31.2304, 121.4737) AS bd_gcj,
	bd09_to_wgs84(31.2304, 121.4737) AS bd_wgs;

CREATE TABLE compose_steps AS
SELECT
	gcj02_to_bd09(wgs_gcj.lat, wgs_gcj.lon) AS wgs_bd_via_gcj,
	gcj02_to_wgs84(bd_gcj.lat, bd_gcj.lon) AS bd_wgs_via_gcj
FROM compose_src;

SELECT CASE
	WHEN abs(s.wgs_bd.lat - t.wgs_bd_via_gcj.lat) < 1e-12
		AND abs(s.wgs_bd.lon - t.wgs_bd_via_gcj.lon) < 1e-12
		THEN 'PASS compose wgs-bd'
	ELSE error('wgs84_to_bd09 != gcj02_to_bd09(wgs84_to_gcj02)')
END AS compose_wgs_bd
FROM compose_src s, compose_steps t;

SELECT CASE
	WHEN abs(s.bd_wgs.lat - t.bd_wgs_via_gcj.lat) < 1e-12
		THEN 'PASS compose bd-wgs'
	ELSE error('bd09_to_wgs84 != gcj02_to_wgs84(bd09_to_gcj02)')
END AS compose_bd_wgs
FROM compose_src s, compose_steps t;

-- Geometry point matches the point overload (ST_X=lon, ST_Y=lat).
CREATE TABLE point_both AS
SELECT
	wgs84_to_gcj02(31.2304, 121.4737) AS pt,
	wgs84_to_gcj02(ST_Point(121.4737, 31.2304)) AS geom;

SELECT CASE
	WHEN abs(ST_Y(geom) - pt.lat) < 1e-12
		AND abs(ST_X(geom) - pt.lon) < 1e-12
		THEN 'PASS point geom overload'
	ELSE error('geometry POINT disagrees with (lat, lon) overload')
END AS point_geom_overload
FROM point_both;

-- SHCS2000 Point & Geometry overloads match (including alias check)
CREATE TABLE sh_point_both AS
SELECT
	wgs84_to_shcs2000(31.2304, 121.4737) AS pt,
	wgs84_to_shcs2000(ST_Point(121.4737, 31.2304)) AS geom,
	wgs84_to_shanghai2000(31.2304, 121.4737) AS pt_alias;

SELECT CASE
	WHEN abs(ST_X(geom) - pt.x) < 1e-9
		AND abs(ST_Y(geom) - pt.y) < 1e-9
		AND abs(pt_alias.x - pt.x) < 1e-9
		AND abs(pt_alias.y - pt.y) < 1e-9
		THEN 'PASS shcs2000 point geom overload & alias'
	ELSE error('shcs2000 geometry POINT or alias disagrees with (lat, lon) overload')
END AS sh_point_geom_overload
FROM sh_point_both;

-- SHCS2000 Roundtrip (< 0.1 mm precision)
CREATE TABLE sh2000_roundtrip AS
SELECT
	lat,
	lon,
	wgs84_to_shcs2000(lat, lon) AS fwd,
	shcs2000_to_wgs84(wgs84_to_shcs2000(lat, lon).x, wgs84_to_shcs2000(lat, lon).y) AS rev
FROM (
	VALUES
		(31.2304, 121.4737),
		(31.2500, 121.4500),
		(31.0000, 121.5000),
		(31.5000, 121.3000)
) AS t(lat, lon);

SELECT CASE
	WHEN (SELECT max(abs(rev.lat - lat) + abs(rev.lon - lon)) FROM sh2000_roundtrip) < 1e-8
		THEN 'PASS shcs2000 roundtrip'
	ELSE error('shcs2000 roundtrip error exceeded tolerance')
END AS sh2000_rt;

SELECT 'PASS sql-track' AS summary;
