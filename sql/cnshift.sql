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

-- ---------------------------------------------------------------------------
-- Shanghai 2000 (SHCS2000) Geodetic Constants & Formulae (docs/ALGORITHM.md §7)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE MACRO sh__a_eff() AS 6378153.3398::DOUBLE;
CREATE OR REPLACE MACRO sh__e2() AS 0.006694380022900787::DOUBLE;
CREATE OR REPLACE MACRO sh__ep2() AS 0.006739496775498909::DOUBLE;
CREATE OR REPLACE MACRO sh__l0() AS 121.46444444444444::DOUBLE;
CREATE OR REPLACE MACRO sh__l0_rad() AS (121.46444444444444::DOUBLE * pi() / 180.0::DOUBLE);
CREATE OR REPLACE MACRO sh__x_orig() AS 3457087.73141366::DOUBLE;
CREATE OR REPLACE MACRO sh__y_orig() AS 257.85859273::DOUBLE;

CREATE OR REPLACE MACRO sh__k0() AS 6367465.458133294::DOUBLE;
CREATE OR REPLACE MACRO sh__k2() AS 16038.549782158::DOUBLE;
CREATE OR REPLACE MACRO sh__k4() AS 16.832642939::DOUBLE;
CREATE OR REPLACE MACRO sh__k6() AS 0.021981053::DOUBLE;
CREATE OR REPLACE MACRO sh__m0_bar() AS 6367465.45832782::DOUBLE;
CREATE OR REPLACE MACRO sh__c1() AS 0.002518826597::DOUBLE;
CREATE OR REPLACE MACRO sh__c2() AS 0.000003700949::DOUBLE;
CREATE OR REPLACE MACRO sh__c3() AS 0.000000007448::DOUBLE;
CREATE OR REPLACE MACRO sh__c4() AS 0.000000000017::DOUBLE;

CREATE OR REPLACE MACRO cn__finite_xy(x, y) AS (
	x IS NOT NULL AND y IS NOT NULL
	AND NOT isnan(x) AND NOT isnan(y)
	AND NOT isinf(x) AND NOT isinf(y)
);

CREATE OR REPLACE MACRO sh__b(lat) AS (lat::DOUBLE * pi() / 180.0::DOUBLE);
CREATE OR REPLACE MACRO sh__l(lon) AS ((lon::DOUBLE * pi() / 180.0::DOUBLE) - sh__l0_rad());
CREATE OR REPLACE MACRO sh__sin_b(lat) AS (sin(sh__b(lat)));
CREATE OR REPLACE MACRO sh__cos_b(lat) AS (cos(sh__b(lat)));
CREATE OR REPLACE MACRO sh__t(lat) AS (tan(sh__b(lat)));
CREATE OR REPLACE MACRO sh__n(lat) AS (sh__a_eff() / sqrt(1.0::DOUBLE - sh__e2() * sh__sin_b(lat) * sh__sin_b(lat)));
CREATE OR REPLACE MACRO sh__eta2(lat) AS (sh__ep2() * sh__cos_b(lat) * sh__cos_b(lat));
CREATE OR REPLACE MACRO sh__x_arc(lat) AS (
	sh__k0() * sh__b(lat) - sh__k2() * sin(2.0::DOUBLE * sh__b(lat)) + sh__k4() * sin(4.0::DOUBLE * sh__b(lat)) - sh__k6() * sin(6.0::DOUBLE * sh__b(lat))
);

CREATE OR REPLACE MACRO cn__wgs84_to_shcs2000_x(lon, lat) AS (
	sh__n(lat) * sh__cos_b(lat) * sh__l(lon)
	+ sh__n(lat) * pow(sh__cos_b(lat), 3.0::DOUBLE) * (1.0::DOUBLE - sh__t(lat) * sh__t(lat) + sh__eta2(lat)) * pow(sh__l(lon), 3.0::DOUBLE) / 6.0::DOUBLE
	- sh__y_orig()
);

CREATE OR REPLACE MACRO cn__wgs84_to_shcs2000_y(lon, lat) AS (
	sh__x_arc(lat)
	+ sh__n(lat) * sh__sin_b(lat) * sh__cos_b(lat) * sh__l(lon) * sh__l(lon) / 2.0::DOUBLE
	+ sh__n(lat) * sh__sin_b(lat) * pow(sh__cos_b(lat), 3.0::DOUBLE) * (5.0::DOUBLE - sh__t(lat) * sh__t(lat) + 9.0::DOUBLE * sh__eta2(lat) + 4.0::DOUBLE * sh__eta2(lat) * sh__eta2(lat)) * pow(sh__l(lon), 4.0::DOUBLE) / 24.0::DOUBLE
	- sh__x_orig()
);

CREATE OR REPLACE MACRO cn__wgs84_to_shcs2000_xy(lon, lat) AS (
	{
		'lon': cn__wgs84_to_shcs2000_x(lon, lat),
		'lat': cn__wgs84_to_shcs2000_y(lon, lat)
	}
);

CREATE OR REPLACE MACRO sh__x_std(y_sh) AS (y_sh::DOUBLE + sh__x_orig());
CREATE OR REPLACE MACRO sh__y_std(x_sh) AS (x_sh::DOUBLE + sh__y_orig());
CREATE OR REPLACE MACRO sh__mu(y_sh) AS (sh__x_std(y_sh) / sh__m0_bar());

CREATE OR REPLACE MACRO sh__bf(y_sh) AS (
	sh__mu(y_sh)
	+ sh__c1() * sin(2.0::DOUBLE * sh__mu(y_sh))
	+ sh__c2() * sin(4.0::DOUBLE * sh__mu(y_sh))
	+ sh__c3() * sin(6.0::DOUBLE * sh__mu(y_sh))
	+ sh__c4() * sin(8.0::DOUBLE * sh__mu(y_sh))
);

CREATE OR REPLACE MACRO sh__sin_bf(y_sh) AS (sin(sh__bf(y_sh)));
CREATE OR REPLACE MACRO sh__cos_bf(y_sh) AS (cos(sh__bf(y_sh)));
CREATE OR REPLACE MACRO sh__t_f(y_sh) AS (tan(sh__bf(y_sh)));
CREATE OR REPLACE MACRO sh__eta_f2(y_sh) AS (sh__ep2() * sh__cos_bf(y_sh) * sh__cos_bf(y_sh));
CREATE OR REPLACE MACRO sh__nf(y_sh) AS (sh__a_eff() / sqrt(1.0::DOUBLE - sh__e2() * sh__sin_bf(y_sh) * sh__sin_bf(y_sh)));
CREATE OR REPLACE MACRO sh__mf(y_sh) AS (sh__a_eff() * (1.0::DOUBLE - sh__e2()) / pow(1.0::DOUBLE - sh__e2() * sh__sin_bf(y_sh) * sh__sin_bf(y_sh), 1.5::DOUBLE));

CREATE OR REPLACE MACRO cn__shcs2000_to_wgs84_lon(x_sh, y_sh) AS (
	sh__l0() + (
		(1.0::DOUBLE / (sh__nf(y_sh) * sh__cos_bf(y_sh))) * sh__y_std(x_sh)
		- ((1.0::DOUBLE + 2.0::DOUBLE * sh__t_f(y_sh) * sh__t_f(y_sh) + sh__eta_f2(y_sh)) / (6.0::DOUBLE * pow(sh__nf(y_sh), 3.0::DOUBLE) * sh__cos_bf(y_sh))) * pow(sh__y_std(x_sh), 3.0::DOUBLE)
		+ ((5.0::DOUBLE + 28.0::DOUBLE * sh__t_f(y_sh) * sh__t_f(y_sh) + 24.0::DOUBLE * pow(sh__t_f(y_sh), 4.0::DOUBLE)) / (120.0::DOUBLE * pow(sh__nf(y_sh), 5.0::DOUBLE) * sh__cos_bf(y_sh))) * pow(sh__y_std(x_sh), 5.0::DOUBLE)
	) * 180.0::DOUBLE / pi()
);

CREATE OR REPLACE MACRO cn__shcs2000_to_wgs84_lat(x_sh, y_sh) AS (
	(
		sh__bf(y_sh)
		- (sh__t_f(y_sh) / (2.0::DOUBLE * sh__mf(y_sh) * sh__nf(y_sh))) * pow(sh__y_std(x_sh), 2.0::DOUBLE)
		+ (sh__t_f(y_sh) / (24.0::DOUBLE * sh__mf(y_sh) * pow(sh__nf(y_sh), 3.0::DOUBLE))) * (5.0::DOUBLE + 3.0::DOUBLE * sh__t_f(y_sh) * sh__t_f(y_sh) + sh__eta_f2(y_sh) - 9.0::DOUBLE * sh__eta_f2(y_sh) * sh__t_f(y_sh) * sh__t_f(y_sh)) * pow(sh__y_std(x_sh), 4.0::DOUBLE)
	) * 180.0::DOUBLE / pi()
);

CREATE OR REPLACE MACRO cn__shcs2000_to_wgs84_xy(x_sh, y_sh) AS (
	{
		'lon': cn__shcs2000_to_wgs84_lon(x_sh, y_sh),
		'lat': cn__shcs2000_to_wgs84_lat(x_sh, y_sh)
	}
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

CREATE OR REPLACE MACRO cn__point_out_shcs(lat, lon) AS (
	CASE
		WHEN NOT cn__finite_latlon(lat, lon) THEN NULL
		ELSE {
			'x': cn__wgs84_to_shcs2000_x(lon, lat),
			'y': cn__wgs84_to_shcs2000_y(lon, lat)
		}
	END
);

CREATE OR REPLACE MACRO cn__point_out_from_shcs(x, y) AS (
	CASE
		WHEN NOT cn__finite_xy(x, y) THEN NULL
		ELSE {
			'lat': cn__shcs2000_to_wgs84_lat(x, y),
			'lon': cn__shcs2000_to_wgs84_lon(x, y)
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

-- Shanghai 2000 (SHCS2000) Dedicated Fast Geometry Walkers (Forward)
CREATE OR REPLACE MACRO cn__point_geom_shcs_fwd(g) AS (
	ST_Point(
		cn__wgs84_to_shcs2000_x(ST_X(g), ST_Y(g)),
		cn__wgs84_to_shcs2000_y(ST_X(g), ST_Y(g))
	)
);

CREATE OR REPLACE MACRO cn__line_geom_shcs_fwd(g) AS (
	ST_MakeLine(
		list_transform(
			generate_series(1, ST_NPoints(g)::BIGINT),
			lambda i: ST_Point(
				cn__wgs84_to_shcs2000_x(
					ST_X(ST_PointN(g, i::INTEGER)),
					ST_Y(ST_PointN(g, i::INTEGER))
				),
				cn__wgs84_to_shcs2000_y(
					ST_X(ST_PointN(g, i::INTEGER)),
					ST_Y(ST_PointN(g, i::INTEGER))
				)
			)
		)
	)
);

CREATE OR REPLACE MACRO cn__poly_geom_shcs_fwd(g) AS (
	ST_MakePolygon(
		cn__line_geom_shcs_fwd(ST_ExteriorRing(g)),
		list_transform(
			list_filter(
				ST_Dump(ST_Boundary(g)),
				lambda ring: len(ring.path) > 0 AND ring.path[1] > 1
			),
			lambda ring: cn__line_geom_shcs_fwd(ring.geom)
		)
	)
);

CREATE OR REPLACE MACRO cn__atomic_geom_shcs_fwd(g) AS (
	CASE ST_GeometryType(g)
		WHEN 'POINT' THEN cn__point_geom_shcs_fwd(g)
		WHEN 'LINESTRING' THEN cn__line_geom_shcs_fwd(g)
		WHEN 'POLYGON' THEN cn__poly_geom_shcs_fwd(g)
		ELSE NULL
	END
);

CREATE OR REPLACE MACRO cn__multi_geom_shcs_fwd(g) AS (
	ST_Multi(
		ST_Collect(
			list_transform(
				ST_Dump(g),
				lambda part: cn__atomic_geom_shcs_fwd(part.geom)
			)
		)
	)
);

CREATE OR REPLACE MACRO cn__collection_geom_shcs_fwd(g) AS (
	ST_Collect(
		list_transform(
			ST_Dump(g),
			lambda part: cn__atomic_geom_shcs_fwd(part.geom)
		)
	)
);

CREATE OR REPLACE MACRO cn__geom_shcs_fwd(g) AS (
	CASE
		WHEN g IS NULL THEN NULL
		WHEN ST_IsEmpty(g) THEN g
		WHEN ST_GeometryType(g) = 'POINT' THEN cn__point_geom_shcs_fwd(g)
		WHEN ST_GeometryType(g) = 'LINESTRING' THEN cn__line_geom_shcs_fwd(g)
		WHEN ST_GeometryType(g) = 'POLYGON' THEN cn__poly_geom_shcs_fwd(g)
		WHEN ST_GeometryType(g) IN ('MULTIPOINT', 'MULTILINESTRING', 'MULTIPOLYGON')
			THEN cn__multi_geom_shcs_fwd(g)
		WHEN ST_GeometryType(g) = 'GEOMETRYCOLLECTION' THEN cn__collection_geom_shcs_fwd(g)
		ELSE NULL
	END
);

-- Shanghai 2000 (SHCS2000) Dedicated Fast Geometry Walkers (Inverse)
CREATE OR REPLACE MACRO cn__point_geom_shcs_inv(g) AS (
	ST_Point(
		cn__shcs2000_to_wgs84_lon(ST_X(g), ST_Y(g)),
		cn__shcs2000_to_wgs84_lat(ST_X(g), ST_Y(g))
	)
);

CREATE OR REPLACE MACRO cn__line_geom_shcs_inv(g) AS (
	ST_MakeLine(
		list_transform(
			generate_series(1, ST_NPoints(g)::BIGINT),
			lambda i: ST_Point(
				cn__shcs2000_to_wgs84_lon(
					ST_X(ST_PointN(g, i::INTEGER)),
					ST_Y(ST_PointN(g, i::INTEGER))
				),
				cn__shcs2000_to_wgs84_lat(
					ST_X(ST_PointN(g, i::INTEGER)),
					ST_Y(ST_PointN(g, i::INTEGER))
				)
			)
		)
	)
);

CREATE OR REPLACE MACRO cn__poly_geom_shcs_inv(g) AS (
	ST_MakePolygon(
		cn__line_geom_shcs_inv(ST_ExteriorRing(g)),
		list_transform(
			list_filter(
				ST_Dump(ST_Boundary(g)),
				lambda ring: len(ring.path) > 0 AND ring.path[1] > 1
			),
			lambda ring: cn__line_geom_shcs_inv(ring.geom)
		)
	)
);

CREATE OR REPLACE MACRO cn__atomic_geom_shcs_inv(g) AS (
	CASE ST_GeometryType(g)
		WHEN 'POINT' THEN cn__point_geom_shcs_inv(g)
		WHEN 'LINESTRING' THEN cn__line_geom_shcs_inv(g)
		WHEN 'POLYGON' THEN cn__poly_geom_shcs_inv(g)
		ELSE NULL
	END
);

CREATE OR REPLACE MACRO cn__multi_geom_shcs_inv(g) AS (
	ST_Multi(
		ST_Collect(
			list_transform(
				ST_Dump(g),
				lambda part: cn__atomic_geom_shcs_inv(part.geom)
			)
		)
	)
);

CREATE OR REPLACE MACRO cn__collection_geom_shcs_inv(g) AS (
	ST_Collect(
		list_transform(
			ST_Dump(g),
			lambda part: cn__atomic_geom_shcs_inv(part.geom)
		)
	)
);

CREATE OR REPLACE MACRO cn__geom_shcs_inv(g) AS (
	CASE
		WHEN g IS NULL THEN NULL
		WHEN ST_IsEmpty(g) THEN g
		WHEN ST_GeometryType(g) = 'POINT' THEN cn__point_geom_shcs_inv(g)
		WHEN ST_GeometryType(g) = 'LINESTRING' THEN cn__line_geom_shcs_inv(g)
		WHEN ST_GeometryType(g) = 'POLYGON' THEN cn__poly_geom_shcs_inv(g)
		WHEN ST_GeometryType(g) IN ('MULTIPOINT', 'MULTILINESTRING', 'MULTIPOLYGON')
			THEN cn__multi_geom_shcs_inv(g)
		WHEN ST_GeometryType(g) = 'GEOMETRYCOLLECTION' THEN cn__collection_geom_shcs_inv(g)
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

-- SHCS2000 API
CREATE OR REPLACE MACRO wgs84_to_shcs2000
	(lat, lon) AS cn__point_out_shcs(lat, lon),
	(geom) AS cn__geom_shcs_fwd(geom);

CREATE OR REPLACE MACRO shcs2000_to_wgs84
	(x, y) AS cn__point_out_from_shcs(x, y),
	(geom) AS cn__geom_shcs_inv(geom);

CREATE OR REPLACE MACRO gcj02_to_shcs2000
	(lat, lon) AS wgs84_to_shcs2000(gcj02_to_wgs84(lat, lon).lat, gcj02_to_wgs84(lat, lon).lon),
	(geom) AS wgs84_to_shcs2000(gcj02_to_wgs84(geom));

CREATE OR REPLACE MACRO shcs2000_to_gcj02
	(x, y) AS wgs84_to_gcj02(shcs2000_to_wgs84(x, y).lat, shcs2000_to_wgs84(x, y).lon),
	(geom) AS wgs84_to_gcj02(shcs2000_to_wgs84(geom));

CREATE OR REPLACE MACRO bd09_to_shcs2000
	(lat, lon) AS wgs84_to_shcs2000(bd09_to_wgs84(lat, lon).lat, bd09_to_wgs84(lat, lon).lon),
	(geom) AS wgs84_to_shcs2000(bd09_to_wgs84(geom));

CREATE OR REPLACE MACRO shcs2000_to_bd09
	(x, y) AS wgs84_to_bd09(shcs2000_to_wgs84(x, y).lat, shcs2000_to_wgs84(x, y).lon),
	(geom) AS wgs84_to_bd09(shcs2000_to_wgs84(geom));
