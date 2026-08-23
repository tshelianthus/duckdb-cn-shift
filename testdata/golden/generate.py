#!/usr/bin/env python3
"""Regenerate testdata/golden fixtures for cnshift.

Run from the repository root:

    python3 testdata/golden/generate.py
"""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path

# Ellipsoid and Empirical Constants
A = 6378245.0
EE = 0.006693421622965823
X_PI = math.pi * 3000.0 / 180.0
BD_LON = 0.0065
BD_LAT = 0.006
BD_Z = 0.00002
BD_THETA = 0.000003

# Shanghai 2000 (SHCS2000) Constants
SH_A_EFF = 6378153.3398
SH_E2 = 0.006694380022900787
SH_EP2 = 0.006739496775498909
SH_L0 = 121.46444444444444
SH_L0_RAD = SH_L0 * math.pi / 180.0
SH_X_ORIG = 3457087.73141366
SH_Y_ORIG = 257.85859273

SH_K0 = 6367465.458133294
SH_K2 = 16038.549782158
SH_K4 = 16.832642939
SH_K6 = 0.021981053
SH_M0_BAR = 6367465.45832782
SH_C1 = 0.002518826597
SH_C2 = 0.000003700949
SH_C3 = 0.000000007448
SH_C4 = 0.000000000017

HERE = Path(__file__).resolve().parent
OPS = (
    "wgs84_to_gcj02",
    "gcj02_to_wgs84",
    "gcj02_to_bd09",
    "bd09_to_gcj02",
    "wgs84_to_bd09",
    "bd09_to_wgs84",
    "wgs84_to_shcs2000",
)


def in_china(lon: float, lat: float) -> bool:
    return 72.004 <= lon <= 137.8347 and 0.8293 <= lat <= 55.8271


def transform_lat(x: float, y: float) -> float:
    ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0
    ret += (160.0 * math.sin(y / 12.0 * math.pi) + 320.0 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0
    return ret


def transform_lon(x: float, y: float) -> float:
    ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0
    ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0
    return ret


def delta(lon: float, lat: float) -> tuple[float, float]:
    dlon0 = transform_lon(lon - 105.0, lat - 35.0)
    dlat0 = transform_lat(lon - 105.0, lat - 35.0)
    rad = lat / 180.0 * math.pi
    magic = 1.0 - EE * math.sin(rad) ** 2
    sqrt_magic = math.sqrt(magic)
    dlon = (dlon0 * 180.0) / (A / sqrt_magic * math.cos(rad) * math.pi)
    dlat = (dlat0 * 180.0) / ((A * (1.0 - EE)) / (magic * sqrt_magic) * math.pi)
    return dlon, dlat


def wgs84_to_gcj02(lon: float, lat: float) -> tuple[float, float]:
    if not in_china(lon, lat):
        return lon, lat
    dlon, dlat = delta(lon, lat)
    return lon + dlon, lat + dlat


def gcj02_to_wgs84(lon: float, lat: float) -> tuple[float, float]:
    if not in_china(lon, lat):
        return lon, lat
    plon, plat = wgs84_to_gcj02(lon, lat)
    return 2.0 * lon - plon, 2.0 * lat - plat


def gcj02_to_bd09(lon: float, lat: float) -> tuple[float, float]:
    if not in_china(lon, lat):
        return lon, lat
    z = math.hypot(lon, lat) + BD_Z * math.sin(lat * X_PI)
    theta = math.atan2(lat, lon) + BD_THETA * math.cos(lon * X_PI)
    return z * math.cos(theta) + BD_LON, z * math.sin(theta) + BD_LAT


def bd09_to_gcj02(lon: float, lat: float) -> tuple[float, float]:
    if not in_china(lon, lat):
        return lon, lat
    x = lon - BD_LON
    y = lat - BD_LAT
    z = math.hypot(x, y) - BD_Z * math.sin(y * X_PI)
    theta = math.atan2(y, x) - BD_THETA * math.cos(x * X_PI)
    return z * math.cos(theta), z * math.sin(theta)


def wgs84_to_bd09(lon: float, lat: float) -> tuple[float, float]:
    return gcj02_to_bd09(*wgs84_to_gcj02(lon, lat))


def bd09_to_wgs84(lon: float, lat: float) -> tuple[float, float]:
    return gcj02_to_wgs84(*bd09_to_gcj02(lon, lat))


def wgs84_to_shcs2000(lon: float, lat: float) -> tuple[float, float]:
    b = lat * math.pi / 180.0
    l = lon * math.pi / 180.0 - SH_L0_RAD
    sin_b = math.sin(b)
    cos_b = math.cos(b)
    t = math.tan(b)
    n = SH_A_EFF / math.sqrt(1.0 - SH_E2 * sin_b ** 2)
    eta2 = SH_EP2 * (cos_b ** 2)
    x_arc = SH_K0 * b - SH_K2 * math.sin(2.0 * b) + SH_K4 * math.sin(4.0 * b) - SH_K6 * math.sin(6.0 * b)
    x_std = x_arc + n * sin_b * cos_b * (l ** 2) / 2.0 + n * sin_b * (cos_b ** 3) * (5.0 - t ** 2 + 9.0 * eta2 + 4.0 * (eta2 ** 2)) * (l ** 4) / 24.0
    y_std = n * cos_b * l + n * (cos_b ** 3) * (1.0 - t ** 2 + eta2) * (l ** 3) / 6.0
    return y_std - SH_Y_ORIG, x_std - SH_X_ORIG


def shcs2000_to_wgs84(x: float, y: float) -> tuple[float, float]:
    x_std = y + SH_X_ORIG
    y_std = x + SH_Y_ORIG
    mu = x_std / SH_M0_BAR
    bf = mu + SH_C1 * math.sin(2.0 * mu) + SH_C2 * math.sin(4.0 * mu) + SH_C3 * math.sin(6.0 * mu) + SH_C4 * math.sin(8.0 * mu)
    sin_bf = math.sin(bf)
    cos_bf = math.cos(bf)
    t_f = math.tan(bf)
    eta_f2 = SH_EP2 * (cos_bf ** 2)
    nf = SH_A_EFF / math.sqrt(1.0 - SH_E2 * sin_bf ** 2)
    mf = SH_A_EFF * (1.0 - SH_E2) / ((1.0 - SH_E2 * sin_bf ** 2) ** 1.5)
    lat = (bf - (t_f / (2.0 * mf * nf)) * (y_std ** 2) + (t_f / (24.0 * mf * (nf ** 3))) * (5.0 + 3.0 * (t_f ** 2) + eta_f2 - 9.0 * eta_f2 * (t_f ** 2)) * (y_std ** 4)) * 180.0 / math.pi
    l = ((1.0 / (nf * cos_bf)) * y_std - ((1.0 + 2.0 * (t_f ** 2) + eta_f2) / (6.0 * (nf ** 3) * cos_bf)) * (y_std ** 3) + ((5.0 + 28.0 * (t_f ** 2) + 24.0 * (t_f ** 4)) / (120.0 * (nf ** 5) * cos_bf)) * (y_std ** 5)) * 180.0 / math.pi
    return SH_L0 + l, lat


APPLY = {
    "wgs84_to_gcj02": wgs84_to_gcj02,
    "gcj02_to_wgs84": gcj02_to_wgs84,
    "gcj02_to_bd09": gcj02_to_bd09,
    "bd09_to_gcj02": bd09_to_gcj02,
    "wgs84_to_bd09": wgs84_to_bd09,
    "bd09_to_wgs84": bd09_to_wgs84,
    "wgs84_to_shcs2000": wgs84_to_shcs2000,
    "shcs2000_to_wgs84": shcs2000_to_wgs84,
}


def fmt_coord(value: float) -> str:
    return f"{value:.16f}"


def wkt_pair(lon: float, lat: float) -> str:
    return f"{lon:.16f} {lat:.16f}"


def apply_pair(op: str, lon: float, lat: float) -> tuple[float, float]:
    return APPLY[op](lon, lat)


def map_ring(op: str, ring: list[tuple[float, float]]) -> list[tuple[float, float]]:
    return [apply_pair(op, lon, lat) for lon, lat in ring]


def ring_wkt(ring: list[tuple[float, float]]) -> str:
    return "(" + ", ".join(wkt_pair(lon, lat) for lon, lat in ring) + ")"


def write_points() -> None:
    cities = [
        ("shanghai", "31.2304", "121.4737", "in-china city"),
        ("beijing", "39.9042", "116.4074", "in-china city"),
        ("nyc", "40.7128", "-74.0060", "outside bbox; identity including BD"),
        ("origin", "0.0", "0.0", "outside bbox; identity"),
        ("bbox_sw_inside", "0.8293", "72.004", "bbox inclusive SW corner"),
        ("bbox_sw_outside", "0.8293", "72.003999", "just west of bbox"),
        ("bbox_ne_inside", "55.8271", "137.8347", "bbox inclusive NE corner"),
        ("bbox_ne_outside", "55.8271", "137.8348", "just east of bbox"),
    ]
    rows = []
    for name, lat_s, lon_s, note in cities:
        lat = float(lat_s)
        lon = float(lon_s)
        for op in OPS:
            olon, olat = apply_pair(op, lon, lat)
            rows.append(
                {
                    "id": f"{name}_{op}",
                    "op": op,
                    "in_lat": lat_s,
                    "in_lon": lon_s,
                    "expect_lat": fmt_coord(olat),
                    "expect_lon": fmt_coord(olon),
                    "note": note,
                }
            )
    path = HERE / "points.csv"
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=["id", "op", "in_lat", "in_lon", "expect_lat", "expect_lon", "note"],
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {path} ({len(rows)} rows)")


def point_wkt(lon: float, lat: float) -> str:
    return f"POINT ({wkt_pair(lon, lat)})"


def line_wkt(coords: list[tuple[float, float]]) -> str:
    return "LINESTRING (" + ", ".join(wkt_pair(lon, lat) for lon, lat in coords) + ")"


def polygon_wkt(rings: list[list[tuple[float, float]]]) -> str:
    return "POLYGON (" + ", ".join(ring_wkt(r) for r in rings) + ")"


def multipoint_wkt(coords: list[tuple[float, float]]) -> str:
    return "MULTIPOINT (" + ", ".join(f"({wkt_pair(lon, lat)})" for lon, lat in coords) + ")"


def multiline_wkt(lines: list[list[tuple[float, float]]]) -> str:
    body = ", ".join(
        "(" + ", ".join(wkt_pair(lon, lat) for lon, lat in line) + ")" for line in lines
    )
    return f"MULTILINESTRING ({body})"


def multipolygon_wkt(polys: list[list[list[tuple[float, float]]]]) -> str:
    body = ", ".join("(" + ", ".join(ring_wkt(r) for r in rings) + ")" for rings in polys)
    return f"MULTIPOLYGON ({body})"


def collection_wkt(parts: list[str]) -> str:
    return "GEOMETRYCOLLECTION (" + ", ".join(parts) + ")"


def vertices_of(kind: str, data) -> list[list[float]]:
    if kind == "POINT":
        lon, lat = data
        return [[lon, lat]]
    if kind == "LINESTRING":
        return [[lon, lat] for lon, lat in data]
    if kind == "POLYGON":
        out: list[list[float]] = []
        for ring in data:
            out.extend([lon, lat] for lon, lat in ring)
        return out
    if kind == "MULTIPOINT":
        return [[lon, lat] for lon, lat in data]
    if kind == "MULTILINESTRING":
        out = []
        for line in data:
            out.extend([lon, lat] for lon, lat in line)
        return out
    if kind == "MULTIPOLYGON":
        out = []
        for rings in data:
            for ring in rings:
                out.extend([lon, lat] for lon, lat in ring)
        return out
    if kind == "GEOMETRYCOLLECTION":
        out = []
        for part_kind, part_data in data:
            out.extend(vertices_of(part_kind, part_data))
        return out
    raise ValueError(kind)


def transform_data(kind: str, data, op: str):
    if kind == "POINT":
        lon, lat = data
        return apply_pair(op, lon, lat)
    if kind in ("LINESTRING", "MULTIPOINT"):
        return map_ring(op, data)
    if kind == "POLYGON":
        return [map_ring(op, ring) for ring in data]
    if kind == "MULTILINESTRING":
        return [map_ring(op, line) for line in data]
    if kind == "MULTIPOLYGON":
        return [[map_ring(op, ring) for ring in rings] for rings in data]
    if kind == "GEOMETRYCOLLECTION":
        return [(pk, transform_data(pk, pd, op)) for pk, pd in data]
    raise ValueError(kind)


def to_wkt(kind: str, data) -> str:
    if kind == "POINT":
        return point_wkt(*data)
    if kind == "LINESTRING":
        return line_wkt(data)
    if kind == "POLYGON":
        return polygon_wkt(data)
    if kind == "MULTIPOINT":
        return multipoint_wkt(data)
    if kind == "MULTILINESTRING":
        return multiline_wkt(data)
    if kind == "MULTIPOLYGON":
        return multipolygon_wkt(data)
    if kind == "GEOMETRYCOLLECTION":
        return collection_wkt([to_wkt(pk, pd) for pk, pd in data])
    raise ValueError(kind)


def n_holes(kind: str, data) -> int | None:
    if kind == "POLYGON":
        return max(len(data) - 1, 0)
    return None


def n_geoms(kind: str, data) -> int:
    if kind == "MULTIPOINT":
        return len(data)
    if kind == "MULTILINESTRING":
        return len(data)
    if kind == "MULTIPOLYGON":
        return len(data)
    if kind == "GEOMETRYCOLLECTION":
        return len(data)
    return 1


def write_geometries() -> None:
    sh = (121.4737, 31.2304)
    bj = (116.4074, 39.9042)
    nyc = (-74.0060, 40.7128)
    shell = [
        (121.47, 31.23),
        (121.48, 31.23),
        (121.48, 31.24),
        (121.47, 31.24),
        (121.47, 31.23),
    ]
    hole = [
        (121.473, 31.233),
        (121.477, 31.233),
        (121.477, 31.237),
        (121.473, 31.237),
        (121.473, 31.233),
    ]
    poly_a = [
        (121.47, 31.23),
        (121.48, 31.23),
        (121.48, 31.24),
        (121.47, 31.24),
        (121.47, 31.23),
    ]
    poly_b = [
        (121.48, 31.23),
        (121.49, 31.23),
        (121.49, 31.24),
        (121.48, 31.24),
        (121.48, 31.23),
    ]
    specs = [
        {
            "id": "sh_point",
            "kind": "POINT",
            "data": sh,
            "note": "Shanghai point",
            "expect_type": "POINT",
        },
        {
            "id": "nyc_point_identity",
            "kind": "POINT",
            "data": nyc,
            "note": "outside bbox identity",
            "expect_type": "POINT",
        },
        {
            "id": "sh_bj_line",
            "kind": "LINESTRING",
            "data": [sh, bj],
            "note": "Shanghai to Beijing",
            "expect_type": "LINESTRING",
        },
        {
            "id": "sh_poly_hole",
            "kind": "POLYGON",
            "data": [shell, hole],
            "note": "polygon with one hole",
            "expect_type": "POLYGON",
        },
        {
            "id": "sh_multipoint",
            "kind": "MULTIPOINT",
            "data": [sh, bj],
            "note": "two city points",
            "expect_type": "MULTIPOINT",
        },
        {
            "id": "sh_multiline",
            "kind": "MULTILINESTRING",
            "data": [[sh, (121.48, 31.24)], [bj, (116.41, 39.91)]],
            "note": "two lines",
            "expect_type": "MULTILINESTRING",
        },
        {
            "id": "sh_multipoly_touching",
            "kind": "MULTIPOLYGON",
            "data": [[poly_a], [poly_b]],
            "note": "adjacent parts must stay 2 (Collect, not Union)",
            "expect_type": "MULTIPOLYGON",
        },
        {
            "id": "mixed_collection",
            "kind": "GEOMETRYCOLLECTION",
            "data": [("POINT", sh), ("LINESTRING", [sh, (121.48, 31.24)])],
            "note": "flat mixed collection",
            "expect_type": "GEOMETRYCOLLECTION",
        },
        {
            "id": "nested_collection_points",
            "kind": "GEOMETRYCOLLECTION",
            "data": [("GEOMETRYCOLLECTION", [("POINT", sh)]), ("POINT", bj)],
            "note": "nested GC flattens; two points collect as MULTIPOINT",
            "expect_type": "MULTIPOINT",
            "flatten": True,
        },
    ]

    rows = []
    for spec in specs:
        kind = spec["kind"]
        data = spec["data"]
        for op in ("wgs84_to_gcj02", "gcj02_to_bd09", "wgs84_to_shcs2000"):
            out_data = transform_data(kind, data, op)
            expect_vertices = vertices_of(kind, out_data)
            if spec.get("flatten"):
                # Nested GC of points → ST_Dump leaves + ST_Collect → MULTIPOINT
                expect_wkt = multipoint_wkt([tuple(p) for p in expect_vertices])
                expect_n_geoms = len(expect_vertices)
            else:
                expect_wkt = to_wkt(kind, out_data)
                expect_n_geoms = n_geoms(kind, data)
            rows.append(
                {
                    "id": f"{spec['id']}_{op}",
                    "op": op,
                    "input_wkt": to_wkt(kind, data),
                    "expect_type": spec["expect_type"],
                    "expect_wkt": expect_wkt,
                    "expect_vertices": expect_vertices,
                    "expect_num_geometries": expect_n_geoms,
                    "expect_num_interior_rings": n_holes(kind, data),
                    "expect_num_points": len(expect_vertices),
                    "note": spec["note"],
                }
            )

    path = HERE / "geometries.jsonl"
    with path.open("w") as fh:
        for row in rows:
            fh.write(json.dumps(row) + "\n")
    print(f"wrote {path} ({len(rows)} rows)")


if __name__ == "__main__":
    write_points()
    write_geometries()
