extends Control

const MapPipeline = preload("res://addons/map_generator/generator/map_pipeline.gd")
const GeoJsonSerializer = preload("res://addons/map_generator/generator/geojson_serializer.gd")

@onready var seed_spin: SpinBox = %SeedSpin
@onready var rand_btn: Button = %RandBtn
@onready var width_spin: SpinBox = %WidthSpin
@onready var height_spin: SpinBox = %HeightSpin
@onready var cells_spin: SpinBox = %CellsSpin
@onready var countries_spin: SpinBox = %CountriesSpin
@onready var sea_slider: HSlider = %SeaSlider
@onready var sea_val: Label = %SeaVal
@onready var island_chk: CheckBox = %IslandChk
@onready var coord_opt: OptionButton = %CoordOpt
@onready var country_chk: CheckBox = %CountryChk
@onready var land_chk: CheckBox = %LandChk
@onready var capital_chk: CheckBox = %CapitalChk
@onready var path_edit: LineEdit = %PathEdit
@onready var generate_btn: Button = %GenerateBtn
@onready var status_lbl: Label = %StatusLbl
@onready var country_list: ItemList = %CountryList
@onready var map_canvas: Control = %MapCanvas
@onready var info_panel: PanelContainer = %InfoPanel
@onready var info_label: RichTextLabel = %InfoLabel

var current_result: Dictionary = {}
var hovered_country_id: int = -1

# Viewport Pan & Zoom
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_panning: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	coord_opt.add_item("Geo [Lon, Lat] (GIS Compatible)", GeoJsonSerializer.CoordMode.GEO)
	coord_opt.add_item("Pixel [X, Y] (Godot 2D)", GeoJsonSerializer.CoordMode.PIXEL)
	coord_opt.add_item("Normalized [0.0 - 1.0]", GeoJsonSerializer.CoordMode.NORMALIZED)
	coord_opt.selected = 0
	
	rand_btn.pressed.connect(_on_randomize_seed)
	generate_btn.pressed.connect(generate_map)
	sea_slider.value_changed.connect(func(v: float): sea_val.text = "%.2f" % v)
	
	map_canvas.draw.connect(_on_map_draw)
	map_canvas.gui_input.connect(_on_map_gui_input)
	
	country_list.item_selected.connect(_on_country_list_selected)
	
	# Initial generation
	generate_map()

func _on_randomize_seed() -> void:
	seed_spin.value = randi() % 1000000

func generate_map() -> void:
	status_lbl.text = "Generating map..."
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
		var countries: Array = res.get("countries", [])
		status_lbl.text = "✅ Generated %d countries in %d ms\nGeoJSON: %s" % [
			countries.size(),
			res.get("total_time_ms", 0),
			params["output_path"]
		]
		status_lbl.modulate = Color.GREEN
		_populate_country_list(countries)
	else:
		status_lbl.text = "❌ Generation failed (Error: %d)" % res.get("error", -1)
		status_lbl.modulate = Color.RED
		
	# Reset view zoom & pan
	_fit_map_to_canvas()
	map_canvas.queue_redraw()

func _populate_country_list(countries: Array) -> void:
	country_list.clear()
	for c in countries:
		var c_name: String = c.get("name", "Unknown")
		var c_id: int = c.get("id", 0)
		var c_color: Color = Color.from_string(c.get("color", "ffffff"), Color.WHITE)
		var idx: int = country_list.add_item("[%d] %s" % [c_id, c_name])
		country_list.set_item_custom_fg_color(idx, c_color)

func _fit_map_to_canvas() -> void:
	var canvas_size: Vector2 = map_canvas.size
	var map_w: float = float(width_spin.value)
	var map_h: float = float(height_spin.value)
	if canvas_size.x > 10.0 and canvas_size.y > 10.0 and map_w > 0.0 and map_h > 0.0:
		var sx: float = (canvas_size.x - 40.0) / map_w
		var sy: float = (canvas_size.y - 40.0) / map_h
		zoom_level = minf(sx, sy)
		pan_offset = (canvas_size - Vector2(map_w, map_h) * zoom_level) * 0.5

func _on_country_list_selected(index: int) -> void:
	var countries: Array = current_result.get("countries", [])
	if index >= 0 and index < countries.size():
		hovered_country_id = countries[index].get("id", -1)
		_update_info_panel(countries[index])
		map_canvas.queue_redraw()

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			var old_zoom: float = zoom_level
			zoom_level = clampf(zoom_level * 1.15, 0.2, 8.0)
			# Zoom towards mouse cursor
			var mouse_pos: Vector2 = event.position
			pan_offset = mouse_pos - (mouse_pos - pan_offset) * (zoom_level / old_zoom)
			map_canvas.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			var old_zoom: float = zoom_level
			zoom_level = clampf(zoom_level / 1.15, 0.2, 8.0)
			var mouse_pos: Vector2 = event.position
			pan_offset = mouse_pos - (mouse_pos - pan_offset) * (zoom_level / old_zoom)
			map_canvas.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				is_panning = true
				pan_start_mouse = event.position
				pan_start_offset = pan_offset
			else:
				is_panning = false
	elif event is InputEventMouseMotion:
		if is_panning:
			pan_offset = pan_start_offset + (event.position - pan_start_mouse)
			map_canvas.queue_redraw()
		else:
			# Raycast / Hit-test countries
			_check_hover(event.position)

func _check_hover(canvas_pos: Vector2) -> void:
	var map_pos: Vector2 = (canvas_pos - pan_offset) / zoom_level
	var countries: Array = current_result.get("countries", [])
	var found_id: int = -1
	var found_country: Dictionary = {}
	
	for c in countries:
		var polys: Array = c.get("polygons", [])
		for poly in polys:
			if poly is PackedVector2Array and poly.size() >= 3:
				if Geometry2D.is_point_in_polygon(map_pos, poly):
					found_id = c.get("id", -1)
					found_country = c
					break
		if found_id != -1:
			break
			
	if found_id != hovered_country_id:
		hovered_country_id = found_id
		if found_id != -1:
			_update_info_panel(found_country)
		else:
			info_panel.visible = false
		map_canvas.queue_redraw()

func _update_info_panel(c: Dictionary) -> void:
	info_panel.visible = true
	var hosp: int = c.get("hospitality", 0)
	var hosp_color: String = "green" if hosp >= 20 else ("orange" if hosp >= -20 else "red")
	var hosp_text: String = "Hospitable (+%d)" % hosp if hosp > 0 else ("Hostile (%d)" % hosp if hosp < 0 else "Neutral (0)")
	
	var text: String = "[b][font_size=17][color=%s]%s[/color][/font_size][/b]\n" % [
		c.get("color", "#ffffff"),
		c.get("name", "Unknown")
	]
	var cap_name: String = c.get("capital_name", "")
	if not cap_name.is_empty():
		text += "[color=#e0e0e0]Capital: [b]%s[/b][/color]\n" % cap_name
	text += "[color=gray]ID: %d | Cells: %d | Area: %.0f[/color]\n\n" % [
		c.get("id", 0),
		c.get("cells_count", 0),
		c.get("area", 0.0)
	]
	text += "[b]Diplomacy:[/b] [color=%s]%s[/color]\n" % [hosp_color, hosp_text]
	text += "[b]Military:[/b] %d / 100\n" % c.get("military", 50)
	text += "[b]Wealth:[/b] %d / 100\n" % c.get("wealth", 50)
	text += "[b]Technology:[/b] %d / 100\n" % c.get("technology", 50)
	text += "[b]Quality of Life:[/b] %d / 100\n" % c.get("quality_of_life", 50)
	text += "[b]Neighbors:[/b] %s\n" % str(c.get("neighbors", []))
	info_label.text = text

func _on_map_draw() -> void:
	var canvas_rect: Rect2 = Rect2(Vector2.ZERO, map_canvas.size)
	map_canvas.draw_rect(canvas_rect, Color("#0d1824")) # Deep Ocean
	
	if current_result.is_empty():
		return
		
	var map_w: float = float(width_spin.value)
	var map_h: float = float(height_spin.value)
	
	# Draw map bounding box / shallow ocean
	var map_box: Rect2 = Rect2(pan_offset, Vector2(map_w, map_h) * zoom_level)
	map_canvas.draw_rect(map_box, Color("#16293d"))
	map_canvas.draw_rect(map_box, Color(1, 1, 1, 0.15), false, 1.0)
	
	# Draw Landmass background outline if available
	var land_polys: Array = current_result.get("land_polygons", [])
	for land_p in land_polys:
		if land_p is PackedVector2Array and land_p.size() >= 3:
			var scaled: PackedVector2Array = PackedVector2Array()
			for pt in land_p:
				scaled.append(pt * zoom_level + pan_offset)
			map_canvas.draw_colored_polygon(scaled, Color("#2d4838"))
			
	# Draw Countries
	var countries: Array = current_result.get("countries", [])
	for country in countries:
		var c_id: int = country.get("id", -1)
		var is_hovered: bool = (c_id == hovered_country_id)
		
		var c_hex: String = country.get("color", "ffffff")
		var col: Color = Color.from_string(c_hex, Color.WHITE)
		col.a = 0.95 if is_hovered else 0.80
		
		var border_col: Color = Color.WHITE if is_hovered else col.darkened(0.5)
		var border_w: float = 2.5 if is_hovered else 1.2
		
		var polys: Array = country.get("polygons", [])
		for p in polys:
			if p is PackedVector2Array and p.size() >= 3:
				var scaled: PackedVector2Array = PackedVector2Array()
				for pt in p:
					scaled.append(pt * zoom_level + pan_offset)
				map_canvas.draw_colored_polygon(scaled, col)
				if scaled.size() >= 3:
					var closed_pts: PackedVector2Array = scaled.duplicate()
					closed_pts.append(scaled[0])
					map_canvas.draw_polyline(closed_pts, border_col, border_w)
					
		# Draw Capital marker and label
		var cap_pt: Vector2 = country.get("capital_pos", Vector2.ZERO)
		var cap_screen: Vector2 = cap_pt * zoom_level + pan_offset
		map_canvas.draw_circle(cap_screen, 5.0, Color.WHITE)
		map_canvas.draw_circle(cap_screen, 3.5, Color.BLACK)
		
		# Draw Country Name Label
		var label_text: String = country.get("name", "")
		var font: Font = ThemeDB.fallback_font
		var font_size: int = int(clampi(int(13.0 * zoom_level), 10, 20))
		map_canvas.draw_string(
			font,
			cap_screen + Vector2(8, 4),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color.WHITE
		)
