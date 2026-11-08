extends Control
## Screen manager: title → map (hub) → chapter → back to the map.

const Hub := preload("res://scripts/hub.gd")
const Chapter := preload("res://scripts/chapter.gd")

var current: Control

func _ready() -> void:
	if Game.auto:
		await _autotest()
		return
	if "--shots" in OS.get_cmdline_user_args():
		await _shots()
		return
	show_title()

func _swap(c: Control) -> void:
	if current: current.queue_free()
	current = c
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)

func show_title() -> void:
	var root = Control.new()
	_swap(root)
	var bg = Art.Backdrop.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(bg)
	bg.show_scene("ld-street")
	var shade = ColorRect.new(); shade.color = Color(0, 0, 0, 0.45); shade.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(shade)
	var cc = CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); root.add_child(cc)
	var card = PanelContainer.new(); card.add_theme_stylebox_override("panel", Game.panel(Color(0.05, 0.06, 0.1, 0.85), Game.GOLD, 10)); cc.add_child(card)
	var box = VBoxContainer.new(); box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10); box.custom_minimum_size = Vector2(420, 0)
	card.add_child(box)
	var t = Game.label("WORLDS SAGA", 44, Game.GOLD, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", Game.font_pixel); box.add_child(t)
	var w = Game.label(Game.world.title[0], 22, Color.WHITE, true); w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(w)
	var tg = Game.label(Game.bi(Game.world.tagline), 15, Color(1, 1, 1, 0.8)); tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(tg)
	box.add_child(Control.new())
	var started = not Game.ws().done.is_empty()
	var play = Game.button("Continue" if started else "New game", 20)
	play.pressed.connect(func(): show_hub() if started else show_intro())
	box.add_child(play)
	if started:
		var again = Game.button("Start again", 15)
		again.pressed.connect(func(): Game.reset(); show_intro())
		box.add_child(again)
	var pt = CheckButton.new(); pt.text = "Legendas em português"; pt.button_pressed = Game.pt_on()
	pt.add_theme_font_override("font", Game.font_body); pt.add_theme_font_size_override("font_size", 15)
	pt.toggled.connect(func(on): Game.save.settings.pt = on; Game.write_save())
	box.add_child(pt)
	var vo = CheckButton.new(); vo.text = "Voices"; vo.button_pressed = Game.save.settings.get("voice", true)
	vo.add_theme_font_override("font", Game.font_body); vo.add_theme_font_size_override("font_size", 15)
	vo.toggled.connect(func(on): Game.save.settings.voice = on; Game.write_save())
	box.add_child(vo)
	play.grab_focus()

## The world's intro, as a short cutscene, before the first visit to the map.
func show_intro() -> void:
	var ch = Chapter.new()
	ch.intro_only = true
	_swap(ch)
	ch.finished.connect(func(_ok): show_hub())
	ch.play_steps([{"kind": "cine", "scene": "ld-crack", "caps": Game.world.intro}])

func show_hub() -> void:
	var h = Hub.new()
	_swap(h)
	h.enter_day.connect(start_day)
	h.back.connect(show_title)

func start_day(day_id: String) -> void:
	var ch = Chapter.new()
	_swap(ch)
	ch.finished.connect(func(ok): show_hub())
	ch.play_day(day_id)

## --autotest: plays every day of the world with correct answers and reports any step that fails.
func _autotest() -> void:
	var played = 0
	var problems = []
	for i in 60:
		var d = Game.next_day()
		if d == "": break
		var ch = Chapter.new()
		_swap(ch)
		var res = await ch.play_day(d)
		if not Game.is_done(d): problems.append(d); break
		played += 1
		print("ok ", d)
	print("AUTOTEST played %d days, problems: %s" % [played, problems])
	get_tree().quit(0 if problems.is_empty() else 1)

## --shots: saves screenshots of the title, the map and a chapter to /tmp/ws-*.png (for checking the look).
func _shot(name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ws-%s.png" % name)

func _shots() -> void:
	show_title(); await _shot("title")
	show_hub(); await _shot("hub")
	var ch = Chapter.new(); _swap(ch); ch.play_day("ld-w1d1")
	await _shot("ch1")
	for k in 3:
		ch.advanced.emit(); await get_tree().process_frame
	await _shot("ch2")
	for k in 3:
		ch.advanced.emit(); await get_tree().process_frame
	await _shot("ch3")
	get_tree().quit()
