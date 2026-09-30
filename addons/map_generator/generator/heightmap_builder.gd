@tool
class_name HeightmapBuilder
extends RefCounted

## Generates procedural elevation and land/ocean classification
static func generate(
	centers: PackedVector2Array,
	width: float,
	height: float,
	seed_val: int,
	sea_level: float = 0.42,
	noise_frequency: float = 0.003,
	octaves: int = 4,
	apply_island_mask: bool = true
) -> Dictionary:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.frequency = noise_frequency
	
	var cell_count: int = centers.size()
	var heights: PackedFloat32Array = PackedFloat32Array()
	var is_land: Array[bool] = []
	heights.resize(cell_count)
	is_land.resize(cell_count)
	
	var land_indices: Array[int] = []
	var ocean_indices: Array[int] = []
	
	var center_x: float = width * 0.5
	var center_y: float = height * 0.5
	var max_dist: float = sqrt(center_x * center_x + center_y * center_y)
	
	for i in range(cell_count):
		var p: Vector2 = centers[i]
		# Sample simplex noise [-1.0, 1.0] -> normalize to [0.0, 1.0]
		var raw_n: float = (noise.get_noise_2d(p.x, p.y) + 1.0) * 0.5
		
		# Island mask falloff: smoothly drop elevation towards the edges of the map
		if apply_island_mask:
			var dx: float = (p.x - center_x) / center_x
			var dy: float = (p.y - center_y) / center_y
			var dist_norm: float = sqrt(dx * dx + dy * dy)
			# Smoothstep falloff starting at 0.5 towards 1.1
			var falloff: float = clampf(1.0 - smoothstep(0.45, 1.05, dist_norm), 0.0, 1.0)
			raw_n = raw_n * falloff
			
		var h: float = clampf(raw_n, 0.0, 1.0)
		heights[i] = h
		
		var land: bool = (h >= sea_level)
		is_land[i] = land
		if land:
			land_indices.append(i)
		else:
			ocean_indices.append(i)
			
	return {
		"heights": heights,
		"is_land": is_land,
		"land_indices": land_indices,
		"ocean_indices": ocean_indices,
		"sea_level": sea_level
	}
