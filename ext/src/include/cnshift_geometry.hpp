#pragma once

#include "cnshift_transform.hpp"
#include "duckdb/common/types.hpp"
#include "duckdb/common/types/string_type.hpp"

#include <string>

namespace duckdb {

// DuckDB v1.5 GEOMETRY is core little-endian ISO WKB (docs: geometry storage).
// Walk XY only; keep type / rings / Multi* part count. Nested GeometryCollection
// is flattened then collected (ST_Dump + ST_Collect), matching sql/cnshift.sql.

using CnshiftTransformFn = CnshiftCoord (*)(double, double);

std::string TransformGeometryWkb(const string_t &wkb, CnshiftTransformFn transform);

} // namespace duckdb
