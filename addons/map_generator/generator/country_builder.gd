@tool
class_name CountryBuilder
extends RefCounted

## Union an array of polygons into a minimal set of merged boundary polygons (Clipper C++)
static func union_polygons(polys: Array) -> Array[PackedVector2Array]:
	if polys.is_empty():
		return []
	var pool: Array[PackedVector2Array] = []
	for p in polys:
		if p is PackedVector2Array and p.size() >= 3:
			pool.append(p)
			
	if pool.is_empty():
		return []
		
	var changed: bool = true
	while changed and pool.size() > 1:
		changed = false
		var new_pool: Array[PackedVector2Array] = []
		var merged_indices: Dictionary = {}
		
		for i in range(pool.size()):
			if i in merged_indices:
				continue
			var curr: PackedVector2Array = pool[i]
			for j in range(i + 1, pool.size()):
				if j in merged_indices:
					continue
				var m: Array[PackedVector2Array] = Geometry2D.merge_polygons(curr, pool[j])
				var outers: Array[PackedVector2Array] = []
				for p in m:
					if p.size() >= 3 and absf(VoronoiBuilder.compute_polygon_area(p)) > 2.0:
						if not Geometry2D.is_polygon_clockwise(p):
							outers.append(p)
				if outers.size() == 1:
					curr = outers[0]
					merged_indices[j] = true
					changed = true
			if absf(VoronoiBuilder.compute_polygon_area(curr)) > 2.0:
				new_pool.append(curr)
		pool = new_pool
		
	return pool

## Generate distinct aesthetic colors using golden ratio HSV
static func generate_country_colors(count: int, rng: RandomNumberGenerator) -> Array[Color]:
	var colors: Array[Color] = []
	var golden_ratio_conjugate: float = 0.618033988749895
	var h: float = rng.randf()
	for i in range(count):
		h = fmod(h + golden_ratio_conjugate, 1.0)
		var s: float = rng.randf_range(0.55, 0.85)
		var v: float = rng.randf_range(0.70, 0.95)
		colors.append(Color.from_hsv(h, s, v))
	return colors

## Generate countries and distribute land cells via wavefront propagation
static func generate(
	voronoi_data: Dictionary,
	heightmap_data: Dictionary,
	num_countries: int,
	rng: RandomNumberGenerator,
	custom_names: Array = []
) -> Dictionary:

	var centers: PackedVector2Array = voronoi_data["centers"]
	var cell_polys: Array = voronoi_data["cell_polygons"]
	var cell_neighbors: Array = voronoi_data["cell_neighbors"]
	var cell_areas: PackedFloat32Array = voronoi_data["cell_areas"]
	var cell_count: int = centers.size()
	
	var heights: PackedFloat32Array = heightmap_data["heights"]
	var is_land: Array[bool] = heightmap_data["is_land"]
	var land_indices: Array[int] = heightmap_data["land_indices"]
	
	if land_indices.is_empty():
		return { "countries": [], "cell_to_country": [] }
		
	var actual_country_count: int = mini(num_countries, land_indices.size())
	actual_country_count = maxi(actual_country_count, 1)
	
	# 1. Select capital locations on land cells using furthest point sampling
	var capital_cells: Array[int] = []
	var first_idx: int = land_indices[rng.randi() % land_indices.size()]
	capital_cells.append(first_idx)
	
	for _c in range(1, actual_country_count):
		var best_candidate: int = -1
		var max_min_dist: float = -1.0
		# Sample a subset of candidates for performance
		var sample_count: int = mini(50, land_indices.size())
		for _s in range(sample_count):
			var cand_idx: int = land_indices[rng.randi() % land_indices.size()]
			if cand_idx in capital_cells:
				continue
			var p: Vector2 = centers[cand_idx]
			var min_dist: float = 1e9
			for cap in capital_cells:
				var d: float = p.distance_to(centers[cap])
				if d < min_dist:
					min_dist = d
			# Elevation suitability score: prefer mild elevation
			var h_score: float = 1.0 - absf(heights[cand_idx] - 0.55)
			var total_score: float = min_dist * (0.8 + 0.4 * h_score)
			if total_score > max_min_dist:
				max_min_dist = total_score
				best_candidate = cand_idx
		if best_candidate != -1:
			capital_cells.append(best_candidate)
		else:
			capital_cells.append(land_indices[rng.randi() % land_indices.size()])
			
	# 2. Dijkstra territory expansion across land cells
	var cell_country: Array[int] = []
	cell_country.resize(cell_count)
	cell_country.fill(-1)
	
	var cell_dist: Array[float] = []
	cell_dist.resize(cell_count)
	cell_dist.fill(1e9)
	
	# Priority queue: Array of [cost: float, cell_id: int, country_id: int]
	var queue: Array = []
	for country_id in range(actual_country_count):
		var cap_cell: int = capital_cells[country_id]
		cell_country[cap_cell] = country_id
		cell_dist[cap_cell] = 0.0
		queue.append([0.0, cap_cell, country_id])
		
	# Process wavefront
	while not queue.is_empty():
		# Pop minimum cost item
		queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var current_item: Array = queue.pop_front()
		var curr_cost: float = current_item[0]
		var curr_cell: int = current_item[1]
		var curr_country: int = current_item[2]
		
		if curr_cost > cell_dist[curr_cell] + 1e-4:
			continue
			
		for nb in cell_neighbors[curr_cell]:
			if not is_land[nb]:
				continue
			var dist_step: float = centers[curr_cell].distance_to(centers[nb])
			var h_cost: float = 1.0 + absf(heights[curr_cell] - heights[nb]) * 3.0
			var new_cost: float = curr_cost + dist_step * h_cost
			
			if new_cost < cell_dist[nb]:
				cell_dist[nb] = new_cost
				cell_country[nb] = curr_country
				queue.append([new_cost, nb, curr_country])
				
	# Claim any remaining disconnected land cells to nearest capital
	for idx in land_indices:
		if cell_country[idx] == -1:
			var best_c: int = 0
			var min_d: float = 1e9
			for c_id in range(actual_country_count):
				var d: float = centers[idx].distance_to(centers[capital_cells[c_id]])
				if d < min_d:
					min_d = d
					best_c = c_id
			cell_country[idx] = best_c
			
	# 3. Country Names & Colors
	var names: Array[String] = NameGenerator.generate_country_names(actual_country_count, rng, custom_names)
	var colors: Array[Color] = generate_country_colors(actual_country_count, rng)
	
	# 4. Group cells by country & build country features
	var country_cells: Array[Array] = []
	country_cells.resize(actual_country_count)
	for i in range(actual_country_count):
		country_cells[i] = []
		
	for i in land_indices:
		var c_id: int = cell_country[i]
		if c_id >= 0 and c_id < actual_country_count:
			country_cells[c_id].append(i)
			
	# 5. Detect neighboring countries
	var neighbor_sets: Array[Dictionary] = []
	neighbor_sets.resize(actual_country_count)
	for i in range(actual_country_count):
		neighbor_sets[i] = {}
		
	for i in range(cell_count):
		var c1: int = cell_country[i]
		if c1 == -1:
			continue
		for nb in cell_neighbors[i]:
			var c2: int = cell_country[nb]
			if c2 != -1 and c1 != c2:
				neighbor_sets[c1][c2] = true
				neighbor_sets[c2][c1] = true
				
	# 6. Build Country Records & Merge Polygons
	var countries: Array[Dictionary] = []
	for c_id in range(actual_country_count):
		var cells_in_c: Array = country_cells[c_id]
		if cells_in_c.is_empty():
			continue
			
		var total_area: float = 0.0
		var polys_to_merge: Array = []
		for cell_idx in cells_in_c:
			total_area += cell_areas[cell_idx]
			polys_to_merge.append(cell_polys[cell_idx])
			
		var merged_polygons: Array[PackedVector2Array] = union_polygons(polys_to_merge)
		var cap_idx: int = capital_cells[c_id]
		var capital_name: String = NameGenerator.generate_capital_name(names[c_id], rng)
		
		# Country stats for The Chancellor simulation
		var military: int = int(round(rng.randf_range(20.0, 95.0)))
		var wealth: int = int(round(rng.randf_range(20.0, 95.0)))
		var technology: int = int(round(rng.randf_range(20.0, 95.0)))
		var quality_of_life: int = int(round(rng.randf_range(20.0, 95.0)))
		var hospitality: int = int(round(rng.randf_range(-80.0, 80.0)))
		
		var nb_list: Array[int] = []
		for nb_id in neighbor_sets[c_id].keys():
			nb_list.append(int(nb_id) + 1) # 1-based ID for GeoJSON
		nb_list.sort()
		
		countries.append({
			"id": c_id + 1,
			"name": names[c_id],
			"color": "#%s" % colors[c_id].to_html(false),
			"capital_name": capital_name,
			"capital_pos": centers[cap_idx],
			"capital_cell": cap_idx,
			"label_pos": centers[cap_idx],
			"area": total_area,
			"cells_count": cells_in_c.size(),
			"polygons": merged_polygons,
			"military": military,
			"wealth": wealth,
			"technology": technology,
			"quality_of_life": quality_of_life,
			"hospitality": hospitality,
			"neighbors": nb_list
		})
		
	return {
		"countries": countries,
		"cell_country": cell_country,
		"capital_cells": capital_cells
	}
