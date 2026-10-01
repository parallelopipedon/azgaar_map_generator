@tool
extends Control

@onready var seed_spin: SpinBox = $Scroll/VBox/Params/SeedRow/SeedSpin
@onready var rand_btn: Button = $Scroll/VBox/Params/SeedRow/RandBtn
@onready var width_spin: SpinBox = $Scroll/VBox/Params/DimRow/WidthSpin
@onready var height_spin: SpinBox = $Scroll/VBox/Params/DimRow/HeightSpin
@onready var cells_spin: SpinBox = $Scroll/VBox/Params/CellsSpin
@onready var countries_spin: SpinBox = $Scroll/VBox/Params/CountriesSpin
@onready var sea_slider: HSlider = $Scroll/VBox/Params/SeaRow/SeaSlider
@onready var sea_label: Label = $Scroll/VBox/Params/SeaRow/SeaVal
@onready var island_chk: CheckBox = $Scroll/VBox/Params/IslandChk
@onready var coord_opt: OptionButton = $Scroll/VBox/Params/CoordOpt
@onready var country_chk: CheckBox = $Scroll/VBox/Layers/CountryChk
@onready var land_chk: CheckBox = $Scroll/VBox/Layers/LandChk
@onready var capital_chk: CheckBox = $Scroll/VBox/Layers/CapitalChk
@onready var path_edit: LineEdit = $Scroll/VBox/Export/PathEdit
@onready var generate_btn: Button = $Scroll/VBox/GenerateBtn
@onready var status_lbl: Label = $Scroll/VBox/StatusLbl
@onready var preview_panel: Control = $Scroll/VBox/PreviewPanel

var current_result: Dictionary = {}

func _ready() -> void:
	if coord_opt.item_count == 0:
		coord_opt.add_item("Geo [Lon, Lat] (GIS)", GeoJsonSerializer.CoordMode.GEO)
		coord_opt.add_item("Pixel [X, Y] (Godot 2D)", GeoJsonSerializer.CoordMode.PIXEL)
		coord_opt.add_item("Normalized [0.0 - 1.0]", GeoJsonSerializer.CoordMode.NORMALIZED)
		coord_opt.selected = 0
		
	rand_btn.pressed.connect(_on_randomize_seed)
	generate_btn.pressed.connect(_on_generate_pressed)
	sea_slider.value_changed.connect(_on_sea_slider_changed)
	preview_panel.draw.connect(_on_preview_draw)
	
	_on_sea_slider_changed(sea_slider.value)

func _on_randomize_seed() -> void:
	seed_spin.value = randi() % 1000000

func _on_sea_slider_changed(val: float) -> void:
	sea_label.text = "%.2f" % val

func _on_generate_pressed() -> void:
	status_lbl.text = "Generating map and GeoJSON..."
	status_lbl.modulate = Color.YELLOW
	
	var mode: int = coord_opt.get_selected_id()
	var params: Dictionary = {
		"seed": int(seed_spin.value),
		"width": float(width_spin.value),
		"height": float(height_spin.value),
		"cell_count": int(cells_spin.value),
		"num_countries": int(countries_spin.value),
		"sea_level": float(sea_slider.value),
		"island_mask": island_chk.button_pressed,
		"coord_mode": mode,
		"include_countries": country_chk.button_pressed,
		"include_land": land_chk.button_pressed,
		"include_capitals": capital_chk.button_pressed,
		"output_path": path_edit.text.strip_edges()
	}
	
	var res: Dictionary = MapPipeline.run(params)
	current_result = res
	
	if res.get("success", false):
		var num_c: int = res.get("countries", []).size()
		var ms: int = res.get("total_time_ms", 0)
		status_lbl.text = "Success! %d countries exported to %s in %d ms" % [num_c, params["output_path"], ms]
		status_lbl.modulate = Color.GREEN
	else:
		status_lbl.text = "Error generating GeoJSON (Code: %d)" % res.get("error", -1)
		status_lbl.modulate = Color.RED
		
	preview_panel.queue_redraw()

func _on_preview_draw() -> void:
	var rect_size: Vector2 = preview_panel.get_rect().size
	if rect_size.x <= 10.0 or rect_size.y <= 10.0:
		return
		
	# Draw Ocean background
	preview_panel.draw_rect(Rect2(Vector2.ZERO, rect_size), Color("#1b2838"))
	
	if current_result.is_empty():
		preview_panel.draw_string(
			ThemeDB.fallback_font,
			Vector2(20, rect_size.y * 0.5),
			"Click 'Generate GeoJSON' to preview map",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(1, 1, 1, 0.4)
		)
		return
		
	var map_w: float = float(width_spin.value)
	var map_h: float = float(height_spin.value)
	var scale_x: float = rect_size.x / map_w
	var scale_y: float = rect_size.y / map_h
	var scale_factor: float = minf(scale_x, scale_y)
	
	var offset_x: float = (rect_size.x - map_w * scale_factor) * 0.5
	var offset_y: float = (rect_size.y - map_h * scale_factor) * 0.5
	
	var countries: Array = current_result.get("countries", [])
	for country in countries:
		var c_hex: String = country.get("color", "ffffff")
		var col: Color = Color.from_string(c_hex, Color.WHITE)
		col.a = 0.85
		var border_col: Color = col.darkened(0.4)
		border_col.a = 1.0
		
		var polys: Array = country.get("polygons", [])
		for p in polys:
			if p is PackedVector2Array and p.size() >= 3:
				var scaled: PackedVector2Array = PackedVector2Array()
				for pt in p:
					scaled.append(Vector2(pt.x * scale_factor + offset_x, pt.y * scale_factor + offset_y))
				preview_panel.draw_colored_polygon(scaled, col)
				if scaled.size() >= 3:
					var closed_pts: PackedVector2Array = scaled.duplicate()
					closed_pts.append(scaled[0])
					preview_panel.draw_polyline(closed_pts, border_col, 1.5)

	# Draw Inland Lakes / Seas in matching ocean color
	var lake_polys: Array = current_result.get("lake_polygons", [])
	for lake_p in lake_polys:
		if lake_p is PackedVector2Array and lake_p.size() >= 3:
			var scaled: PackedVector2Array = PackedVector2Array()
			for pt in lake_p:
				scaled.append(Vector2(pt.x * scale_factor + offset_x, pt.y * scale_factor + offset_y))
			preview_panel.draw_colored_polygon(scaled, Color("#1b2838"))
			if scaled.size() >= 3:
				var closed_pts: PackedVector2Array = scaled.duplicate()
				closed_pts.append(scaled[0])
				preview_panel.draw_polyline(closed_pts, Color(1, 1, 1, 0.25), 1.0)
					
	# Draw Capitals
	for country in countries:
		var cap_pt: Vector2 = country.get("capital_pos", Vector2.ZERO)
		var cap_screen: Vector2 = Vector2(cap_pt.x * scale_factor + offset_x, cap_pt.y * scale_factor + offset_y)
		preview_panel.draw_circle(cap_screen, 4.0, Color.WHITE)
		preview_panel.draw_circle(cap_screen, 2.5, Color.BLACK)
