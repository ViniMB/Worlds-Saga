class_name Art
extends RefCounted
## Loads the pixel art rendered from the original game: animated backgrounds (8 frames side by side) and character
## sheets (32×32 cells: idle, blink, talk, talk-2, idle-2, flipped).

static var _cache = {}

static func tex(path: String) -> Texture2D:
	if _cache.has(path): return _cache[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = t
	return t

## Background sheet for a scene and an optional state ({"night": true} → ld-x__night-true).
static func bg_path(scene: String, state = null) -> String:
	var key = scene
	if state is Dictionary and state.size() > 0:
		var parts = []
		var keys = state.keys(); keys.sort()
		for k in keys: parts.append("%s-%s" % [k, str(state[k]).to_lower()])
		key += "__" + "_".join(parts)
	var p = "res://assets/bg/%s/%s.png" % [Game.world_id, key]
	if not ResourceLoader.exists(p): p = "res://assets/bg/%s/%s.png" % [Game.world_id, scene]
	return p

static func char_path(id: String) -> String:
	return "res://assets/chars/%s.png" % id

static func relic_path(id: String) -> String:
	return "res://assets/relics/%s.png" % id


## A TextureRect that plays an animated background sheet.
class Backdrop extends TextureRect:
	var sheet: Texture2D
	var atlas = AtlasTexture.new()
	var t = 0.0
	func _init() -> void:
		texture = atlas; stretch_mode = TextureRect.STRETCH_SCALE; texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func show_scene(scene: String, state = null) -> void:
		sheet = Art.tex(Art.bg_path(scene, state))
		atlas.atlas = sheet
		atlas.region = Rect2(0, 0, 144, 96)
	func _process(delta: float) -> void:
		if sheet == null: return
		t += delta
		var n = int(sheet.get_width() / 144)
		var f = int(t * 1000.0 / Game.FRAME_MS) % max(n, 1)
		atlas.region = Rect2(f * 144, 0, 144, 96)


## A character standing on stage: blinks, and moves its mouth while talking.
class Figure extends TextureRect:
	var id = ""
	var talking = false
	var flip = false
	var atlas = AtlasTexture.new()
	var t = randf() * 3.0
	func _init(who: String = "", px := 6) -> void:
		id = who
		atlas.atlas = Art.tex(Art.char_path(who))
		atlas.region = Rect2(0, 0, 32, 32)
		texture = atlas; stretch_mode = TextureRect.STRETCH_SCALE; texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size = Vector2(32 * px, 32 * px); size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		t += delta
		var cell = 0
		if talking: cell = 2 if int(t * 7.0) % 2 == 0 else 3
		elif fmod(t, 3.4) < 0.12: cell = 1
		elif fmod(t, 1.6) > 0.8: cell = 4
		flip_h = flip
		atlas.region = Rect2(cell * 32, 0, 32, 32)
