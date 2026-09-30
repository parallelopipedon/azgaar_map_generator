@tool
class_name NameGenerator
extends RefCounted

const REALM_PREFIXES = [
	"Ald", "Val", "Oak", "Verd", "Krag", "Sol", "Frost", "Iron", "Riven",
	"Ostar", "Aurel", "Zephyr", "Glen", "Storm", "High", "Dusk", "Amber",
	"Silver", "Eld", "Mor", "Sun", "Ash", "Falcon", "Raven", "Stone", "Gild"
]

const REALM_MIDDLES = [
	"en", "or", "an", "ar", "el", "is", "un", "ath", "ond", "er", "in", "am"
]

const REALM_SUFFIXES = [
	"ia", "oria", "haven", "mark", "gard", "land", "via", "cia", "burg",
	"mont", "vale", "dale", "reach", "wood", "spire", "dell", "shire", "wick"
]

const FAMOUS_REALMS = [
	"Valoria", "Oakhaven", "Verdantia", "Kragmar", "Solaria", "Frostpeak",
	"Ironhold", "Rivendell", "Ostaria", "Aurelia", "Zephyria", "Highmark",
	"Stormgard", "Duskwood", "Ambervale", "Silverglen", "Eldoria", "Morvath",
	"Sunspire", "Ravenmark", "Stonehaven", "Gildreach", "Windfall", "Falconridge"
]

const CAPITAL_PATTERNS = [
	"%s City", "%s City", "%s Capital",
	"Port %s", "Fort %s", "High %s",
	"%s Keep", "%s Prime"
]

## Generate N unique country names, drawing from optional custom_names first
static func generate_country_names(count: int, rng: RandomNumberGenerator, custom_names: Array = []) -> Array[String]:
	var result: Array[String] = []
	var used: Dictionary = {}
	
	# 1. First draw from custom names if provided
	if not custom_names.is_empty():
		var custom_pool: Array = custom_names.duplicate()
		for i in range(custom_pool.size() - 1, 0, -1):
			var j: int = rng.randi() % (i + 1)
			var tmp = custom_pool[i]
			custom_pool[i] = custom_pool[j]
			custom_pool[j] = tmp
		while not custom_pool.is_empty() and result.size() < count:
			var raw_item = custom_pool.pop_back()
			var name: String = str(raw_item).strip_edges()
			if not name.is_empty() and not used.has(name):
				used[name] = true
				result.append(name)
	
	# 2. Draw from famous realms pool
	var pool: Array = FAMOUS_REALMS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	while not pool.is_empty() and result.size() < count:
		var name: String = pool.pop_back()
		if not used.has(name):
			used[name] = true
			result.append(name)
			
	# 3. If more needed, generate procedurally
	while result.size() < count:
		var prefix: String = REALM_PREFIXES[rng.randi() % REALM_PREFIXES.size()]
		var suffix: String = REALM_SUFFIXES[rng.randi() % REALM_SUFFIXES.size()]
		var name: String = prefix + suffix
		if rng.randf() > 0.6:
			var mid: String = REALM_MIDDLES[rng.randi() % REALM_MIDDLES.size()]
			name = prefix + mid + suffix
		if not used.has(name):
			used[name] = true
			result.append(name)
			
	return result

## Generate an evocative capital city name for a country
static func generate_capital_name(country_name: String, rng: RandomNumberGenerator) -> String:
	var pattern: String = CAPITAL_PATTERNS[rng.randi() % CAPITAL_PATTERNS.size()]
	return pattern % country_name

