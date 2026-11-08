extends Control
## The world map: a side-scrolling street made of the world's places, side by side. Walk with ←/→ (or tap the
## ground); every chapter is a glowing marker; walk to it and press Space/E (or tap it) to play.

signal enter_day(day_id: String)
signal back

const SPEED := 260.0
const GROUND := 440.0

var places: Array = []        # scene ids, in order of first appearance
var markers: Array = []       # {day, x, node}
var world_w = 0.0
var cam_x = 0.0
var you: Art.Figure
var you_x = 120.0
var target_x = -1.0
var layer: Control
var hint: Label
var near: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	layer = Control.new(); add_child(layer)
	_build_places()
	_build_markers()
	you = Art.Figure.new("you", 4)
	layer.add_child(you)
	var last = Game.ws().get("hub_x", -1.0)
	you_x = last if last > 0 else (markers[0].x - 80 if markers.size() > 0 else 120.0)
	_hud()

func _scene_of(day: Dictionary) -> String:
	for s in day.steps:
		if s.has("scene"): return s.scene
	return ""

func _build_places() -> void:
	var last = "ld-street"
	for d in Game.all_days():
		var s = _scene_of(d)
		if s == "" or s.begins_with("ld-crack") or s == "ld-boxin": s = last
		last = s
		if not s in places: places.append(s)
	var x = 0.0
	for s in places:
		var bg = Art.Backdrop.new()
		bg.show_scene(s)
		bg.position = Vector2(x, 0); bg.size = Vector2(144 * Game.SCALE, 96 * Game.SCALE)
		layer.add_child(bg)
		var name = Game.label(s.trim_prefix("ld-").capitalize(), 13, Color(1, 1, 1, 0.7), false, false)
		name.position = Vector2(x + 12, 8); name.add_theme_font_override("font", Game.font_pixel)
		layer.add_child(name)
		x += 144 * Game.SCALE
	world_w = x

func _build_markers() -> void:
	var per = {}
	var last = "ld-street"
	for d in Game.all_days():
		var s = _scene_of(d)
		if s == "" or s.begins_with("ld-crack") or s == "ld-boxin": s = last
		last = s
		if not (Game.day_open(d.id) or Game.is_done(d.id)): continue
		per[s] = per.get(s, 0) + 1
		var slot: int = per[s]
		var px = places.find(s) * 144 * Game.SCALE + 80 + (slot - 1) * 150 % 600
		var m = _marker(d, Game.is_done(d.id))
		m.position = Vector2(px - 28, GROUND - 150)
		layer.add_child(m)
		markers.append({"day": d.id, "x": px, "node": m, "title": d.title})

func _marker(d: Dictionary, done: bool) -> Control:
	var c = Control.new(); c.size = Vector2(56, 90)
	var em = TextureRect.new()
	em.texture = Art.tex("res://assets/emotes/%s.png" % ("star" if done else "exclamation"))
	em.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; em.stretch_mode = TextureRect.STRETCH_SCALE
	em.size = Vector2(48, 48); em.position = Vector2(4, 0)
	c.add_child(em)
	var tw = c.create_tween().set_loops()
	tw.tween_property(em, "position:y", -8.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(em, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	var b = Button.new(); b.flat = true; b.size = c.size; b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): target_x = c.position.x + 28)
	c.add_child(b)
	c.modulate = Color(0.75, 0.75, 0.75) if done else Color.WHITE
	return c

func _hud() -> void:
	var top = PanelContainer.new(); top.add_theme_stylebox_override("panel", Game.panel())
	top.position = Vector2(8, 8); add_child(top)
	var row = HBoxContainer.new(); row.add_theme_constant_override("separation", 10); top.add_child(row)
	var menu = Game.button("Menu", 14); menu.pressed.connect(func(): back.emit()); row.add_child(menu)
	var ws = Game.ws()
	row.add_child(Game.label("%s · %d/%d" % [Game.world.title[0], ws.done.size(), Game.all_days().size()], 15, Color.WHITE, true, false))
	if ws.rank != "": row.add_child(Game.label("· " + ws.rank, 15, Game.GOLD, false, false))
	for r in ws.relics:
		var ic = TextureRect.new(); ic.texture = Art.tex(Art.relic_path(r)); ic.custom_minimum_size = Vector2(24, 24)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.tooltip_text = Game.relic(r).en
		row.add_child(ic)
	hint = Game.label("", 16, Color.WHITE)
	var hp = PanelContainer.new(); hp.add_theme_stylebox_override("panel", Game.panel()); hp.add_child(hint)
	hp.position = Vector2(170, 410); hp.custom_minimum_size = Vector2(380, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hp)
	if markers.is_empty():
		hint.text = "London Fog: complete!  ★"

func _process(delta: float) -> void:
	var dir = Input.get_axis("ui_left", "ui_right")
	if dir != 0.0: target_x = -1.0
	elif target_x >= 0.0:
		dir = sign(target_x - you_x)
		if abs(target_x - you_x) < 6.0: dir = 0.0; target_x = -1.0
	you_x = clamp(you_x + dir * SPEED * delta, 40.0, world_w - 40.0)
	if dir != 0.0: you.flip = dir < 0
	var bob = sin(Time.get_ticks_msec() / 90.0) * 3.0 if dir != 0.0 else 0.0
	you.position = Vector2(you_x - 64, GROUND - 128 + bob)
	cam_x = lerp(cam_x, clamp(you_x - 360.0, 0.0, max(world_w - 720.0, 0.0)), 1.0 - exp(-8.0 * delta))
	layer.position.x = -round(cam_x)
	near = {}
	for m in markers:
		if abs(m.x - you_x) < 50: near = m
	if hint and not markers.is_empty():
		if near.is_empty(): hint.text = "← →  walk to a  !  to play"
		else: hint.text = "%s  —  Space / tap" % near.title[0]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") or e.is_action_pressed("ui_advance") or (e is InputEventKey and e.pressed and e.keycode == KEY_E):
		if not near.is_empty(): _go(near.day)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var wx: float = e.position.x + cam_x
		if not near.is_empty() and abs(wx - near.x) < 60: _go(near.day)
		else: target_x = wx

func _go(day: String) -> void:
	Game.ws().hub_x = you_x
	enter_day.emit(day)
