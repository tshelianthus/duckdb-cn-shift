#include "cnshift_transform.hpp"

#include <cmath>

namespace duckdb {

namespace {

// docs/ALGORITHM.md §1 — copy these only by back-reference; do not invent a second table.
constexpr double kA = 6378245.0;
constexpr double kEe = 0.006693421622965823; // pg geoc_delta; not eviltransform's …94323
constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr double kXPi = kPi * 3000.0 / 180.0;
constexpr double kBdLon = 0.0065;
constexpr double kBdLat = 0.006;
constexpr double kBdZ = 0.00002;
constexpr double kBdTheta = 0.000003;

// docs/ALGORITHM.md §2 — x = lon-105, y = lat-35
double TransformLat(double x, double y) {
	double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * std::sqrt(std::fabs(x));
	ret += (20.0 * std::sin(6.0 * x * kPi) + 20.0 * std::sin(2.0 * x * kPi)) * 2.0 / 3.0;
	ret += (20.0 * std::sin(y * kPi) + 40.0 * std::sin(y / 3.0 * kPi)) * 2.0 / 3.0;
	ret += (160.0 * std::sin(y / 12.0 * kPi) + 320.0 * std::sin(y * kPi / 30.0)) * 2.0 / 3.0;
	return ret;
}

double TransformLon(double x, double y) {
	double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * std::sqrt(std::fabs(x));
	ret += (20.0 * std::sin(6.0 * x * kPi) + 20.0 * std::sin(2.0 * x * kPi)) * 2.0 / 3.0;
	ret += (20.0 * std::sin(x * kPi) + 40.0 * std::sin(x / 3.0 * kPi)) * 2.0 / 3.0;
	ret += (150.0 * std::sin(x / 12.0 * kPi) + 300.0 * std::sin(x / 30.0 * kPi)) * 2.0 / 3.0;
	return ret;
}

// docs/ALGORITHM.md §3
CnshiftCoord Delta(double lon, double lat) {
	const double dlon0 = TransformLon(lon - 105.0, lat - 35.0);
	const double dlat0 = TransformLat(lon - 105.0, lat - 35.0);
	const double rad_lat = lat / 180.0 * kPi;
	const double sin_lat = std::sin(rad_lat);
	const double magic = 1.0 - kEe * sin_lat * sin_lat;
	const double sqrt_magic = std::sqrt(magic);
	const double dlon = (dlon0 * 180.0) / (kA / sqrt_magic * std::cos(rad_lat) * kPi);
	const double dlat = (dlat0 * 180.0) / ((kA * (1.0 - kEe)) / (magic * sqrt_magic) * kPi);
	return {dlat, dlon};
}

} // namespace

bool InChinaBbox(double lat, double lon) {
	return lon >= 72.004 && lon <= 137.8347 && lat >= 0.8293 && lat <= 55.8271;
}

CnshiftCoord Wgs84ToGcj02(double lat, double lon) {
	if (!InChinaBbox(lat, lon)) {
		return {lat, lon};
	}
	const auto d = Delta(lon, lat);
	return {lat + d.lat, lon + d.lon};
}

CnshiftCoord Gcj02ToWgs84(double lat, double lon) {
	// docs/ALGORITHM.md §4.3 — one-shot 2p - forward(p); not iterative.
	if (!InChinaBbox(lat, lon)) {
		return {lat, lon};
	}
	const auto fwd = Wgs84ToGcj02(lat, lon);
	return {lat * 2.0 - fwd.lat, lon * 2.0 - fwd.lon};
}

CnshiftCoord Gcj02ToBd09(double lat, double lon) {
	// docs/ALGORITHM.md §5 — BD segment also applies the China bbox (pg source).
	if (!InChinaBbox(lat, lon)) {
		return {lat, lon};
	}
	const double z = std::sqrt(lon * lon + lat * lat) + kBdZ * std::sin(lat * kXPi);
	const double theta = std::atan2(lat, lon) + kBdTheta * std::cos(lon * kXPi);
	return {z * std::sin(theta) + kBdLat, z * std::cos(theta) + kBdLon};
}

CnshiftCoord Bd09ToGcj02(double lat, double lon) {
	if (!InChinaBbox(lat, lon)) {
		return {lat, lon};
	}
	const double x = lon - kBdLon;
	const double y = lat - kBdLat;
	const double z = std::sqrt(x * x + y * y) - kBdZ * std::sin(y * kXPi);
	const double theta = std::atan2(y, x) - kBdTheta * std::cos(x * kXPi);
	return {z * std::sin(theta), z * std::cos(theta)};
}

CnshiftCoord Wgs84ToBd09(double lat, double lon) {
	const auto gcj = Wgs84ToGcj02(lat, lon);
	return Gcj02ToBd09(gcj.lat, gcj.lon);
}

CnshiftCoord Bd09ToWgs84(double lat, double lon) {
	const auto gcj = Bd09ToGcj02(lat, lon);
	return Gcj02ToWgs84(gcj.lat, gcj.lon);
}

} // namespace duckdb
