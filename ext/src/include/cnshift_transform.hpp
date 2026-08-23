#pragma once

// Algorithm constants and formulae: docs/ALGORITHM.md (single source of truth).
// Do not diverge without updating that document and shared golden fixtures.
//
// Pure C++ WGS-84 / GCJ-02 / BD-09 offset math. No DuckDB, GEOS, GDAL, or PROJ.
// Input range checks belong in the SQL executor, not this kernel.

namespace duckdb {

struct CnshiftCoord {
	double lat;
	double lon;
};

//! docs/ALGORITHM.md §1 China bbox: lon∈[72.004, 137.8347] ∧ lat∈[0.8293, 55.8271]
bool InChinaBbox(double lat, double lon);

CnshiftCoord Wgs84ToGcj02(double lat, double lon);
CnshiftCoord Gcj02ToWgs84(double lat, double lon);
CnshiftCoord Gcj02ToBd09(double lat, double lon);
CnshiftCoord Bd09ToGcj02(double lat, double lon);
CnshiftCoord Wgs84ToBd09(double lat, double lon);
CnshiftCoord Bd09ToWgs84(double lat, double lon);

// docs/ALGORITHM.md §7 Shanghai 2000 (SHCS2000)
CnshiftCoord Wgs84ToShcs2000(double lat, double lon);
CnshiftCoord Shcs2000ToWgs84(double y, double x);
CnshiftCoord Gcj02ToShcs2000(double lat, double lon);
CnshiftCoord Shcs2000ToGcj02(double y, double x);
CnshiftCoord Bd09ToShcs2000(double lat, double lon);
CnshiftCoord Shcs2000ToBd09(double y, double x);

// Backward-compatibility aliases
inline CnshiftCoord Wgs84ToShanghai2000(double lat, double lon) {
	return Wgs84ToShcs2000(lat, lon);
}
inline CnshiftCoord Shanghai2000ToWgs84(double y, double x) {
	return Shcs2000ToWgs84(y, x);
}
inline CnshiftCoord Gcj02ToShanghai2000(double lat, double lon) {
	return Gcj02ToShcs2000(lat, lon);
}
inline CnshiftCoord Shanghai2000ToGcj02(double y, double x) {
	return Shcs2000ToGcj02(y, x);
}
inline CnshiftCoord Bd09ToShanghai2000(double lat, double lon) {
	return Bd09ToShcs2000(lat, lon);
}
inline CnshiftCoord Shanghai2000ToBd09(double y, double x) {
	return Shcs2000ToBd09(y, x);
}

} // namespace duckdb
