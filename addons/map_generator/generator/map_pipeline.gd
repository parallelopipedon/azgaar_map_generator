@tool
class_name MapPipeline
extends RefCounted

## Master generator pipeline connecting Voronoi, Heightmap, Countries, and GeoJSON
static func run(params: Dictionary) -> Dictionary:
	var t_start: int = Time.get_ticks_msec()
	
	var map_seed: int = params.get("seed", 12345)
	var width: float = params.get("width", 1200.0)
	var height: float = params.get("height", 800.0)
	var cell_count: int = params.get("cell_count", 800)
	var num_countries: int = params.get("num_countries", 7)
	var sea_level: float = params.get("sea_level", 0.42)
	var island_mask: bool = params.get("island_mask", true)
	var noise_freq: float = params.get("noise_frequency", 0.003)
	var coord_mode: GeoJsonSerializer.CoordMode = params.get("coord_mode", GeoJsonSerializer.CoordMode.GEO)
	var include_countries: bool = params.get("include_countries", true)
	var include_land: bool = params.get("include_land", true)
	var include_capitals: bool = params.get("include_capitals", true)
	var include_lakes: bool = params.get("include_lakes", include_land)
	var custom_names: Array = params.get("custom_names", [])
	var output_path: String = params.get("output_path", "res://output/world_map.geojson")
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed
	
	# Step 1: Generate Voronoi grid
	var t0: int = Time.get_ticks_msec()
	var voronoi: Dictionary = VoronoiBuilder.generate(width, height, cell_count, rng, 1)
	var t_voronoi: int = Time.get_ticks_msec() - t0
	
	# Step 2: Generate Heightmap & Landmasses
	var t1: int = Time.get_ticks_msec()
	var heightmap: Dictionary = HeightmapBuilder.generate(
		voronoi["centers"],
		width,
		height,
		map_seed,
		sea_level,
		noise_freq,
		4,
		island_mask
	)
	var t_heightmap: int = Time.get_ticks_msec() - t1
	
	# Step 3: Generate Countries & Expand Territories
	var t2: int = Time.get_ticks_msec()
	var countries_res: Dictionary = CountryBuilder.generate(voronoi, heightmap, num_countries, rng, custom_names)
	var t_countries: int = Time.get_ticks_msec() - t2
	
	# Step 4: Merge landmass polygons (if requested)
	var t3: int = Time.get_ticks_msec()
	var land_merged: Array[PackedVector2Array] = []
	if include_land:
		var land_indices: Array[int] = heightmap["land_indices"]
		var cell_polys: Array = voronoi["cell_polygons"]
		var land_polys_to_merge: Array = []
		for idx in land_indices:
			land_polys_to_merge.append(cell_polys[idx])
		land_merged = CountryBuilder.union_polygons(land_polys_to_merge)
	var t_land_merge: int = Time.get_ticks_msec() - t3
	
	# Step 4b: Extract inland lakes / seas
	var lake_merged: Array[PackedVector2Array] = _extract_inland_lakes(voronoi, heightmap, width, height)
	
	# Step 5: Serialize to GeoJSON
	var t4: int = Time.get_ticks_msec()
	var geojson: Dictionary = GeoJsonSerializer.serialize(
		countries_res,
		land_merged,
		width,
		height,
		coord_mode,
		include_countries,
		include_land,
		include_capitals,
		lake_merged,
		include_lakes
	)
	
	# Step 6: Save to file
	var save_error: Error = OK
	if not output_path.is_empty():
		save_error = GeoJsonSerializer.save_to_file(geojson, output_path, true)
	var t_export: int = Time.get_ticks_msec() - t4
	
	var total_time: int = Time.get_ticks_msec() - t_start
	
	return {
		"success": (save_error == OK),
		"error": save_error,
		"total_time_ms": total_time,
		"voronoi_time_ms": t_voronoi,
		"heightmap_time_ms": t_heightmap,
		"countries_time_ms": t_countries,
		"land_merge_time_ms": t_land_merge,
		"export_time_ms": t_export,
		"output_path": output_path,
		"countries": countries_res.get("countries", []),
		"land_polygons": land_merged,
		"lake_polygons": lake_merged,
		"voronoi": voronoi,
		"heightmap": heightmap,
		"geojson": geojson,
		"params": params
	}

## Identify and dissolve inland water cells (lakes and enclosed seas)
static func _extract_inland_lakes(voronoi: Dictionary, heightmap: Dictionary, width: float, height: float) -> Array[PackedVector2Array]:
	var is_land: Array[bool] = heightmap["is_land"]
	var cell_polys: Array = voronoi["cell_polygons"]
	var cell_neighbors: Array = voronoi["cell_neighbors"]
	
	var visited: Dictionary = {}
	var lake_components: Array = []
	for i in range(is_land.size()):
		if is_land[i] or (i in visited):
			continue
		var comp: Array[int] = []
		var q: Array[int] = [i]
		visited[i] = true
		while not q.is_empty():
			var curr: int = q.pop_front()
			comp.append(curr)
			for nb in cell_neighbors[curr]:
				if not is_land[nb] and not (nb in visited):
					visited[nb] = true
					q.append(nb)
		lake_components.append(comp)
		
	var lake_polys: Array[PackedVector2Array] = []
	for comp in lake_components:
		var touches_border: bool = false
		for c in comp:
			var poly: PackedVector2Array = cell_polys[c]
			for pt in poly:
				if pt.x <= 0.5 or pt.x >= width - 0.5 or pt.y <= 0.5 or pt.y >= height - 0.5:
					touches_border = true
					break
			if touches_border:
				break
		if not touches_border:
			var lake_cell_polys: Array = []
			for c in comp:
				lake_cell_polys.append(cell_polys[c])
			var merged: Array[PackedVector2Array] = CountryBuilder.union_polygons(lake_cell_polys)
			lake_polys.append_array(merged)
			
	return lake_polys
