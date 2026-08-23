#include "cnshift_transform.hpp"

#include <cmath>

namespace duckdb {

namespace {

// Ellipsoid and Empirical Constants
constexpr double kA = 6378245.0;
constexpr double kEe = 0.006693421622965823;
constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr double kXPi = kPi * 3000.0 / 180.0;
constexpr double kBdLon = 0.0065;
constexpr double kBdLat = 0.006;
constexpr double kBdZ = 0.00002;
constexpr double kBdTheta = 0.000003;

// Empirical Polynomials (x = lon-105, y = lat-35)
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

// Delta Offset Calculation
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

// Shanghai 2000 (SHCS2000) Geodetic Constants
constexpr double kShAEff = 6378153.3398;
constexpr double kShE2 = 0.006694380022900787;
constexpr double kShEp2 = 0.006739496775498909;
constexpr double kShL0 = 121.46444444444444;
constexpr double kShL0Rad = 121.46444444444444 * kPi / 180.0;
constexpr double kShXOrig = 3457087.73141366;
constexpr double kShYOrig = 257.85859273;

constexpr double kShK0 = 6367465.458133294;
constexpr double kShK2 = 16038.549782158;
constexpr double kShK4 = 16.832642939;
constexpr double kShK6 = 0.021981053;
constexpr double kShM0Bar = 6367465.45832782;
constexpr double kShC1 = 0.002518826597;
constexpr double kShC2 = 0.000003700949;
constexpr double kShC3 = 0.000000007448;
constexpr double kShC4 = 0.000000000017;

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
	if (!InChinaBbox(lat, lon)) {
		return {lat, lon};
	}
	const auto fwd = Wgs84ToGcj02(lat, lon);
	return {lat * 2.0 - fwd.lat, lon * 2.0 - fwd.lon};
}

CnshiftCoord Gcj02ToBd09(double lat, double lon) {
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

CnshiftCoord Wgs84ToShcs2000(double lat, double lon) {
	const double b = lat * kPi / 180.0;
	const double l = (lon * kPi / 180.0) - kShL0Rad;
	const double sin_b = std::sin(b);
	const double cos_b = std::cos(b);
	const double t = std::tan(b);
	const double n = kShAEff / std::sqrt(1.0 - kShE2 * sin_b * sin_b);
	const double eta2 = kShEp2 * cos_b * cos_b;
	const double x_arc =
	    kShK0 * b - kShK2 * std::sin(2.0 * b) + kShK4 * std::sin(4.0 * b) - kShK6 * std::sin(6.0 * b);
	const double x_std = x_arc + n * sin_b * cos_b * (l * l) / 2.0 +
	                     n * sin_b * (cos_b * cos_b * cos_b) * (5.0 - t * t + 9.0 * eta2 + 4.0 * eta2 * eta2) *
	                         (l * l * l * l) / 24.0;
	const double y_std = n * cos_b * l + n * (cos_b * cos_b * cos_b) * (1.0 - t * t + eta2) * (l * l * l) / 6.0;
	return {x_std - kShXOrig, y_std - kShYOrig};
}

CnshiftCoord Shcs2000ToWgs84(double y, double x) {
	const double x_std = y + kShXOrig;
	const double y_std = x + kShYOrig;
	const double mu = x_std / kShM0Bar;
	const double bf = mu + kShC1 * std::sin(2.0 * mu) + kShC2 * std::sin(4.0 * mu) + kShC3 * std::sin(6.0 * mu) +
	                  kShC4 * std::sin(8.0 * mu);
	const double sin_bf = std::sin(bf);
	const double cos_bf = std::cos(bf);
	const double t_f = std::tan(bf);
	const double eta_f2 = kShEp2 * cos_bf * cos_bf;
	const double nf = kShAEff / std::sqrt(1.0 - kShE2 * sin_bf * sin_bf);
	const double mf = kShAEff * (1.0 - kShE2) / std::pow(1.0 - kShE2 * sin_bf * sin_bf, 1.5);
	const double lat =
	    (bf - (t_f / (2.0 * mf * nf)) * (y_std * y_std) +
	     (t_f / (24.0 * mf * nf * nf * nf)) * (5.0 + 3.0 * t_f * t_f + eta_f2 - 9.0 * eta_f2 * t_f * t_f) *
	         (y_std * y_std * y_std * y_std)) *
	    180.0 / kPi;
	const double l =
	    ((1.0 / (nf * cos_bf)) * y_std -
	     ((1.0 + 2.0 * t_f * t_f + eta_f2) / (6.0 * nf * nf * nf * cos_bf)) * (y_std * y_std * y_std) +
	     ((5.0 + 28.0 * t_f * t_f + 24.0 * t_f * t_f * t_f * t_f) / (120.0 * std::pow(nf, 5.0) * cos_bf)) *
	         (y_std * y_std * y_std * y_std * y_std)) *
	    180.0 / kPi;
	return {lat, kShL0 + l};
}

CnshiftCoord Gcj02ToShcs2000(double lat, double lon) {
	const auto wgs = Gcj02ToWgs84(lat, lon);
	return Wgs84ToShcs2000(wgs.lat, wgs.lon);
}

CnshiftCoord Shcs2000ToGcj02(double y, double x) {
	const auto wgs = Shcs2000ToWgs84(y, x);
	return Wgs84ToGcj02(wgs.lat, wgs.lon);
}

CnshiftCoord Bd09ToShcs2000(double lat, double lon) {
	const auto wgs = Bd09ToWgs84(lat, lon);
	return Wgs84ToShcs2000(wgs.lat, wgs.lon);
}

CnshiftCoord Shcs2000ToBd09(double y, double x) {
	const auto wgs = Shcs2000ToWgs84(y, x);
	return Wgs84ToBd09(wgs.lat, wgs.lon);
}

} // namespace duckdb
