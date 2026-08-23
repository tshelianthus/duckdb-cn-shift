#pragma once

// Pure C++ WGS-84 / GCJ-02 / BD-09 / SHCS2000 offset math. No DuckDB, GEOS, GDAL, or PROJ.
// Input range checks belong in the SQL executor, not this kernel.

namespace duckdb {

struct CnshiftCoord {
	double lat;
	double lon;
};

//! China bbox: lon∈[72.004, 137.8347] ∧ lat∈[0.8293, 55.8271]
bool InChinaBbox(double lat, double lon);

CnshiftCoord Wgs84ToGcj02(double lat, double lon);
CnshiftCoord Gcj02ToWgs84(double lat, double lon);
CnshiftCoord Gcj02ToBd09(double lat, double lon);
CnshiftCoord Bd09ToGcj02(double lat, double lon);
CnshiftCoord Wgs84ToBd09(double lat, double lon);
CnshiftCoord Bd09ToWgs84(double lat, double lon);

// Shanghai 2000 (SHCS2000)
CnshiftCoord Wgs84ToShcs2000(double lat, double lon);
CnshiftCoord Shcs2000ToWgs84(double y, double x);
CnshiftCoord Gcj02ToShcs2000(double lat, double lon);
CnshiftCoord Shcs2000ToGcj02(double y, double x);
CnshiftCoord Bd09ToShcs2000(double lat, double lon);
CnshiftCoord Shcs2000ToBd09(double y, double x);

} // namespace duckdb
