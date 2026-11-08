extends Control
## Plays one chapter (a "day" of the world data) as an RPG scene: cutscenes, dialogue with choices, exploring a place,
## mini-games, battles and rewards. Every step is a coroutine; the player advances with a click, Space or Enter.
## Wrong answers cost one courage heart; at zero, a friend helps and the hearts refill (nobody is ever stuck).

signal finished(ok: bool)
signal advanced
signal picked(i: int)

const BOX_Y := 318.0
var intro_only = false
var day: Dictionary = {}
var hearts = 3
var stage_cast: Array = []

var bg: Art.Backdrop
var stage: Control
var ui: Control
var top: HBoxContainer
var heart_row: HBoxContainer
var title_lbl: Label
var figures = {}
var box: PanelContainer
var name_lbl: Label
var text_lbl: Label
var sub_lbl: Label
var typing: Tween
var can_skip = false

func _ready() -> void:
	_build()

func _build() -> void:
	if bg: return
	clip_contents = true
	bg = Art.Backdrop.new(); bg.position = Vector2.ZERO; bg.size = Vector2(720, 480); add_child(bg)
	stage = Control.new(); stage.size = Vector2(720, 480); stage.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(stage)
	ui = Control.new(); ui.size = Vector2(720, 480); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	# top bar: chapter title and courage hearts
	top = HBoxContainer.new(); top.position = Vector2(10, 8); top.size = Vector2(700, 30); top.add_theme_constant_override("separation", 10)
	add_child(top)
	title_lbl = Game.label("", 15, Color.WHITE, true); title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8)); title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	top.add_child(title_lbl)
	heart_row = HBoxContainer.new(); top.add_child(heart_row)
	_draw_hearts()
	# dialogue box
	box = PanelContainer.new(); box.position = Vector2(12, BOX_Y); box.size = Vector2(696, 150)
	box.add_theme_stylebox_override("panel", Game.panel()); box.visible = false
	add_child(box)
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 4); box.add_child(v)
	name_lbl = Game.label("", 17, Game.GOLD, true); v.add_child(name_lbl)
	text_lbl = Game.label("", 19, Color.WHITE); text_lbl.custom_minimum_size = Vector2(660, 0); v.add_child(text_lbl)
	sub_lbl = Game.label("", 15, Color(0.75, 0.8, 0.95)); sub_lbl.custom_minimum_size = Vector2(660, 0); v.add_child(sub_lbl)

func _draw_hearts() -> void:
	for c in heart_row.get_children(): c.queue_free()
	for i in 3:
		var h = TextureRect.new(); h.texture = Art.tex("res://assets/emotes/heart.png"); h.custom_minimum_size = Vector2(26, 26)
		h.stretch_mode = TextureRect.STRETCH_SCALE; h.modulate = Color.WHITE if i < hearts else Color(0.2, 0.2, 0.25, 0.6)
		heart_row.add_child(h)

# ---------- entry points ----------
func play_day(id: String) -> bool:
	_build()
	for d in Game.all_days():
		if d.id == id: day = d
	if day.is_empty(): finished.emit(false); return false
	title_lbl.text = day.title[0]
	await play_steps(day.steps)
	Game.finish_day(id)
	finished.emit(true)
	return true

func play_steps(steps: Array) -> void:
	_build()
	if intro_only: top.visible = false
	for s in steps:
		await _step(s)
		_clear()
	if intro_only: finished.emit(true)

func _step(s: Dictionary) -> void:
	if s.has("scene"): bg.show_scene(s.scene, s.get("state"))
	match s.kind:
		"cine": await _cine(s)
		"talk": await _talk(s)
		"quiz": await _quiz(s.get("intro"), s.items)
		"learn": await _explore(s, s.targets, true)
		"inspect": await _explore(s, s.clues, false)
		"match": await _match(s)
		"memory": await _memory(s)
		"sort": await _sort(s)
		"order": await _order(s)
		"read": await _read(s)
		"maze": await _maze(s)
		"chart": await _chart(s)
		"surgery": await _battle(s)
		"spell": await _spell(s)
		"testimony": await _testimony(s)
		"reward": await _reward(s)
		_: push_warning("step kind not ported yet: " + str(s.kind))

func _clear() -> void:
	for c in ui.get_children(): c.queue_free()
	box.visible = false
	for f in figures.values(): f.talking = false

# ---------- basics: waiting, saying, choosing ----------
func _wait() -> void:
	if Game.auto:
		await get_tree().process_frame
		return
	await advanced

func _unhandled_input(e: InputEvent) -> void:
	var go = e.is_action_pressed("ui_advance") or e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if not go: return
	if typing and typing.is_running():
		typing.kill(); text_lbl.visible_ratio = 1.0
		return
	advanced.emit()

func _set_cast(cast: Array) -> void:
	for f in figures.values(): f.queue_free()
	figures = {}
	var ids = []
	for id in cast:
		if id != "narrator" and ResourceLoader.exists(Art.char_path(id)): ids.append(id)
	stage_cast = ids
	var n = ids.size()
	for i in n:
		var f = Art.Figure.new(ids[i], 6)
		var cx = 360.0 if n == 1 else lerp(150.0, 570.0, float(i) / float(n - 1))
		f.position = Vector2(cx - 96, BOX_Y - 170)
		f.flip = cx > 360.0
		stage.add_child(f); figures[ids[i]] = f

func _show_text(who: String, en: String, pt: String = "") -> void:
	box.visible = true
	var p = Game.person(who)
	name_lbl.text = p.get("name", "")
	name_lbl.add_theme_color_override("font_color", Color(p.get("color", "#f5c542")).lightened(0.25))
	text_lbl.text = en
	sub_lbl.text = pt if Game.pt_on() else ""
	for id in figures: figures[id].talking = id == who
	text_lbl.visible_ratio = 0.0
	if typing: typing.kill()
	typing = create_tween()
	typing.tween_property(text_lbl, "visible_ratio", 1.0, clamp(en.length() * 0.022, 0.2, 2.2))
	if Game.auto: typing.kill(); text_lbl.visible_ratio = 1.0

func _say(who: String, en: String, pt: String = "") -> void:
	_show_text(who, en, pt)
	Game.speak(en)
	await _wait()
	if figures.has(who): figures[who].talking = false

## Shows buttons and returns the index picked. In autotest it returns `correct` at once.
func _choose(options: Array, correct := 0, prompt = null) -> int:
	if Game.auto:
		await get_tree().process_frame
		return correct
	var was_box := box.visible
	box.visible = false
	var panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", Game.panel(Color(0.05, 0.06, 0.1, 0.94)))
	ui.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 60; panel.offset_right = -60; panel.offset_bottom = -12; panel.offset_top = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 8); panel.add_child(v)
	if prompt != null:
		var pl = Game.label(Game.bi(prompt), 16, Game.GOLD, true); pl.custom_minimum_size = Vector2(560, 0); v.add_child(pl)
	var buttons = []
	for i in options.size():
		var b = Game.button(str(options[i]), 17); b.custom_minimum_size = Vector2(560, 0)
		b.pressed.connect(func(): picked.emit(i))
		v.add_child(b); buttons.append(b)
	if buttons.size() > 0: buttons[0].grab_focus()
	var i: int = await picked
	panel.queue_free()
	box.visible = was_box and false
	return i

func _hurt(fb = null, who := "narrator") -> void:
	hearts -= 1
	_draw_hearts()
	_shake()
	if fb != null: await _say(who, Game.en(fb), fb[1] if fb is Array and fb.size() > 1 else "")
	if hearts <= 0:
		var friend: String = "pippa" if Game.world.cast.has("pippa") else "narrator"
		await _say(friend, "Don't worry. Mistakes help us learn. Let's try again, together.", "Não se preocupe. Erros nos ajudam a aprender. Vamos tentar de novo, juntos.")
		hearts = 3; _draw_hearts()

func _shake() -> void:
	var tw = create_tween()
	for i in 4: tw.tween_property(stage, "position:x", 8.0 if i % 2 == 0 else -8.0, 0.04)
	tw.tween_property(stage, "position:x", 0.0, 0.04)

func _banner(text, color := Game.GOLD) -> void:
	var l = Game.label(Game.bi(text), 20, color, true); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p = PanelContainer.new(); p.add_theme_stylebox_override("panel", Game.panel()); p.add_child(l)
	p.position = Vector2(110, 44); p.custom_minimum_size = Vector2(500, 0); ui.add_child(p)

func _shuffled(n: int) -> Array:
	var idx = range(n); idx.shuffle(); return idx

# ---------- cutscenes and dialogue ----------
func _cine(s: Dictionary) -> void:
	_set_cast(s.get("cast", []))
	for cap in s.caps:
		await _say("narrator", cap[0], cap[1])

func _talk(s: Dictionary) -> void:
	_set_cast(s.get("cast", []))
	for b in s.beats:
		if b.has("who"):
			await _say(b.who, b.en, b.get("pt", ""))
		elif b.has("branch"):
			var labels = []
			for o in b.opts: labels.append(o.en)
			var i = await _choose(labels, 0, b.branch)
			Game.choose_path(b.opts[i].path)
			await _say("you", b.opts[i].en, b.opts[i].get("pt", ""))
			if b.has("note"): await _say("narrator", Game.en(b.note), b.note[1])
		elif b.has("opts"):
			await _ask(b)

func _ask(b: Dictionary) -> void:
	var left: Array = b.opts.duplicate()
	while true:
		var order = _shuffled(left.size())
		var labels = []
		var correct = 0
		for k in order.size():
			labels.append(left[order[k]].en)
			if left[order[k]].get("ok", false): correct = k
		_show_text("you", "…", "")
		var i = await _choose(labels, correct, b.get("ask"))
		var o: Dictionary = left[order[i]]
		if o.get("ok", false) or left.size() <= 1:
			await _say("you", o.en, o.get("pt", ""))
			return
		await _hurt(o.get("fb", ["Not quite. Try another way.", "Não exatamente. Tente de outro jeito."]))
		left.erase(o)

func _quiz(intro, items: Array) -> void:
	if intro != null and not Game.auto: _banner(intro)
	for q in items:
		if q.has("say"): Game.speak(q.say)
		var left = range(q.opts.size())
		while true:
			var labels = []
			var correct = 0
			for k in left.size():
				labels.append(q.opts[left[k]])
				if left[k] == int(q.a): correct = k
			var i = await _choose(labels, correct, q.q)
			if left[i] == int(q.a):
				break
			await _hurt(q.get("fb", ["Not quite.", "Não exatamente."]))
			left.remove_at(i)

# ---------- exploring a place: learn words / inspect clues ----------
func _explore(s: Dictionary, spots: Array, speak_word: bool) -> void:
	_set_cast([])
	var need: int = min(int(s.get("need", spots.size())), spots.size())
	if s.has("intro"): await _say(s.get("who", "narrator"), Game.en(s.intro), s.intro[1])
	var found = {}
	var done = []
	if Game.auto:
		for k in need: found[spots[k].id] = true
		return
	box.visible = false
	var pins = {}
	for sp in spots:
		var r: float = sp.get("r", 8) * Game.SCALE
		var b = Button.new(); b.flat = true; b.focus_mode = Control.FOCUS_ALL
		b.position = Vector2(sp.x * Game.SCALE - r, sp.y * Game.SCALE - r); b.size = Vector2(r * 2, r * 2)
		var ring = Panel.new(); var st = StyleBoxFlat.new(); st.bg_color = Color(1, 1, 1, 0.08); st.border_color = Game.GOLD
		st.set_border_width_all(3); st.set_corner_radius_all(int(r)); ring.add_theme_stylebox_override("panel", st)
		ring.size = b.size; ring.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(ring)
		var tw = ring.create_tween().set_loops(); tw.tween_property(ring, "modulate:a", 0.35, 0.6); tw.tween_property(ring, "modulate:a", 1.0, 0.6)
		b.pressed.connect(func(): picked.emit(spots.find(sp)))
		ui.add_child(b); pins[sp.id] = b
	var counter = Game.label("0/%d" % need, 16, Game.GOLD, true); counter.position = Vector2(640, 44); ui.add_child(counter)
	while found.size() < need:
		var i: int = await picked
		var sp: Dictionary = spots[i]
		if speak_word:
			await _say(sp.get("who", "narrator"), "%s — %s" % [sp.en, sp.get("ex", "")], "%s — %s" % [sp.get("pt", ""), sp.get("ex_pt", "")])
		else:
			await _say(s.get("who", "you"), sp.en, sp.get("pt", ""))
		box.visible = false
		found[sp.id] = true
		pins[sp.id].modulate = Color(0.5, 1, 0.6, 0.6)
		counter.text = "%d/%d" % [found.size(), need]

# ---------- mini-games ----------
func _match(s: Dictionary) -> void:
	await _pairs(s.pairs, s.get("intro"), false)

func _memory(s: Dictionary) -> void:
	await _pairs(s.pairs, s.get("intro"), true)

## Pairs: pick one on the left, then its partner on the right. (Memory works the same way, face up: the challenge is
## the vocabulary, not remembering card positions.)
func _pairs(pairs: Array, intro, memory: bool) -> void:
	if Game.auto: return
	_banner(intro if intro != null else ["Match the pairs.", "Ligue os pares."])
	var grid = GridContainer.new(); grid.columns = 2; grid.position = Vector2(60, 120); grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8); ui.add_child(grid)
	var L = _shuffled(pairs.size()); var R = _shuffled(pairs.size())
	var lb = {}; var rb = {}
	for k in pairs.size():
		var a = Game.button(pairs[L[k]][0], 16); a.custom_minimum_size = Vector2(280, 0); grid.add_child(a); lb[L[k]] = a
		var b = Game.button(pairs[R[k]][1], 16); b.custom_minimum_size = Vector2(280, 0); grid.add_child(b); rb[R[k]] = b
		a.pressed.connect(func(): picked.emit(L[k]))
		b.pressed.connect(func(): picked.emit(100 + R[k]))
	var left = -1
	var solved = 0
	while solved < pairs.size():
		var i: int = await picked
		if i < 100:
			if left >= 0 and lb.has(left): lb[left].modulate = Color.WHITE
			left = i; lb[i].modulate = Game.GOLD
		elif left >= 0:
			var r = i - 100
			if r == left:
				lb[left].disabled = true; rb[r].disabled = true; lb[left].modulate = Game.GREEN; rb[r].modulate = Game.GREEN
				Game.speak(pairs[r][0]); solved += 1
			else:
				_shake(); hearts -= 0 if memory else 1; _draw_hearts()
				if hearts <= 0: hearts = 3; _draw_hearts()
				lb[left].modulate = Color.WHITE
			left = -1

func _sort(s: Dictionary) -> void:
	if s.has("intro") and not Game.auto: _banner(s.intro)
	var labels = []
	for b in s.bins: labels.append(b.en + ("  ·  " + b.pt if Game.pt_on() else ""))
	for it in s.items:
		var correct = 0
		for k in s.bins.size():
			if s.bins[k].id == it.bin: correct = k
		while true:
			_show_text(it.get("who", "narrator"), it.en, it.get("pt", ""))
			Game.speak(it.en)
			var i = await _choose(labels, correct)
			if i == correct:
				if it.has("why") and not Game.auto: await _say("narrator", "✓ " + it.why[0], it.why[1])
				break
			await _hurt(it.get("why"))

func _order(s: Dictionary) -> void:
	for task in s.tasks:
		var steps: Array = task.steps
		if Game.auto: continue
		_banner(task.title)
		var done = []
		var list = VBoxContainer.new(); list.position = Vector2(60, 110); list.add_theme_constant_override("separation", 6); ui.add_child(list)
		var out = VBoxContainer.new(); out.position = Vector2(60, 110); ui.add_child(out)
		var order = _shuffled(steps.size())
		var buttons = {}
		for k in order:
			var b = Game.button(steps[k][0], 16); b.custom_minimum_size = Vector2(600, 0)
			b.pressed.connect(func(): picked.emit(k)); list.add_child(b); buttons[k] = b
		while done.size() < steps.size():
			var i: int = await picked
			if i == done.size():
				done.append(i); buttons[i].disabled = true; buttons[i].text = "%d. %s" % [done.size(), steps[i][0]]
				buttons[i].modulate = Game.GREEN; list.move_child(buttons[i], done.size() - 1)
				Game.speak(steps[i][0])
			else:
				await _hurt(null)
		await get_tree().create_timer(0.6).timeout

func _read(s: Dictionary) -> void:
	_set_cast([])
	if not Game.auto:
		var p = PanelContainer.new(); p.add_theme_stylebox_override("panel", Game.panel(Game.PAPER, Color("#c9a86a"), 4))
		p.position = Vector2(60, 50); p.size = Vector2(600, 0); ui.add_child(p)
		var v = VBoxContainer.new(); v.add_theme_constant_override("separation", 8); p.add_child(v)
		v.add_child(Game.label(Game.en(s.title), 18, Game.INK, true))
		for para in s.paras:
			var l = Game.label(para[0], 16, Game.INK); l.custom_minimum_size = Vector2(560, 0); v.add_child(l)
			if Game.pt_on():
				var t = Game.label(para[1], 13, Color("#6a5a3a")); t.custom_minimum_size = Vector2(560, 0); v.add_child(t)
		var more = Game.label("▶ Space / tap", 13, Color("#8a6a3a")); v.add_child(more)
		for para in s.paras:
			Game.speak(para[0]); await _wait()
		p.queue_free()
	await _quiz(null, s.get("items", []))

func _maze(s: Dictionary) -> void:
	var map: Array = s.map
	var cell = 44.0
	var origin = Vector2(360 - map[0].length() * cell / 2.0, 60)
	var pos = Vector2.ZERO
	for y in map.size():
		for x in map[y].length():
			var ch: String = map[y][x]
			if ch == "S": pos = Vector2(x, y)
			if Game.auto: continue
			var r = ColorRect.new(); r.position = origin + Vector2(x, y) * cell; r.size = Vector2(cell - 2, cell - 2)
			r.color = Color("#2a2f45") if ch == "#" else (Game.GREEN if ch == "D" else Color("#c9c3b0"))
			ui.add_child(r)
	var you: Art.Figure = null
	if not Game.auto:
		you = Art.Figure.new("you", 1); you.size = Vector2(cell, cell); you.custom_minimum_size = you.size
		you.position = origin + pos * cell; ui.add_child(you)
	var facing = Vector2.RIGHT
	var turns = ["straight", "left", "right"]
	var names = ["Go straight", "Turn left", "Turn right"]
	for m in s.moves:
		while true:
			_show_text(s.get("who", "narrator"), m.en, m.pt); Game.speak(m.en)
			var i = await _choose(names, turns.find(m.turn))
			if turns[i] == m.turn: break
			await _hurt(["That's not what %s said. Listen again." % Game.person(s.get("who", "narrator")).get("name", "they"), "Não foi isso que disseram. Escute de novo."])
		if m.turn == "left": facing = Vector2(facing.y, -facing.x)
		elif m.turn == "right": facing = Vector2(-facing.y, facing.x)
		for k in int(m.n):
			pos += facing
			if you:
				var tw = create_tween(); tw.tween_property(you, "position", origin + pos * cell, 0.18); await tw.finished

func _chart(s: Dictionary) -> void:
	_set_cast([s.who])
	for line in s.said: await _say(s.who, line[0], line[1])
	for f in s.fields:
		while true:
			var i = await _choose(f.opts, int(f.a), f.label)
			if i == int(f.a): break
			await _hurt(["Listen again: " + s.said[min(s.fields.find(f), s.said.size() - 1)][0], "Escute de novo."])

func _spell(s: Dictionary) -> void:
	var spells: Array = s.spells
	if s.has("intro"): await _say("narrator", Game.en(s.intro), s.intro[1])
	for k in spells.size():
		while true:
			var order = _shuffled(spells.size())
			var labels = []
			var correct = 0
			for j in order.size():
				labels.append("ᚱ%s  %s" % [spells[order[j]].rune, spells[order[j]].en])
				if order[j] == k: correct = j
			var i = await _choose(labels, correct, ["Rune %d of %d" % [k + 1, spells.size()], "Runa %d de %d" % [k + 1, spells.size()]])
			if order[i] == k:
				await _say("you", spells[k].en, spells[k].pt)
				break
			await _hurt(["The runes glow in order. Look at the number.", "As runas brilham em ordem. Olhe o número."])

# ---------- battle (timed moments) ----------
func _battle(s: Dictionary) -> void:
	_set_cast(s.get("cast", []))
	var foe: String = s.cast[1] if s.cast.size() > 1 else ""
	var hp: int = s.moments.size()
	var bar = ProgressBar.new(); bar.max_value = hp; bar.value = hp; bar.show_percentage = false
	bar.position = Vector2(420, 50); bar.size = Vector2(260, 16)
	var fill = StyleBoxFlat.new(); fill.bg_color = Game.RED; bar.add_theme_stylebox_override("fill", fill)
	if not Game.auto:
		ui.add_child(bar)
		_banner(s.title, Game.RED)
		await _say("narrator", Game.en(s.intro), s.intro[1])
	var k = 0
	while k < s.moments.size():
		var m: Dictionary = s.moments[k]
		var labels = []
		var order = _shuffled(m.opts.size())
		var correct = 0
		for j in order.size():
			labels.append(m.opts[order[j]][0])
			if order[j] == int(m.a): correct = j
		_show_text(foe if foe != "" else "narrator", m.cue[0], m.cue[1])
		var timer = get_tree().create_timer(float(m.get("secs", 8)) + 4.0)
		var timed_out = [false]
		timer.timeout.connect(func(): if not Game.auto: timed_out[0] = true; picked.emit(-1))
		var i = await _choose(labels, correct)
		if i >= 0 and order[i] == int(m.a) and not timed_out[0]:
			Game.speak(m.opts[int(m.a)][0])
			if figures.has(foe): _hit(figures[foe])
			bar.value -= 1; k += 1
		else:
			await _hurt(["Too slow — or the wrong move! Again!", "Lento demais — ou o movimento errado! De novo!"] if i < 0 else ["Wrong move! It fights back.", "Movimento errado! Ele contra-ataca."])

func _hit(f: Control) -> void:
	var tw = create_tween()
	tw.tween_property(f, "modulate", Color(3, 3, 3), 0.06); tw.tween_property(f, "modulate", Color.WHITE, 0.12)
	tw.tween_property(f, "position:x", f.position.x + 14, 0.05); tw.tween_property(f, "position:x", f.position.x, 0.08)

# ---------- testimony ----------
func _testimony(s: Dictionary) -> void:
	_set_cast([s.who])
	var lies = 0
	for st in s.statements: if st.has("lie"): lies += 1
	if not Game.auto:
		_banner(s.title, Game.RED)
		await _say("narrator", Game.en(s.intro), s.intro[1])
	var found = {}
	var ev_labels = []
	for e in s.evidence: ev_labels.append(e.en)
	var idx = 0
	while found.size() < lies:
		var st: Dictionary = s.statements[idx]
		_show_text(s.who, st.en, st.pt); Game.speak(st.en)
		var correct = 1 if st.has("lie") and not found.has(idx) else 2
		var a = await _choose(["Press: ask more", "Present evidence", "Next statement"], correct)
		if a == 0:
			var pr = st.get("press", ["…", "…"])
			await _say(s.who, pr[0], pr[1])
		elif a == 1:
			var ec = 0
			if st.has("lie"):
				for e in s.evidence.size(): if s.evidence[e].id == st.lie.evidence: ec = e
			var e = await _choose(ev_labels, ec, ["Which evidence?", "Qual prova?"])
			if st.has("lie") and s.evidence[e].id == st.lie.evidence:
				_banner(["OBJECTION!", "PROTESTO!"], Game.RED); _shake()
				await _say("you", st.lie.fb[0], st.lie.fb[1])
				if st.lie.has("after"): await _say(s.who, st.lie.after[0], st.lie.after[1])
				found[idx] = true
				for c in ui.get_children(): if c is PanelContainer: c.queue_free()
			else:
				await _hurt(["That evidence doesn't prove this one is a lie.", "Essa prova não mostra que isso é mentira."])
		else:
			idx = (idx + 1) % s.statements.size()
		if a != 2 and found.has(idx): idx = (idx + 1) % s.statements.size()

# ---------- reward ----------
func _reward(s: Dictionary) -> void:
	_set_cast([s.who])
	var r = Game.relic(s.relic)
	if not Game.auto:
		var p = PanelContainer.new(); p.add_theme_stylebox_override("panel", Game.panel(Color(0.1, 0.08, 0.02, 0.95), Game.GOLD))
		p.position = Vector2(190, 50); p.custom_minimum_size = Vector2(340, 0); ui.add_child(p)
		var v = VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; p.add_child(v)
		var t = Game.label(Game.bi(s.title), 18, Game.GOLD, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
		var ic = TextureRect.new(); ic.texture = Art.tex(Art.relic_path(s.relic)); ic.custom_minimum_size = Vector2(96, 96)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; v.add_child(ic)
		var n = Game.label(r.get("en", "") + ("\n" + r.get("pt", "") if Game.pt_on() else ""), 15); n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(n)
		var tw = ic.create_tween().set_loops(); tw.tween_property(ic, "rotation", 0.08, 0.5); tw.tween_property(ic, "rotation", -0.08, 0.5)
	await _say(s.who, s.line[0], s.line[1])
	Game.add_relic(s.relic, s.get("rank"))
	if s.has("rank") and not Game.auto:
		await _say("narrator", "New rank: " + s.rank[0] + "!", "Nova patente: " + s.rank[1] + "!")
