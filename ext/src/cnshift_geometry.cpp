#include "cnshift_geometry.hpp"

#include "duckdb/common/exception.hpp"
#include "duckdb/common/types.hpp"
#include "duckdb/common/types/string_type.hpp"

#include <cmath>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

namespace duckdb {

namespace {

constexpr idx_t kMaxRecursion = 32;
constexpr uint32_t kTypePoint = 1;
constexpr uint32_t kTypeLineString = 2;
constexpr uint32_t kTypePolygon = 3;
constexpr uint32_t kTypeMultiPoint = 4;
constexpr uint32_t kTypeMultiLineString = 5;
constexpr uint32_t kTypeMultiPolygon = 6;
constexpr uint32_t kTypeGeometryCollection = 7;

struct Vertex {
	double coords[4] = {0, 0, 0, 0};
	uint32_t dims = 2;
};

bool VertexAllNan(const Vertex &v) {
	for (uint32_t i = 0; i < v.dims; i++) {
		if (!std::isnan(v.coords[i])) {
			return false;
		}
	}
	return v.dims > 0;
}

struct Geom {
	uint32_t type = 0;
	bool has_z = false;
	bool has_m = false;
	std::vector<Vertex> verts;
	std::vector<std::vector<Vertex>> rings;
	std::vector<Geom> parts;
};

class WkbReader {
public:
	WkbReader(const char *data_p, idx_t size_p) : data(data_p), size(size_p), pos(0) {
	}

	bool AtEnd() const {
		return pos >= size;
	}

	uint8_t ReadU8() {
		Need(1);
		return static_cast<uint8_t>(data[pos++]);
	}

	uint32_t ReadU32LE() {
		Need(4);
		const auto *p = reinterpret_cast<const unsigned char *>(data + pos);
		pos += 4;
		return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) | (static_cast<uint32_t>(p[2]) << 16) |
		       (static_cast<uint32_t>(p[3]) << 24);
	}

	double ReadF64LE() {
		Need(8);
		uint64_t u = 0;
		const auto *p = reinterpret_cast<const unsigned char *>(data + pos);
		pos += 8;
		for (int i = 0; i < 8; i++) {
			u |= static_cast<uint64_t>(p[i]) << (8 * i);
		}
		double d = 0;
		std::memcpy(&d, &u, sizeof(double));
		return d;
	}

	void Need(idx_t n) const {
		if (pos + n > size) {
			throw InvalidInputException("cnshift: truncated WKB geometry");
		}
	}

private:
	const char *data;
	idx_t size;
	idx_t pos;
};

class WkbWriter {
public:
	void WriteU8(uint8_t v) {
		buf.push_back(static_cast<char>(v));
	}

	void WriteU32LE(uint32_t v) {
		buf.push_back(static_cast<char>(v & 0xFF));
		buf.push_back(static_cast<char>((v >> 8) & 0xFF));
		buf.push_back(static_cast<char>((v >> 16) & 0xFF));
		buf.push_back(static_cast<char>((v >> 24) & 0xFF));
	}

	void WriteF64LE(double d) {
		uint64_t u = 0;
		std::memcpy(&u, &d, sizeof(double));
		for (int i = 0; i < 8; i++) {
			buf.push_back(static_cast<char>((u >> (8 * i)) & 0xFF));
		}
	}

	const std::vector<char> &Buffer() const {
		return buf;
	}

private:
	std::vector<char> buf;
};

void DecodeMeta(uint32_t meta, uint32_t &type, bool &has_z, bool &has_m) {
	// DuckDB v1.5 ISO WKB: type + 1000*Z + 2000*M on the low 16 bits.
	if (meta & 0xE0000000) {
		throw InvalidInputException("cnshift: unsupported EWKB flags in GEOMETRY");
	}
	const uint32_t iso = meta & 0x0000FFFF;
	type = iso % 1000;
	const uint32_t flag = iso / 1000;
	if (type < 1 || type > 7) {
		throw InvalidInputException("cnshift: unsupported WKB geometry type %u", type);
	}
	if (flag > 3) {
		throw InvalidInputException("cnshift: unsupported WKB vertex flag %u", flag);
	}
	has_z = (flag & 0x01) != 0;
	has_m = (flag & 0x02) != 0;
}

uint32_t EncodeMeta(uint32_t type, bool has_z, bool has_m) {
	return type + (has_z ? 1000u : 0u) + (has_m ? 2000u : 0u);
}

uint32_t Dims(bool has_z, bool has_m) {
	return 2 + (has_z ? 1 : 0) + (has_m ? 1 : 0);
}

Vertex ReadVertex(WkbReader &r, bool has_z, bool has_m) {
	Vertex v;
	v.dims = Dims(has_z, has_m);
	for (uint32_t i = 0; i < v.dims; i++) {
		v.coords[i] = r.ReadF64LE();
	}
	return v;
}

Geom ReadGeom(WkbReader &r, idx_t depth);

Geom ReadGeomBody(WkbReader &r, uint32_t type, bool has_z, bool has_m, idx_t depth) {
	Geom g;
	g.type = type;
	g.has_z = has_z;
	g.has_m = has_m;
	switch (type) {
	case kTypePoint:
		g.verts.push_back(ReadVertex(r, has_z, has_m));
		break;
	case kTypeLineString: {
		const uint32_t n = r.ReadU32LE();
		g.verts.reserve(n);
		for (uint32_t i = 0; i < n; i++) {
			g.verts.push_back(ReadVertex(r, has_z, has_m));
		}
		break;
	}
	case kTypePolygon: {
		const uint32_t n_rings = r.ReadU32LE();
		g.rings.resize(n_rings);
		for (uint32_t i = 0; i < n_rings; i++) {
			const uint32_t n = r.ReadU32LE();
			g.rings[i].reserve(n);
			for (uint32_t j = 0; j < n; j++) {
				g.rings[i].push_back(ReadVertex(r, has_z, has_m));
			}
		}
		break;
	}
	case kTypeMultiPoint:
	case kTypeMultiLineString:
	case kTypeMultiPolygon:
	case kTypeGeometryCollection: {
		const uint32_t n = r.ReadU32LE();
		g.parts.reserve(n);
		for (uint32_t i = 0; i < n; i++) {
			g.parts.push_back(ReadGeom(r, depth + 1));
		}
		break;
	}
	default:
		throw InvalidInputException("cnshift: unsupported WKB geometry type %u", type);
	}
	return g;
}

Geom ReadGeom(WkbReader &r, idx_t depth) {
	if (depth > kMaxRecursion) {
		throw InvalidInputException("cnshift: geometry exceeds maximum recursion depth");
	}
	const uint8_t order = r.ReadU8();
	if (order != 1) {
		throw InvalidInputException("cnshift: only little-endian WKB is supported");
	}
	uint32_t type = 0;
	bool has_z = false;
	bool has_m = false;
	DecodeMeta(r.ReadU32LE(), type, has_z, has_m);
	return ReadGeomBody(r, type, has_z, has_m, depth);
}

void WriteVertex(WkbWriter &w, const Vertex &v) {
	for (uint32_t i = 0; i < v.dims; i++) {
		w.WriteF64LE(v.coords[i]);
	}
}

void WriteGeom(WkbWriter &w, const Geom &g) {
	w.WriteU8(1);
	w.WriteU32LE(EncodeMeta(g.type, g.has_z, g.has_m));
	switch (g.type) {
	case kTypePoint:
		if (g.verts.empty()) {
			Vertex nan;
			nan.dims = Dims(g.has_z, g.has_m);
			for (uint32_t i = 0; i < nan.dims; i++) {
				nan.coords[i] = std::numeric_limits<double>::quiet_NaN();
			}
			WriteVertex(w, nan);
		} else {
			WriteVertex(w, g.verts[0]);
		}
		break;
	case kTypeLineString:
		w.WriteU32LE(static_cast<uint32_t>(g.verts.size()));
		for (const auto &v : g.verts) {
			WriteVertex(w, v);
		}
		break;
	case kTypePolygon:
		w.WriteU32LE(static_cast<uint32_t>(g.rings.size()));
		for (const auto &ring : g.rings) {
			w.WriteU32LE(static_cast<uint32_t>(ring.size()));
			for (const auto &v : ring) {
				WriteVertex(w, v);
			}
		}
		break;
	case kTypeMultiPoint:
	case kTypeMultiLineString:
	case kTypeMultiPolygon:
	case kTypeGeometryCollection:
		w.WriteU32LE(static_cast<uint32_t>(g.parts.size()));
		for (const auto &part : g.parts) {
			WriteGeom(w, part);
		}
		break;
	default:
		throw InvalidInputException("cnshift: cannot serialize WKB type %u", g.type);
	}
}

bool IsEmpty(const Geom &g) {
	switch (g.type) {
	case kTypePoint:
		return g.verts.empty() || VertexAllNan(g.verts[0]);
	case kTypeLineString:
		return g.verts.empty();
	case kTypePolygon:
		return g.rings.empty();
	case kTypeMultiPoint:
	case kTypeMultiLineString:
	case kTypeMultiPolygon:
	case kTypeGeometryCollection:
		return g.parts.empty();
	default:
		return false;
	}
}

void TransformVertex(Vertex &v, CnshiftTransformFn transform) {
	if (VertexAllNan(v) || !std::isfinite(v.coords[0]) || !std::isfinite(v.coords[1])) {
		return;
	}
	// X = lon, Y = lat. Public kernel is (lat, lon).
	const auto out = transform(v.coords[1], v.coords[0]);
	v.coords[0] = out.lon;
	v.coords[1] = out.lat;
}

void FlattenAtomic(const Geom &g, std::vector<Geom> &out) {
	switch (g.type) {
	case kTypePoint:
	case kTypeLineString:
	case kTypePolygon:
		out.push_back(g);
		break;
	case kTypeMultiPoint:
	case kTypeMultiLineString:
	case kTypeMultiPolygon:
	case kTypeGeometryCollection:
		for (const auto &part : g.parts) {
			FlattenAtomic(part, out);
		}
		break;
	default:
		break;
	}
}

Geom CollectLikeSql(std::vector<Geom> parts) {
	Geom out;
	if (parts.empty()) {
		out.type = kTypeGeometryCollection;
		return out;
	}
	const uint32_t t = parts[0].type;
	bool homo = true;
	for (const auto &p : parts) {
		if (p.type != t) {
			homo = false;
			break;
		}
	}
	if (homo && t == kTypePoint) {
		out.type = kTypeMultiPoint;
	} else if (homo && t == kTypeLineString) {
		out.type = kTypeMultiLineString;
	} else if (homo && t == kTypePolygon) {
		out.type = kTypeMultiPolygon;
	} else {
		out.type = kTypeGeometryCollection;
	}
	out.has_z = parts[0].has_z;
	out.has_m = parts[0].has_m;
	out.parts = std::move(parts);
	return out;
}

void TransformInPlace(Geom &g, CnshiftTransformFn transform) {
	switch (g.type) {
	case kTypePoint:
	case kTypeLineString:
		for (auto &v : g.verts) {
			TransformVertex(v, transform);
		}
		break;
	case kTypePolygon:
		for (auto &ring : g.rings) {
			for (auto &v : ring) {
				TransformVertex(v, transform);
			}
		}
		break;
	case kTypeMultiPoint:
	case kTypeMultiLineString:
	case kTypeMultiPolygon:
		for (auto &part : g.parts) {
			TransformInPlace(part, transform);
		}
		break;
	case kTypeGeometryCollection: {
		std::vector<Geom> atomics;
		FlattenAtomic(g, atomics);
		for (auto &a : atomics) {
			TransformInPlace(a, transform);
		}
		g = CollectLikeSql(std::move(atomics));
		break;
	}
	default:
		throw InvalidInputException("cnshift: unsupported geometry type %u", g.type);
	}
}

} // namespace

std::string TransformGeometryWkb(const string_t &wkb, CnshiftTransformFn transform) {
	if (wkb.GetSize() == 0) {
		throw InvalidInputException("cnshift: empty GEOMETRY blob");
	}
	WkbReader reader(wkb.GetData(), wkb.GetSize());
	Geom g = ReadGeom(reader, 0);
	if (!reader.AtEnd()) {
		throw InvalidInputException("cnshift: trailing bytes in GEOMETRY WKB");
	}
	if (IsEmpty(g)) {
		return std::string(wkb.GetData(), wkb.GetSize());
	}
	TransformInPlace(g, transform);
	WkbWriter writer;
	WriteGeom(writer, g);
	const auto &buf = writer.Buffer();
	return std::string(buf.data(), buf.size());
}

} // namespace duckdb
