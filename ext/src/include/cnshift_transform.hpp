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

} // namespace duckdb
