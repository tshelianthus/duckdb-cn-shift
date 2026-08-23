#define DUCKDB_EXTENSION_MAIN

#include "cnshift_extension.hpp"
#include "cnshift_geometry.hpp"
#include "cnshift_transform.hpp"

#include "duckdb.hpp"
#include "duckdb/common/exception.hpp"
#include "duckdb/common/types/vector.hpp"
#include "duckdb/common/vector_operations/unary_executor.hpp"
#include "duckdb/function/function_set.hpp"
#include "duckdb/function/scalar_function.hpp"

#include <cmath>
#include <utility>

namespace duckdb {

// Algorithm constants and formulae: docs/ALGORITHM.md (single source of truth).
// Do not diverge without updating that document and shared golden fixtures.

static LogicalType MakeLatLonStructType() {
	child_list_t<LogicalType> children;
	children.emplace_back("lat", LogicalType::DOUBLE);
	children.emplace_back("lon", LogicalType::DOUBLE);
	return LogicalType::STRUCT(children);
}

static void ValidateLatLon(double lat, double lon) {
	if (std::isnan(lat) || std::isinf(lat) || lat < -90.0 || lat > 90.0) {
		throw OutOfRangeException("Latitude out of range: expected [-90, 90], got %f", lat);
	}
	if (std::isnan(lon) || std::isinf(lon) || lon < -180.0 || lon > 180.0) {
		throw OutOfRangeException("Longitude out of range: expected [-180, 180], got %f", lon);
	}
}

static void ExecuteCrsTransform(DataChunk &args, Vector &result, CnshiftTransformFn transform) {
	auto &lat_vec = args.data[0];
	auto &lon_vec = args.data[1];
	const idx_t count = args.size();

	if (lat_vec.GetVectorType() == VectorType::CONSTANT_VECTOR &&
	    lon_vec.GetVectorType() == VectorType::CONSTANT_VECTOR) {
		if (ConstantVector::IsNull(lat_vec) || ConstantVector::IsNull(lon_vec)) {
			result.Reference(Value(result.GetType()));
			return;
		}
		const double lat = ConstantVector::GetData<double>(lat_vec)[0];
		const double lon = ConstantVector::GetData<double>(lon_vec)[0];
		ValidateLatLon(lat, lon);
		const auto out = transform(lat, lon);
		result.Reference(Value::STRUCT(result.GetType(), {Value::DOUBLE(out.lat), Value::DOUBLE(out.lon)}));
		return;
	}

	UnifiedVectorFormat lat_data;
	UnifiedVectorFormat lon_data;
	lat_vec.ToUnifiedFormat(count, lat_data);
	lon_vec.ToUnifiedFormat(count, lon_data);
	auto lat_ptr = lat_data.GetData<double>();
	auto lon_ptr = lon_data.GetData<double>();

	result.SetVectorType(VectorType::FLAT_VECTOR);
	auto &entries = StructVector::GetEntries(result);
	entries[0]->SetVectorType(VectorType::FLAT_VECTOR);
	entries[1]->SetVectorType(VectorType::FLAT_VECTOR);
	auto lat_out = FlatVector::GetData<double>(*entries[0]);
	auto lon_out = FlatVector::GetData<double>(*entries[1]);

	for (idx_t i = 0; i < count; i++) {
		const auto lat_idx = lat_data.sel->get_index(i);
		const auto lon_idx = lon_data.sel->get_index(i);
		if (!lat_data.validity.RowIsValid(lat_idx) || !lon_data.validity.RowIsValid(lon_idx)) {
			lat_out[i] = 0.0;
			lon_out[i] = 0.0;
			FlatVector::SetNull(result, i, true);
			continue;
		}
		const double lat = lat_ptr[lat_idx];
		const double lon = lon_ptr[lon_idx];
		ValidateLatLon(lat, lon);
		const auto out = transform(lat, lon);
		lat_out[i] = out.lat;
		lon_out[i] = out.lon;
	}
}

template <CnshiftTransformFn FN>
static void CnshiftPointFun(DataChunk &args, ExpressionState &, Vector &result) {
	ExecuteCrsTransform(args, result, FN);
}

template <CnshiftTransformFn FN>
static void CnshiftGeomFun(DataChunk &args, ExpressionState &, Vector &result) {
	UnaryExecutor::Execute<string_t, string_t>(args.data[0], result, args.size(), [&](const string_t &wkb) {
		const auto out = TransformGeometryWkb(wkb, FN);
		return StringVector::AddStringOrBlob(result, out);
	});
}

static void RegisterCrsOverloads(ExtensionLoader &loader, const char *name, scalar_function_t point_fn,
                                 scalar_function_t geom_fn) {
	ScalarFunctionSet set(name);

	ScalarFunction point_fun({LogicalType::DOUBLE, LogicalType::DOUBLE}, MakeLatLonStructType(), point_fn);
	point_fun.SetFallible();
	set.AddFunction(std::move(point_fun));

	ScalarFunction geom_fun({LogicalType::GEOMETRY()}, LogicalType::GEOMETRY(), geom_fn);
	geom_fun.SetFallible();
	set.AddFunction(std::move(geom_fun));

	loader.RegisterFunction(set);
}

static void LoadInternal(ExtensionLoader &loader) {
	RegisterCrsOverloads(loader, "wgs84_to_gcj02", CnshiftPointFun<Wgs84ToGcj02>, CnshiftGeomFun<Wgs84ToGcj02>);
	RegisterCrsOverloads(loader, "gcj02_to_wgs84", CnshiftPointFun<Gcj02ToWgs84>, CnshiftGeomFun<Gcj02ToWgs84>);
	RegisterCrsOverloads(loader, "gcj02_to_bd09", CnshiftPointFun<Gcj02ToBd09>, CnshiftGeomFun<Gcj02ToBd09>);
	RegisterCrsOverloads(loader, "bd09_to_gcj02", CnshiftPointFun<Bd09ToGcj02>, CnshiftGeomFun<Bd09ToGcj02>);
	RegisterCrsOverloads(loader, "wgs84_to_bd09", CnshiftPointFun<Wgs84ToBd09>, CnshiftGeomFun<Wgs84ToBd09>);
	RegisterCrsOverloads(loader, "bd09_to_wgs84", CnshiftPointFun<Bd09ToWgs84>, CnshiftGeomFun<Bd09ToWgs84>);
}

void CnshiftExtension::Load(ExtensionLoader &loader) {
	LoadInternal(loader);
}

std::string CnshiftExtension::Name() {
	return "cnshift";
}

std::string CnshiftExtension::Version() const {
#ifdef EXT_VERSION_CNSHIFT
	return EXT_VERSION_CNSHIFT;
#else
	return "";
#endif
}

} // namespace duckdb

extern "C" {

DUCKDB_CPP_EXTENSION_ENTRY(cnshift, loader) {
	duckdb::LoadInternal(loader);
}
}
