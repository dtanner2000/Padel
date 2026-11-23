class_name Hud
extends CanvasLayer
## Landscape touch HUD: scoreboard, pause, rally count, joystick,
## HIT (hold to ready, swipe to aim, timing arc), LOB and SMASH,
## plus the start menu and pause menu. Respects the iOS safe area.

signal shot_requested(kind: String, aim: Vector2)
signal hit_pressed
signal mode_chosen(mode: String, golden_point: bool)
signal quit_to_menu
signal online_quick
signal online_create(length: String, golden_point: bool)
signal online_join(code: String)
signal online_closed
signal play_ai_instead

const LIME := Color("c6f432")
const INK := Color("0b1220")
const PANEL := Color(0.035, 0.06, 0.11, 0.82)
const MUTED := Color("a9b4c6")

## Menu entries: id, title, detail.
const MODES := [
	["quick", "Quick match", "One set, first to 4 games · about 5 minutes"],
	["set", "One set", "First to 6 games, tie-break at 6-6"],
	["match", "Full match", "Best of three sets"],
	["practice", "Practice", "Ball machine: groundstrokes, back glass, overheads"],
	["online", "Play online", "Quick match, or a private game with a friend"],
]
const PRIVATE_LENGTHS := [["quick", "Quick"], ["set", "One set"], ["match", "Full"]]

var safe: Control
var controls: Control          # everything you touch during play
var joystick: TouchJoystick
var hit_btn: TouchButton
var lob_btn: TouchButton
var smash_btn: TouchButton
var pause_btn: Button

var _score_panel: PanelContainer
var _mode_label: Label
var _sets: Array[Label] = []
var _games: Array[Label] = []
var _points: Array[Label] = []
var _rally_panel: PanelContainer
var _rally_label: Label
var _message: Label
var _callout: Label
var _flash: Label
var _msg_t := 0.0
var _callout_t := 0.0
var _flash_t := 0.0

var _menu: Control
var _golden: CheckButton
var _pause_menu: Control
var _quit_btn: Button
var _names: Array[Label] = []

var _online: Control
var _online_status: Label
var _code_label: Label
var _code_edit: LineEdit
var _ai_btn: Button
var net_mode := false:        # online match: pausing can't stop the game for the other phone
	set(v):
		net_mode = v
		if _quit_btn:
			_quit_btn.text = "Leave match" if v else "Quit to menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	safe = Control.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)

	_build_scoreboard()
	_build_rally()

	_message = _label("", 30, Color.WHITE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 10)
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	safe.add_child(_message)
	_callout = _pill_label("", 15, INK, Color.WHITE)
	safe.add_child(_callout)
	_flash = _label("", 24, LIME)
	_flash.add_theme_constant_override("outline_size", 8)
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	safe.add_child(_flash)

	controls = Control.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(controls)
	_build_pause_button()

	joystick = TouchJoystick.new()
	controls.add_child(joystick)

	hit_btn = TouchButton.new()
	hit_btn.radius = 50
	hit_btn.label = "HIT"
	hit_btn.sublabel = "HOLD + SWIPE"
	hit_btn.font_size = 28
	hit_btn.fill = LIME
	hit_btn.text_color = INK
	hit_btn.outline = Color(0, 0, 0, 0)
	hit_btn.readiness = 0.0
	hit_btn.pressed_down.connect(func() -> void: hit_pressed.emit())
	hit_btn.released.connect(func(aim: Vector2) -> void: shot_requested.emit("drive", aim))
	controls.add_child(hit_btn)

	lob_btn = TouchButton.new()
	lob_btn.radius = 32
	lob_btn.label = "LOB"
	lob_btn.font_size = 17
	lob_btn.fire_on_press = true
	lob_btn.released.connect(func(aim: Vector2) -> void: shot_requested.emit("lob", aim))
	controls.add_child(lob_btn)

	smash_btn = TouchButton.new()
	smash_btn.radius = 32
	smash_btn.label = "SMASH"
	smash_btn.font_size = 15
	smash_btn.enabled = false
	smash_btn.fire_on_press = true
	smash_btn.released.connect(func(aim: Vector2) -> void: shot_requested.emit("smash", aim))
	controls.add_child(smash_btn)

	_build_menu()
	_build_online()
	_build_pause_menu()

	get_viewport().size_changed.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_msg_t -= delta
	_callout_t -= delta
	_flash_t -= delta
	_message.visible = _msg_t > 0.0
	_callout.visible = _callout_t > 0.0
	_flash.visible = _flash_t > 0.0


# --- public -------------------------------------------------------------------

func show_menu(on: bool) -> void:
	_menu.visible = on
	_online.visible = false
	controls.visible = not on
	_score_panel.visible = not on
	_rally_panel.visible = not on
	if on:
		_msg_t = 0.0
		_callout_t = 0.0


func set_team_names(team0: String, team1: String) -> void:
	_names[0].text = team0
	_names[1].text = team1
	_layout()


func show_online(on: bool) -> void:
	_online.visible = on
	if on:
		_menu.visible = false
		_code_label.visible = false
		_ai_btn.visible = false
		_online_status.text = "Play someone anywhere: a random opponent, or a friend with a code."


func set_online_status(text: String) -> void:
	_online_status.text = text


func show_room_code(code: String) -> void:
	_code_label.text = code
	_code_label.visible = true
	_online_status.text = "Send your friend this code. The match starts when they join."


func show_ai_fallback(on: bool) -> void:
	if _ai_btn.visible != on:
		_ai_btn.visible = on


func set_practice(on: bool) -> void:
	_score_panel.visible = not on and not _menu.visible


func update_score(s: MatchScore, serving_team: int) -> void:
	for t in 2:
		_sets[t].text = str(s.sets[t])
		_games[t].text = str(s.games[t])
		_points[t].text = s.point_text(t)
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(5)
		box.content_margin_left = 4
		box.content_margin_right = 4
		box.bg_color = LIME if t == serving_team else Color(0, 0, 0, 0)
		_points[t].add_theme_stylebox_override("normal", box)
		_points[t].add_theme_color_override("font_color", INK if t == serving_team else Color.WHITE)
	if s.tiebreak:
		_mode_label.text = "TIE-BREAK"
	elif s.is_golden_point():
		_mode_label.text = "GOLDEN POINT"
	elif s.sets_to_win == 1:
		_mode_label.text = "FIRST TO %d" % s.games_per_set
	else:
		_mode_label.text = "SET %d" % (s.sets[0] + s.sets[1] + 1)


func set_rally(n: int) -> void:
	set_rally_text("RALLY  %d" % n)


func set_rally_text(text: String) -> void:
	_rally_label.text = text
	if is_instance_valid(safe):
		_rally_panel.reset_size()
		_rally_panel.position = Vector2(safe.size.x - _rally_panel.size.x, 0)


func show_message(text: String, seconds := 1.6) -> void:
	_message.text = text
	_msg_t = seconds
	_layout_message()


func callout(text: String, seconds := 1.0) -> void:
	_callout.text = text
	_callout_t = seconds
	_layout_message()


func flash(text: String, seconds := 0.8) -> void:
	_flash.text = text
	_flash_t = seconds
	_layout_message()


# --- build --------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _pill_label(text: String, size: int, color: Color, bg: Color) -> Label:
	var l := _label(text, size, color)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	l.add_theme_stylebox_override("normal", sb)
	return l


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _button(text: String, size: int, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.12) if st == "pressed" else bg
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	return b


func _build_scoreboard() -> void:
	_score_panel = _panel()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	_score_panel.add_child(grid)
	_mode_label = _label("SET 1", 11, MUTED)
	grid.add_child(_mode_label)
	for h in ["SET", "GAME", "PT"]:
		var l := _label(h, 11, MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(l)
	for t in 2:
		var n := _label("YOU · ANA" if t == 0 else "RIVALS", 17, Color("ffd2a6") if t == 0 else Color.WHITE)
		_names.append(n)
		grid.add_child(n)
		for col in 3:
			var v := _label("0", 18, Color.WHITE)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.custom_minimum_size = Vector2(36 if col == 2 else 26, 0)
			grid.add_child(v)
			match col:
				0: _sets.append(v)
				1: _games.append(v)
				2: _points.append(v)
	safe.add_child(_score_panel)


func _build_rally() -> void:
	_rally_panel = _panel()
	_rally_label = _label("RALLY  0", 16, Color.WHITE)
	_rally_panel.add_child(_rally_label)
	safe.add_child(_rally_panel)


func _build_pause_button() -> void:
	pause_btn = _button("II", 18, PANEL, Color.WHITE)
	pause_btn.custom_minimum_size = Vector2(46, 46)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := pause_btn.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		sb.set_corner_radius_all(23)
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		pause_btn.add_theme_stylebox_override(st, sb)
	pause_btn.pressed.connect(func() -> void: _set_paused(true))
	controls.add_child(pause_btn)


func _build_menu() -> void:
	_menu = ColorRect.new()
	(_menu as ColorRect).color = Color(0.03, 0.06, 0.1, 0.72)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(centre)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	centre.add_child(col)
	var title := _label("PADEL", 54, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _label("Doubles · glass walls · golden point", 15, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for m in MODES:
		var b := _button("%s\n%s" % [m[1], m[2]], 15, Color(1, 1, 1, 0.94) if m[0] != "quick" else LIME, INK)
		b.custom_minimum_size = Vector2(330, 64)
		var id: String = m[0]
		if id == "online":
			b.pressed.connect(func() -> void: show_online(true))
		else:
			b.pressed.connect(func() -> void: mode_chosen.emit(id, _golden.button_pressed))
		grid.add_child(b)
	_golden = CheckButton.new()
	_golden.text = "Golden point at deuce"
	_golden.button_pressed = true
	_golden.focus_mode = Control.FOCUS_NONE
	_golden.add_theme_font_size_override("font_size", 15)
	_golden.add_theme_color_override("font_color", Color.WHITE)
	_golden.add_theme_color_override("font_pressed_color", Color.WHITE)
	_golden.add_theme_color_override("font_hover_color", Color.WHITE)
	_golden.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_golden)


func _build_pause_menu() -> void:
	_pause_menu = ColorRect.new()
	(_pause_menu as ColorRect).color = Color(0.03, 0.06, 0.1, 0.7)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.visible = false
	add_child(_pause_menu)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(centre)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	centre.add_child(col)
	var t := _label("Paused", 34, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var resume := _button("Resume", 20, LIME, INK)
	resume.custom_minimum_size = Vector2(260, 54)
	resume.pressed.connect(func() -> void: _set_paused(false))
	col.add_child(resume)
	_quit_btn = _button("Quit to menu", 20, Color(1, 1, 1, 0.94), INK)
	_quit_btn.custom_minimum_size = Vector2(260, 54)
	_quit_btn.pressed.connect(func() -> void:
		_set_paused(false)
		quit_to_menu.emit())
	col.add_child(_quit_btn)


func _build_online() -> void:
	_online = ColorRect.new()
	(_online as ColorRect).color = Color(0.03, 0.06, 0.1, 0.86)
	_online.mouse_filter = Control.MOUSE_FILTER_STOP
	_online.visible = false
	add_child(_online)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_online.add_child(centre)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	centre.add_child(col)
	var title := _label("Play online", 32, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_online_status = _label("", 15, MUTED)
	_online_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_status.custom_minimum_size = Vector2(620, 0)
	col.add_child(_online_status)

	_code_label = _label("", 44, LIME)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.visible = false
	col.add_child(_code_label)

	var quick := _button("Quick match  ·  random opponent, first to 4 games", 17, LIME, INK)
	quick.custom_minimum_size = Vector2(520, 50)
	quick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quick.pressed.connect(func() -> void:
		_code_label.visible = false
		online_quick.emit())
	col.add_child(quick)

	_ai_btn = _button("No one around yet. Play the AI instead", 15, Color(1, 1, 1, 0.94), INK)
	_ai_btn.custom_minimum_size = Vector2(420, 40)
	_ai_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ai_btn.visible = false
	_ai_btn.pressed.connect(func() -> void:
		_online.visible = false
		play_ai_instead.emit())
	col.add_child(_ai_btn)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	host_row.alignment = BoxContainer.ALIGNMENT_CENTER
	host_row.add_child(_label("Private game:", 16, Color.WHITE))
	for h in PRIVATE_LENGTHS:
		var b := _button(h[1], 16, Color(1, 1, 1, 0.94), INK)
		b.custom_minimum_size = Vector2(110, 44)
		var id: String = h[0]
		b.pressed.connect(func() -> void: online_create.emit(id, _golden.button_pressed))
		host_row.add_child(b)
	col.add_child(host_row)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_child(_label("Friend's code:", 16, Color.WHITE))
	_code_edit = LineEdit.new()
	_code_edit.custom_minimum_size = Vector2(130, 44)
	_code_edit.max_length = 4
	_code_edit.placeholder_text = "K7QF"
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_size_override("font_size", 20)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			var caret := _code_edit.caret_column
			_code_edit.text = up
			_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(t: String) -> void: online_join.emit(t))
	join_row.add_child(_code_edit)
	var join := _button("Join", 16, LIME, INK)
	join.custom_minimum_size = Vector2(90, 44)
	join.pressed.connect(func() -> void: online_join.emit(_code_edit.text))
	join_row.add_child(join)
	col.add_child(join_row)

	var back := _button("Back", 16, Color(1, 1, 1, 0.2), Color.WHITE)
	back.custom_minimum_size = Vector2(140, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		show_online(false)
		_menu.visible = true
		online_closed.emit())
	col.add_child(back)


func _set_paused(on: bool) -> void:
	get_tree().paused = on and not net_mode
	_pause_menu.visible = on
	controls.visible = not on and not _menu.visible


# --- layout -------------------------------------------------------------------

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_menu.position = Vector2.ZERO
	_menu.size = vp
	_pause_menu.position = Vector2.ZERO
	_pause_menu.size = vp
	_online.position = Vector2.ZERO
	_online.size = vp
	var rect := Rect2(Vector2.ZERO, vp)
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var win := Vector2(DisplayServer.window_get_size())
		if win.x > 0 and sa.size.x > 0:
			var sc := vp / win
			rect = Rect2(Vector2(sa.position) * sc, Vector2(sa.size) * sc)
	rect = rect.grow(-12.0)
	safe.position = rect.position
	safe.size = rect.size
	controls.position = Vector2.ZERO
	controls.size = rect.size
	var w := rect.size.x
	var h := rect.size.y

	pause_btn.position = Vector2(0, 0)
	_score_panel.reset_size()
	_score_panel.position = Vector2((w - _score_panel.size.x) * 0.5, 0)
	_rally_panel.reset_size()
	_rally_panel.position = Vector2(w - _rally_panel.size.x, 0)

	joystick.position = Vector2(0, h * 0.4)
	joystick.size = Vector2(w * 0.42, h * 0.6)
	joystick.rest_centre = Vector2(80, joystick.size.y - 80)

	_place(hit_btn, Vector2(w - 70, h - 70), 72)
	_place(lob_btn, Vector2(w - 185, h - 38), 48)
	_place(smash_btn, Vector2(w - 60, h - 195), 48)
	_layout_message()


func _place(b: TouchButton, centre: Vector2, half: float) -> void:
	b.size = Vector2(half, half) * 2.0
	b.position = centre - Vector2(half, half)
	b.queue_redraw()


func _layout_message() -> void:
	if not is_instance_valid(safe):
		return
	var w := safe.size.x
	var h := safe.size.y
	_message.reset_size()
	_message.position = Vector2((w - _message.size.x) * 0.5, h * 0.36 - _message.size.y * 0.5)
	_callout.reset_size()
	_callout.position = Vector2((w - _callout.size.x) * 0.5, h - _callout.size.y - 4)
	_flash.reset_size()
	_flash.position = Vector2((w - _flash.size.x) * 0.5, h * 0.2)
