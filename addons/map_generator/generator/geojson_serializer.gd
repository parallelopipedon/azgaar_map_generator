@tool
class_name GeoJsonSerializer
extends RefCounted

enum CoordMode {
	PIXEL,
	GEO,
	NORMALIZED
}

## Convert 2D point according to coordinate mode
static func transform_point(p: Vector2, width: float, height: float, mode: CoordMode) -> Array:
	match mode:
		CoordMode.GEO:
			var lon: float = -180.0 + (p.x / width) * 360.0
			var lat: float = 90.0 - (p.y / height) * 180.0
			return [snappedf(lon, 0.0001), snappedf(lat, 0.0001)]
		CoordMode.NORMALIZED:
			return [snappedf(p.x / width, 0.0001), snappedf(p.y / height, 0.0001)]
		CoordMode.PIXEL:
			return [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
	return [p.x, p.y]

## Convert PackedVector2Array polygon into GeoJSON LinearRing (closed ring)
static func polygon_to_ring(poly: PackedVector2Array, width: float, height: float, mode: CoordMode) -> Array:
	var ring: Array = []
	var n: int = poly.size()
	if n < 3:
		return ring
		
	# Ensure Counter-Clockwise winding for exterior ring
	var is_cw: bool = Geometry2D.is_polygon_clockwise(poly)
	var ordered: PackedVector2Array = poly.duplicate()
	if is_cw:
		ordered.reverse()
		
	for pt in ordered:
		ring.append(transform_point(pt, width, height, mode))
		
	# Ensure closed ring (last point equals first point)
	if ring.size() > 0:
		var first: Array = ring[0]
		var last: Array = ring[ring.size() - 1]
		if first[0] != last[0] or first[1] != last[1]:
			ring.append([first[0], first[1]])
			
	return ring

## Build GeoJSON FeatureCollection
static func serialize(
	countries_data: Dictionary,
	land_polygons: Array[PackedVector2Array],
	width: float,
	height: float,
	mode: CoordMode = CoordMode.GEO,
	include_countries: bool = true,
	include_land: bool = true,
	include_capitals: bool = true
) -> Dictionary:
	var features: Array = []
	var countries: Array = countries_data.get("countries", [])
	
	# 1. Landmass / Continent features
	if include_land and not land_polygons.is_empty():
		var land_multi_coords: Array = []
		for poly in land_polygons:
			if poly.size() >= 3:
				var ring: Array = polygon_to_ring(poly, width, height, mode)
				if ring.size() >= 4:
					land_multi_coords.append([ring])
					
		if not land_multi_coords.is_empty():
			features.append({
				"type": "Feature",
				"id": "landmasses",
				"geometry": {
					"type": "MultiPolygon" if land_multi_coords.size() > 1 else "Polygon",
					"coordinates": land_multi_coords if land_multi_coords.size() > 1 else land_multi_coords[0]
				},
				"properties": {
					"name": "Landmass",
					"type": "land"
				}
			})
			
	# 2. Country features
	if include_countries:
		for country in countries:
			var polys: Array = country.get("polygons", [])
			if polys.is_empty():
				continue
				
			var country_rings: Array = []
			for p in polys:
				if p is PackedVector2Array and p.size() >= 3:
					var ring: Array = polygon_to_ring(p, width, height, mode)
					if ring.size() >= 4:
						country_rings.append([ring])
						
			if country_rings.is_empty():
				continue
				
			var geometry: Dictionary = {}
			if country_rings.size() == 1:
				geometry = {
					"type": "Polygon",
					"coordinates": country_rings[0]
				}
			else:
				geometry = {
					"type": "MultiPolygon",
					"coordinates": country_rings
				}
				
			var cap_pt: Vector2 = country.get("capital_pos", Vector2.ZERO)
			var cap_coords: Array = transform_point(cap_pt, width, height, mode)
			var label_pt: Vector2 = country.get("label_pos", cap_pt)
			var label_coords: Array = transform_point(label_pt, width, height, mode)
			var cap_name: String = country.get("capital_name", "%s City" % country.get("name", "Unknown"))
			
			features.append({
				"type": "Feature",
				"id": country.get("id"),
				"geometry": geometry,
				"properties": {
					"id": country.get("id"),
					"name": country.get("name"),
					"type": "country",
					"color": country.get("color"),
					"capital": cap_name,
					"capital_coords": cap_coords,
					"label_x": label_coords[0],
					"label_y": label_coords[1],
					"area": snappedf(country.get("area", 0.0), 0.1),
					"cells_count": country.get("cells_count", 0),
					"military": country.get("military", 50),
					"wealth": country.get("wealth", 50),
					"technology": country.get("technology", 50),
					"quality_of_life": country.get("quality_of_life", 50),
					"hospitality": country.get("hospitality", 0),
					"neighbors": country.get("neighbors", [])
				}
			})
			
	# 3. Capital City Point features
	if include_capitals and include_countries:
		for country in countries:
			var cap_pt: Vector2 = country.get("capital_pos", Vector2.ZERO)
			var cap_coords: Array = transform_point(cap_pt, width, height, mode)
			var cap_name: String = country.get("capital_name", "%s City" % country.get("name", "Unknown"))
			features.append({
				"type": "Feature",
				"id": "capital_%d" % country.get("id"),
				"geometry": {
					"type": "Point",
					"coordinates": cap_coords
				},
				"properties": {
					"name": cap_name,
					"country_id": country.get("id"),
					"country_name": country.get("name"),
					"type": "capital"
				}
			})
			
	return {
		"type": "FeatureCollection",
		"features": features
	}

## Save dictionary as JSON to file
static func save_to_file(geojson_dict: Dictionary, file_path: String, pretty: bool = true) -> Error:
	var dir_path: String = file_path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
		
	var json_str: String = JSON.stringify(geojson_dict, "  " if pretty else "")
	file.store_string(json_str)
	file.close()
	return OK
