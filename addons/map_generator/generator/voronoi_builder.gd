@tool
class_name VoronoiBuilder
extends RefCounted

## Circumcenter of 3 points forming a triangle
static func compute_circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d: float = 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-6:
		return (a + b + c) / 3.0
	var a2: float = a.length_squared()
	var b2: float = b.length_squared()
	var c2: float = c.length_squared()
	var ux: float = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
	var uy: float = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
	return Vector2(ux, uy)

## Polygon area (shoelace formula)
static func compute_polygon_area(poly: PackedVector2Array) -> float:
	var n: int = poly.size()
	if n < 3:
		return 0.0
	var area: float = 0.0
	for i in range(n):
		var j: int = (i + 1) % n
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return absf(area) * 0.5

## Polygon centroid
static func compute_polygon_centroid(poly: PackedVector2Array) -> Vector2:
	var n: int = poly.size()
	if n < 3:
		return poly[0] if n > 0 else Vector2.ZERO
	var cx: float = 0.0
	var cy: float = 0.0
	var signed_area: float = 0.0
	for i in range(n):
		var j: int = (i + 1) % n
		var cross: float = poly[i].x * poly[j].y - poly[j].x * poly[i].y
		signed_area += cross
		cx += (poly[i].x + poly[j].x) * cross
		cy += (poly[i].y + poly[j].y) * cross
	var area: float = signed_area * 0.5
	if absf(area) < 1e-6:
		return poly[0]
	return Vector2(cx / (6.0 * area), cy / (6.0 * area))

## Generate Voronoi grid with optional Lloyd relaxation
static func generate(
	width: float,
	height: float,
	target_cells: int,
	rng: RandomNumberGenerator,
	relaxation_passes: int = 1
) -> Dictionary:
	var cols: int = int(round(sqrt(float(target_cells) * (width / height))))
	cols = clampi(cols, 4, 200)
	var rows: int = int(round(float(target_cells) / float(cols)))
	rows = clampi(rows, 4, 200)
	
	var dx: float = width / float(cols)
	var dy: float = height / float(rows)
	
	# Generate jittered grid points
	var raw_points: PackedVector2Array = PackedVector2Array()
	for r in range(rows):
		for c in range(cols):
			var px: float = (float(c) + 0.5 + rng.randf_range(-0.4, 0.4)) * dx
			var py: float = (float(r) + 0.5 + rng.randf_range(-0.4, 0.4)) * dy
			raw_points.append(Vector2(clampf(px, 1.0, width - 1.0), clampf(py, 1.0, height - 1.0)))
			
	var current_points: PackedVector2Array = raw_points
	var result: Dictionary = {}
	
	for pass_idx in range(relaxation_passes + 1):
		result = _build_voronoi_from_points(current_points, width, height)
		if pass_idx < relaxation_passes:
			# Lloyd relaxation: move points to centroids of their cells
			var new_points: PackedVector2Array = PackedVector2Array()
			var cells: Array = result["cell_polygons"]
			for i in range(cells.size()):
				var poly: PackedVector2Array = cells[i]
				if poly.size() >= 3:
					var centroid: Vector2 = compute_polygon_centroid(poly)
					new_points.append(Vector2(clampf(centroid.x, 1.0, width - 1.0), clampf(centroid.y, 1.0, height - 1.0)))
				else:
					new_points.append(current_points[i])
			current_points = new_points
			
	return result

## Internal: compute Voronoi dual & neighbor graph from points
static func _build_voronoi_from_points(inner_points: PackedVector2Array, width: float, height: float) -> Dictionary:
	var total_points: PackedVector2Array = PackedVector2Array()
	
	# 4 bounding boundary anchor points far outside canvas to guarantee Delaunay boundary
	var margin_x: float = width * 1.5
	var margin_y: float = height * 1.5
	total_points.append(Vector2(-margin_x, -margin_y))
	total_points.append(Vector2(width + margin_x, -margin_y))
	total_points.append(Vector2(width + margin_x, height + margin_y))
	total_points.append(Vector2(-margin_x, height + margin_y))
	
	var valid_start_idx: int = 4
	for p in inner_points:
		total_points.append(p)
		
	var triangles: PackedInt32Array = Geometry2D.triangulate_delaunay(total_points)
	var tri_count: int = triangles.size() / 3
	
	var tri_circumcenters: PackedVector2Array = PackedVector2Array()
	tri_circumcenters.resize(tri_count)
	
	var point_to_tris: Array[Array] = []
	point_to_tris.resize(total_points.size())
	for i in range(total_points.size()):
		point_to_tris[i] = []
		
	var raw_neighbors: Array[Array] = []
	raw_neighbors.resize(total_points.size())
	for i in range(total_points.size()):
		raw_neighbors[i] = []
		
	for t in range(tri_count):
		var i0: int = triangles[t * 3 + 0]
		var i1: int = triangles[t * 3 + 1]
		var i2: int = triangles[t * 3 + 2]
		
		var cc: Vector2 = compute_circumcenter(total_points[i0], total_points[i1], total_points[i2])
		tri_circumcenters[t] = cc
		
		point_to_tris[i0].append(t)
		point_to_tris[i1].append(t)
		point_to_tris[i2].append(t)
		
		# Record Delaunay edges as Voronoi neighbors
		var edge_pairs = [[i0, i1], [i1, i2], [i2, i0]]
		for pair in edge_pairs:
			var u: int = pair[0]
			var v: int = pair[1]
			if not (v in raw_neighbors[u]):
				raw_neighbors[u].append(v)
			if not (u in raw_neighbors[v]):
				raw_neighbors[v].append(u)
				
	var bounds_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(width, 0.0),
		Vector2(width, height),
		Vector2(0.0, height)
	])
	
	var cell_count: int = inner_points.size()
	var final_centers: PackedVector2Array = PackedVector2Array()
	var final_polygons: Array = []
	var final_neighbors: Array = []
	var final_areas: PackedFloat32Array = PackedFloat32Array()
	
	final_centers.resize(cell_count)
	final_polygons.resize(cell_count)
	final_neighbors.resize(cell_count)
	final_areas.resize(cell_count)
	
	for idx in range(cell_count):
		var point_idx: int = idx + valid_start_idx
		var p: Vector2 = total_points[point_idx]
		final_centers[idx] = p
		
		var tris_for_p: Array = point_to_tris[point_idx]
		var poly: PackedVector2Array = PackedVector2Array()
		
		if tris_for_p.size() >= 3:
			var verts: Array = []
			for t in tris_for_p:
				verts.append(tri_circumcenters[t])
			# Sort circumcenters radially counter-clockwise around p
			verts.sort_custom(func(v1: Vector2, v2: Vector2) -> bool:
				return (v1 - p).angle() < (v2 - p).angle()
			)
			var unclipped: PackedVector2Array = PackedVector2Array(verts)
			var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(unclipped, bounds_poly)
			if clipped.size() > 0:
				poly = clipped[0]
			else:
				poly = unclipped
		else:
			# Fallback if too few triangles
			var approx_d: float = sqrt((width * height) / float(maxi(cell_count, 1))) * 0.4
			poly = PackedVector2Array([
				p + Vector2(-approx_d, -approx_d),
				p + Vector2(approx_d, -approx_d),
				p + Vector2(approx_d, approx_d),
				p + Vector2(-approx_d, approx_d)
			])
			
		final_polygons[idx] = poly
		final_areas[idx] = compute_polygon_area(poly)
		
		# Remap neighbors back to [0, cell_count - 1]
		var valid_nb: Array[int] = []
		for nb_point_idx in raw_neighbors[point_idx]:
			if nb_point_idx >= valid_start_idx:
				var mapped_id: int = nb_point_idx - valid_start_idx
				if mapped_id < cell_count and mapped_id != idx:
					valid_nb.append(mapped_id)
		final_neighbors[idx] = valid_nb
		
	return {
		"width": width,
		"height": height,
		"cell_count": cell_count,
		"centers": final_centers,
		"cell_polygons": final_polygons,
		"cell_neighbors": final_neighbors,
		"cell_areas": final_areas
	}
