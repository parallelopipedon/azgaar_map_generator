extends SceneTree

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--help" in args or "-h" in args:
		_print_help()
		quit()
		return

	var params: Dictionary = {
		"seed": randi() % 1000000,
		"width": 1200.0,
		"height": 800.0,
		"cell_count": 800,
		"num_countries": 7,
		"sea_level": 0.42,
		"island_mask": true,
		"coord_mode": GeoJsonSerializer.CoordMode.GEO,
		"include_countries": true,
		"include_land": true,
		"include_capitals": true,
		"include_lakes": true,
		"output_path": "res://output/world_map.geojson"
	}
	
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--seed" and i + 1 < args.size():
			params["seed"] = args[i + 1].to_int()
			i += 1
		elif arg == "--countries" and i + 1 < args.size():
			params["num_countries"] = args[i + 1].to_int()
			i += 1
		elif arg == "--cells" and i + 1 < args.size():
			params["cell_count"] = args[i + 1].to_int()
			i += 1
		elif arg in ["--sea", "--sea-level", "--sea_level"] and i + 1 < args.size():
			params["sea_level"] = args[i + 1].to_float()
			i += 1
		elif arg in ["--island-mask", "--island_mask", "--island-falloff", "--island_falloff"]:
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				var val: String = args[i + 1].to_lower()
				params["island_mask"] = (val in ["true", "1", "yes", "on"])
				i += 1
			else:
				params["island_mask"] = true
		elif arg in ["--no-island-mask", "--no_island_mask", "--no-island-falloff", "--no_island_falloff"]:
			params["island_mask"] = false
		elif arg in ["--no-countries", "--no_countries"]:
			params["include_countries"] = false
		elif arg in ["--no-land", "--no_land"]:
			params["include_land"] = false
		elif arg in ["--no-capitals", "--no_capitals"]:
			params["include_capitals"] = false
		elif arg in ["--no-lakes", "--no_lakes", "--no-lake", "--no_lake", "--no-seas", "--no_seas"]:
			params["include_lakes"] = false
		elif arg in ["--custom-names", "--custom_names"] and i + 1 < args.size():
			var val: String = args[i + 1]
			var names_list: Array = []
			if FileAccess.file_exists(val):
				var f: FileAccess = FileAccess.open(val, FileAccess.READ)
				if f:
					var txt: String = f.get_as_text()
					for line in txt.split("\n"):
						for part in line.split(","):
							var trimmed: String = part.strip_edges()
							if not trimmed.is_empty():
								names_list.append(trimmed)
			else:
				for part in val.split(","):
					var trimmed: String = part.strip_edges()
					if not trimmed.is_empty():
						names_list.append(trimmed)
			params["custom_names"] = names_list
			i += 1
		elif arg == "--width" and i + 1 < args.size():
			params["width"] = args[i + 1].to_float()
			i += 1
		elif arg == "--height" and i + 1 < args.size():
			params["height"] = args[i + 1].to_float()
			i += 1
		elif arg == "--size" and i + 1 < args.size():
			var parts: PackedStringArray = args[i + 1].to_lower().split("x")
			if parts.size() == 2:
				params["width"] = parts[0].to_float()
				params["height"] = parts[1].to_float()
			i += 1
		elif arg == "--out" and i + 1 < args.size():
			params["output_path"] = args[i + 1]
			i += 1
		elif arg == "--mode" and i + 1 < args.size():
			var m: String = args[i + 1].to_lower()
			if m in ["pixel", "pix", "px"]:
				params["coord_mode"] = GeoJsonSerializer.CoordMode.PIXEL
			elif m in ["normalized", "norm"]:
				params["coord_mode"] = GeoJsonSerializer.CoordMode.NORMALIZED
			else:
				params["coord_mode"] = GeoJsonSerializer.CoordMode.GEO
			i += 1
		i += 1
		
	print("[MapGenerator CLI] Generating %dx%d map with seed %d, %d countries (island mask: %s)..." % [
		int(params["width"]),
		int(params["height"]),
		params["seed"],
		params["num_countries"],
		str(params["island_mask"])
	])
	var res: Dictionary = MapPipeline.run(params)
	if res.get("success", false):
		print("[MapGenerator CLI] ✅ Successfully generated GeoJSON in %d ms -> %s" % [
			res.get("total_time_ms", 0),
			params["output_path"]
		])
	else:
		printerr("[MapGenerator CLI] ❌ Failed to generate GeoJSON (Error code: %d)" % res.get("error", -1))
	quit()

static func _print_help() -> void:
	print("""
Fantasy Map Generator - Headless CLI Runner

Usage:
  godot --headless -s addons/map_generator/cli_runner.gd -- [options]

Options:
  --seed <int>            RNG seed (default: random)
  --countries <int>       Target number of countries (default: 7)
  --cells <int>           Number of Voronoi sample points (default: 800)
  --width <float>         Canvas width in pixels (default: 1200)
  --height <float>        Canvas height in pixels (default: 800)
  --size <W>x<H>          Shorthand for width and height (e.g. 1920x1080)
  --sea, --sea-level <f>  Sea level threshold (0.15 - 0.75, default: 0.42)
  --island-mask [bool]    Radial edge-falloff mask for islands/continents (default: true)
  --no-island-mask        Disable island falloff mask
  --no-countries          Omit country territory polygons
  --no-land               Omit landmass / continent background polygon
  --no-capitals           Omit separate capital city Point features
  --no-lakes              Omit inland sea / lake polygons
  --custom-names <val>    Comma-separated list or file path of realm names to use
  --mode <geo|pixel|norm> Projection mode: 'geo' [Lon,Lat], 'pixel' [X,Y], or 'normalized' (default: geo)
  --out <path>            Output GeoJSON file path (default: res://output/world_map.geojson)
  --help, -h              Display this help message and exit
""")

