@tool
class_name MapGenerator
extends RefCounted

## Coordinate mode enumeration for GeoJSON output
enum CoordMode {
	PIXEL = GeoJsonSerializer.CoordMode.PIXEL,
	GEO = GeoJsonSerializer.CoordMode.GEO,
	NORMALIZED = GeoJsonSerializer.CoordMode.NORMALIZED
}

## Returns default generation parameters
static func get_default_params() -> Dictionary:
	return {
		"seed": randi() % 1000000,
		"width": 1200.0,
		"height": 800.0,
		"cell_count": 800,
		"num_countries": 7,
		"sea_level": 0.42,
		"island_mask": true,
		"noise_frequency": 0.003,
		"coord_mode": CoordMode.GEO,
		"include_countries": true,
		"include_land": true,
		"include_capitals": true,
		"include_lakes": true,
		"custom_names": [],
		"output_path": ""
	}

## Master generation method.
## Returns a result dictionary containing:
##   - "success": bool
##   - "total_time_ms": int
##   - "countries": Array[Dictionary] (name, color, capital_name, capital_pos, area, cells_count, polygons, stats, neighbors)
##   - "land_polygons": Array[PackedVector2Array]
##   - "lake_polygons": Array[PackedVector2Array]
##   - "geojson": Dictionary (RFC 7946 FeatureCollection)
##   - "voronoi": Dictionary (raw Voronoi cell graph)
##   - "heightmap": Dictionary (raw heightmap values & classification)
static func generate(params: Dictionary = {}) -> Dictionary:
	var final_params: Dictionary = get_default_params()
	final_params.merge(params, true)
	return MapPipeline.run(final_params)

## Generates map and returns serialized GeoJSON JSON string.
static func generate_geojson_string(params: Dictionary = {}, pretty: bool = true) -> String:
	var res: Dictionary = generate(params)
	var geojson_dict: Dictionary = res.get("geojson", {})
	return JSON.stringify(geojson_dict, "  " if pretty else "")

## Generates map and saves directly to target file path (e.g. "res://Assets/Data/world.geojson").
## Returns Error (OK on success).
static func generate_geojson_file(output_path: String, params: Dictionary = {}) -> Error:
	var final_params: Dictionary = params.duplicate()
	final_params["output_path"] = output_path
	var res: Dictionary = generate(final_params)
	if not res.get("success", false):
		return res.get("error", FAILED)
	return OK

## Generates countries-only GeoJSON (omits background landmass, inland seas, and separate point features).
## Ideal for game territory renderers like The Chancellor's GeoMap.
static func generate_countries_only_file(output_path: String, params: Dictionary = {}) -> Error:
	var final_params: Dictionary = params.duplicate()
	final_params["include_countries"] = true
	final_params["include_land"] = false
	final_params["include_capitals"] = false
	final_params["include_lakes"] = false
	return generate_geojson_file(output_path, final_params)

