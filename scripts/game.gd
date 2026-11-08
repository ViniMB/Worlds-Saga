extends Node
## Global state: the loaded world, the save file, settings, voices and the shared look (fonts, colours, panels).

signal saved

const SAVE_PATH := "user://save.json"
const SCALE := 5            # backgrounds are 144×96 pixel art, drawn 5× in a 720×480 viewport
const CHAR := 32            # character sheets are 32×32 cells
const FRAMES := 8           # animated backgrounds have 8 frames
const FRAME_MS := 160

var world: Dictionary = {}
var world_id = "london"
var voice_index: Dictionary = {}
var voice_streams: Dictionary = {}
var save: Dictionary = {}
var auto = false           # autotest: answers every question correctly, no waiting

var font_body: Font
var font_bold: Font
var font_pixel: Font
var voice_player: AudioStreamPlayer
var voice_timer: Timer

const INK := Color("#1b1d2a")
const PAPER := Color("#f4efe0")
const GOLD := Color("#f5c542")
const RED := Color("#e5484d")
const GREEN := Color("#3ccb7f")
const PANEL := Color(0.07, 0.08, 0.13, 0.92)

func _ready() -> void:
	auto = "--autotest" in OS.get_cmdline_user_args()
	font_body = _no_liga("res://assets/fonts/pixelify-sans-latin-400-normal.woff2")
	font_bold = _no_liga("res://assets/fonts/pixelify-sans-latin-700-normal.woff2")
	font_pixel = _no_liga("res://assets/fonts/silkscreen-latin-400-normal.woff2")
	voice_player = AudioStreamPlayer.new(); add_child(voice_player)
	voice_timer = Timer.new(); voice_timer.one_shot = true; add_child(voice_timer)
	voice_timer.timeout.connect(func(): voice_player.stop())
	load_save()
	load_world(world_id)

## Pixelify's "fi" ligature draws badly, so ligatures are turned off.
func _no_liga(path: String) -> Font:
	var v = FontVariation.new()
	v.base_font = load(path)
	v.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0, TextServerManager.get_primary_interface().name_to_tag("clig"): 0}
	return v

# ---------- world ----------
func load_world(id: String) -> void:
	world_id = id
	world = _read_json("res://data/worlds/%s.json" % id)
	var v = _read_json("res://assets/voices/%s.json" % id)
	voice_index = v.get("lines", {})

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f = FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func all_days() -> Array:
	var out = []
	for w in world.get("weeks", []):
		for d in w.days: out.append(d)
	return out

func week_of(day_id: String) -> Dictionary:
	for w in world.get("weeks", []):
		for d in w.days:
			if d.id == day_id: return w
	return {}

func person(id: String) -> Dictionary:
	if id == "you": return {"name": "You", "color": "#0CC0DF"}
	if id == "narrator": return {"name": "", "color": "#ffffff"}
	return world.get("cast", {}).get(id, {"name": id.capitalize(), "color": "#ffffff"})

func relic(id: String) -> Dictionary:
	for r in world.get("relics", []):
		if r.id == id: return r
	return {"id": id, "en": id, "pt": id}

# ---------- progress ----------
func ws() -> Dictionary:
	if not save.worlds.has(world_id): save.worlds[world_id] = {"done": {}, "relics": [], "paths": [], "rank": ""}
	return save.worlds[world_id]

func is_done(day_id: String) -> bool: return ws().done.has(day_id)

## A day is open when the day before it in its week is done; week 1 is always open, week 2 after week 1's last day,
## a road after week 2 when it was chosen, and the other roads once the first road is finished ("What if…?").
func day_open(day_id: String) -> bool:
	var weeks: Array = world.weeks
	for wi in weeks.size():
		var w = weeks[wi]
		for di in w.days.size():
			if w.days[di].id != day_id: continue
			if di > 0: return is_done(w.days[di - 1].id)
			if wi == 0: return true
			if wi == 1: return is_done(weeks[0].days[-1].id)
			var paths: Array = ws().paths
			if paths.is_empty(): return false
			if w.id == paths[0]: return true
			return _road_finished(paths[0])
	return false

func _road_finished(road: String) -> bool:
	for w in world.weeks:
		if w.id == road: return is_done(w.days[-1].id)
	return false

func next_day() -> String:
	for d in all_days():
		if day_open(d.id) and not is_done(d.id): return d.id
	return ""

func finish_day(day_id: String) -> void:
	ws().done[day_id] = Time.get_unix_time_from_system()
	write_save()

func add_relic(id: String, rank) -> void:
	if not id in ws().relics: ws().relics.append(id)
	if rank is Array and rank.size() > 0: ws().rank = rank[0]
	write_save()

func choose_path(p: String) -> void:
	if not p in ws().paths: ws().paths.append(p)
	write_save()

# ---------- save ----------
func load_save() -> void:
	save = {"worlds": {}, "settings": {"pt": true, "voice": true}}
	if FileAccess.file_exists(SAVE_PATH):
		var d = JSON.parse_string(FileAccess.open(SAVE_PATH, FileAccess.READ).get_as_text())
		if d is Dictionary: save.merge(d, true)

func write_save() -> void:
	if auto: return
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(save)); saved.emit()

func reset() -> void:
	save.worlds = {}; write_save()

func pt_on() -> bool: return save.settings.get("pt", true)

# ---------- voices ----------
static func voice_id(prefix: String, en: String) -> String:
	var s = en.replace("Dr. {name}", "Doctor").replace("{name}", "friend")
	var re = RegEx.create_from_string("\\{[a-z]+\\}"); s = re.sub(s, "it", true)
	s = s.to_lower()
	var re2 = RegEx.create_from_string("[^a-z0-9]+"); s = re2.sub(s, "-", true)
	return prefix + "." + s.trim_prefix("-").trim_suffix("-")

## Speaks a line if it was recorded. Returns its length in seconds (0 when there is no recording).
func speak(en: String) -> float:
	voice_player.stop()
	if auto or not save.settings.get("voice", true): return 0.0
	var hit = voice_index.get(voice_id(world.get("id", world_id), en))
	if hit == null: return 0.0
	var pack: String = hit[0]
	if not voice_streams.has(pack):
		var p = "res://assets/voices/%s/%s.mp3" % [world_id, pack]
		if not ResourceLoader.exists(p): return 0.0
		voice_streams[pack] = load(p)
	voice_player.stream = voice_streams[pack]
	voice_player.play(hit[1] / 1000.0)
	voice_timer.start(hit[2] / 1000.0)
	return hit[2] / 1000.0

func hush() -> void: voice_player.stop()

# ---------- look ----------
func panel(bg := PANEL, border := Color(1, 1, 1, 0.18), radius := 6) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border; s.set_border_width_all(2); s.set_corner_radius_all(radius)
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

func label(text: String, size := 18, color := Color.WHITE, bold := false, wrap := true) -> Label:
	var l = Label.new()
	l.text = text; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.add_theme_font_override("font", font_bold if bold else font_body)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func button(text: String, size := 17) -> Button:
	var b = Button.new()
	b.text = text; b.focus_mode = Control.FOCUS_ALL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_override("font", font_body)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", panel(Color(0.13, 0.15, 0.24, 0.95), Color(1, 1, 1, 0.22)))
	b.add_theme_stylebox_override("hover", panel(Color(0.2, 0.24, 0.38, 0.98), GOLD))
	b.add_theme_stylebox_override("focus", panel(Color(0.2, 0.24, 0.38, 0.98), GOLD))
	b.add_theme_stylebox_override("pressed", panel(Color(0.28, 0.32, 0.5, 1), GOLD))
	b.add_theme_stylebox_override("disabled", panel(Color(0.1, 0.1, 0.14, 0.8), Color(1, 1, 1, 0.08)))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	return b

## A bilingual pair [en, pt] → the English, plus the Portuguese underneath when subtitles are on.
func bi(pair) -> String:
	if pair is String: return pair
	if pair is Array and pair.size() > 1 and pt_on(): return "%s\n%s" % [pair[0], pair[1]]
	return pair[0] if pair is Array and pair.size() > 0 else ""

func en(pair) -> String:
	return pair if pair is String else (pair[0] if pair is Array and pair.size() > 0 else "")
