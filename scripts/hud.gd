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
signal online_create(length: String, golden_point: bool, size: int)
signal online_start_now
signal online_join(code: String)
signal online_closed
signal play_ai_instead
signal training_chosen(drill: String)
signal career_chosen(venue: String)
signal daily_chosen
signal team_changed
signal settings_changed
signal locker_changed

const LIME := Color("c6f432")
const INK := Color("0b1220")
const PANEL := Color(0.035, 0.06, 0.11, 0.82)
const MUTED := Color("a9b4c6")

## Menu entries: id, title, detail. The first two are highlighted.
const MODES := [
	["career", "Career", "Win tournaments, unlock new courts"],
	["quick", "Quick match", "One set, first to 4 games · about 5 minutes"],
	["training", "Training", "Learn every shot: drills with a ball machine"],
	["daily", "Daily challenge", "Hit the moving goal on the back glass"],
	["online", "Play online", "Quick match, or a private game with a friend"],
	["longer", "Longer match", "One set, or best of three"],
]

## Training drills: id, name. Details (tips, goals) live in main.gd.
const TRAINING := [
	["ground", "Groundstrokes"], ["aim", "Aiming"], ["slice", "Slice"],
	["glass", "Off the back glass"], ["volley", "Volleys at the net"], ["smash", "Power smash"],
	["vibora", "Víbora"], ["chiquita", "Chiquita"], ["contrapared", "Contrapared"],
	["mix", "Free practice"],
]


## A quick sideways flick on HIT is a slice; anything with real up/down is an aimed drive.
## A firm swipe straight down is a chiquita (main.gd falls back to a drive if
## you haven't unlocked it).
static func swipe_kind(aim: Vector2) -> String:
	if absf(aim.x) >= 0.4 and absf(aim.x) > 1.8 * absf(aim.y):
		return "slice"
	if aim.y <= -0.55 and absf(aim.y) > 1.5 * absf(aim.x):
		return "chiquita"
	return "drive"
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
var _wind_label: Label
var _rally_label: Label
var _message: Label
var _callout: Label
var _flash: Label
var _msg_t := 0.0
var _callout_t := 0.0
var _flash_t := 0.0

var _menu: Control
var _menu_buttons := {}        # mode id -> Button (subtitles get refreshed)
var _pills := {}               # bottom-row pills on the menu
var _screens: Array[Control] = []   # full-screen overlays (sized in _layout)
var _career: Control
var _career_list: VBoxContainer
var _team: Control
var _team_box: VBoxContainer
var _settings: Control
var _settings_box: VBoxContainer
var _stats: Control
var _stats_grid: GridContainer
var _longer: Control
var _locker: Control
var _locker_box: VBoxContainer
var _wardrobe: Control
var _wardrobe_box: VBoxContainer
var _awards: Control
var _awards_grid: GridContainer
var _pause_menu: Control
var _quit_btn: Button
var _names: Array[Label] = []

var _training: Control
var _training_grid: GridContainer
var _online: Control
var _online_status: Label
var _code_label: Label
var _code_edit: LineEdit
var _ai_btn: Button
var _start_btn: Button
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
	_wind_label = _pill_label("", 13, Color.WHITE, PANEL)
	_wind_label.visible = false
	safe.add_child(_wind_label)

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
	hit_btn.released.connect(func(aim: Vector2) -> void: shot_requested.emit(Hud.swipe_kind(aim), aim))
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
	smash_btn.charge = 0.0
	smash_btn.fire_on_press = true
	smash_btn.released.connect(func(aim: Vector2) -> void: shot_requested.emit("smash", aim))
	controls.add_child(smash_btn)

	_build_menu()
	_build_online()
	_build_training()
	_screens.append(_online)
	_screens.append(_training)
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
	for sc in _screens:
		sc.visible = false
	if on:
		refresh_menu()
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
		_online_status.text = "Play someone anywhere: a random opponent, or a friend with a code.\nYour rating: %d · %s  (quick matches are ranked; private games aren't)" % [Profile.rating(), Roster.tier(Profile.rating())]


func set_online_status(text: String) -> void:
	_online_status.text = text


func show_room_code(code: String) -> void:
	_code_label.text = code
	_code_label.visible = true
	_online_status.text = "Send your friend this code. The match starts when they join."


## Doubles room host: play with the phones that are here (AI fills the rest).
func show_start_now(on: bool) -> void:
	if _start_btn:
		_start_btn.visible = on


func show_ai_fallback(on: bool) -> void:
	if _ai_btn.visible != on:
		_ai_btn.visible = on


var _training_info := {}


## info: drill id -> short progress text ("Done · best 7"), shown under each drill.
func set_training_info(info: Dictionary) -> void:
	_training_info = info


func show_training(on: bool, info := {}) -> void:
	_training.visible = on
	if not on:
		return
	_menu.visible = false
	for c in _training_grid.get_children():
		c.queue_free()
	for d in TRAINING:
		var id: String = d[0]
		var sub: String = info.get(id, "")
		var locked: bool = Roster.SHOTS.has(id) and not Profile.shot_unlocked(id)
		if locked:
			sub = "Locked · win %s" % Roster.venue(Roster.SHOTS[id].unlock).name
		var b := _button("%s\n%s" % [d[1], sub if sub != "" else "Not tried yet"], 15,
			LIME if sub.begins_with("✓") else (Color(1, 1, 1, 0.14) if locked else Color(1, 1, 1, 0.94)), MUTED if locked else INK)
		b.custom_minimum_size = Vector2(300, 50)
		b.disabled = locked
		b.pressed.connect(func() -> void:
			_training.visible = false
			training_chosen.emit(id))
		_training_grid.add_child(b)
	_training_grid.columns = 3


func _build_training() -> void:
	_training = ColorRect.new()
	(_training as ColorRect).color = Color(0.03, 0.06, 0.1, 0.86)
	_training.mouse_filter = Control.MOUSE_FILTER_STOP
	_training.visible = false
	add_child(_training)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_training.add_child(centre)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	centre.add_child(col)
	var title := _label("Training", 32, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _label("A ball machine feeds you. Hit the goal to complete each drill.", 15, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_training_grid = GridContainer.new()
	_training_grid.columns = 2
	_training_grid.add_theme_constant_override("h_separation", 10)
	_training_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(_training_grid)
	var back := _button("Back", 16, Color(1, 1, 1, 0.2), Color.WHITE)
	back.custom_minimum_size = Vector2(140, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		_training.visible = false
		_menu.visible = true)
	col.add_child(back)


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


## Bottom pill during a replay; "" hides it.
func set_banner(text: String) -> void:
	_callout.text = text
	_callout_t = 999.0 if text != "" else 0.0
	_layout_message()


## "" hides it.
func set_wind(text: String) -> void:
	_wind_label.text = text
	_wind_label.visible = text != "" and not _menu.visible
	_layout_message()


func set_rally(n: int) -> void:
	set_rally_text("RALLY  %d" % n)


func set_rally_text(text: String) -> void:
	_rally_label.text = text
	if is_instance_valid(safe):
		_rally_panel.reset_size()
		_rally_panel.position = Vector2(0.0 if Profile.left_handed() else safe.size.x - _rally_panel.size.x, 0)


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
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.12) if st == "pressed" else bg
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, fg)
	b.pressed.connect(func() -> void: Sfx.play_ui())
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
	col.add_theme_constant_override("separation", 7)
	centre.add_child(col)
	var title := _label("OFF THE GLASS", 42, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for m in MODES:
		var id: String = m[0]
		var b := _button("%s\n%s" % [m[1], m[2]], 15, LIME if id in ["career", "quick"] else Color(1, 1, 1, 0.94), INK)
		b.custom_minimum_size = Vector2(330, 58)
		match id:
			"online": b.pressed.connect(func() -> void: show_online(true))
			"training": b.pressed.connect(func() -> void: show_training(true, _training_info))
			"career": b.pressed.connect(func() -> void: show_career(true))
			"daily": b.pressed.connect(func() -> void: daily_chosen.emit())
			"longer": b.pressed.connect(func() -> void: _open(_longer))
			_: b.pressed.connect(func() -> void: mode_chosen.emit(id, Profile.golden_point()))
		_menu_buttons[id] = b
		grid.add_child(b)
	# bottom row: team, AI level, court, stats, settings
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for id in ["team", "locker", "ai", "court", "stats", "settings"]:
		var pb := _button("", 14, Color(1, 1, 1, 0.16), Color.WHITE)
		pb.custom_minimum_size = Vector2(0, 40)
		_pills[id] = pb
		row.add_child(pb)
	_pills.team.pressed.connect(func() -> void: show_team(true))
	_pills.locker.pressed.connect(func() -> void: show_locker(true))
	_pills.stats.pressed.connect(func() -> void: show_stats(true))
	_pills.settings.pressed.connect(func() -> void: show_settings(true))
	_pills.ai.pressed.connect(func() -> void:
		Profile.set_v("settings", "difficulty", (Profile.difficulty() + 1) % 3)
		Profile.save()
		refresh_menu()
		settings_changed.emit())
	_pills.court.pressed.connect(func() -> void:
		var open: Array = []
		for i in Roster.VENUES.size():
			if Profile.venue_unlocked(i):
				open.append(Roster.VENUES[i].id)
		for v in Roster.EXTRA_VENUES:
			open.append(v.id)
		var at := open.find(Profile.get_v("settings", "court", "club"))
		Profile.set_v("settings", "court", open[(at + 1) % open.size()])
		Profile.save()
		refresh_menu()
		settings_changed.emit())
	_build_longer()
	_build_career()
	_build_team()
	_build_settings()
	_build_stats()
	_build_locker()
	_build_wardrobe()
	_build_awards()


## Menu labels that depend on saved state (team, AI level, court, today's best).
func refresh_menu() -> void:
	if _pills.is_empty():
		return
	var lu := Roster.lineup(Profile.character(), Profile.partner())
	_pills.team.text = "Team: %s & %s" % [Roster.character(lu[0]).name, Roster.character(lu[1]).name]
	_pills.ai.text = "AI: %s" % Profile.DIFFICULTIES[Profile.difficulty()]
	_pills.court.text = "Court: %s" % Roster.venue(Profile.get_v("settings", "court", "club")).name
	_pills.stats.text = "Stats"
	var pts := Profile.skill_points()
	_pills.locker.text = "Locker%s" % ("  (%d)" % pts if pts > 0 else "")
	_pills.settings.text = "Settings"
	var best := Profile.daily_best()
	_menu_buttons.daily.text = "Daily challenge\n%s" % ("Today's best: %d goals" % best if best > 0 else "Hit the moving goal on the back glass")
	var next := ""
	for v in Roster.VENUES:
		if not Profile.career_won(v.id):
			next = "%s · %s" % [v.name, Roster.ROUNDS[Profile.career_round(v.id)]]
			break
	_menu_buttons.career.text = "Career\n%s" % (next if next != "" else "World champions! Defend your titles")


# --- full-screen overlays --------------------------------------------------------

## A full-screen panel with a title row; returns [root, column].
func _screen(title: String, subtitle := "") -> Array:
	var root := ColorRect.new()
	root.color = Color(0.03, 0.06, 0.1, 0.9)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	_screens.append(root)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	centre.add_child(col)
	var t := _label(title, 30, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if subtitle != "":
		var st := _label(subtitle, 14, MUTED)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(st)
	return [root, col]


func _back_button(screen: Control, label := "Back") -> Button:
	var back := _button(label, 16, Color(1, 1, 1, 0.2), Color.WHITE)
	back.custom_minimum_size = Vector2(150, 42)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		screen.visible = false
		_menu.visible = true
		refresh_menu())
	return back


func _open(screen: Control) -> void:
	_menu.visible = false
	screen.visible = true


func _build_longer() -> void:
	var sc := _screen("Longer match", "Golden point and AI level are on the menu and in Settings")
	_longer = sc[0]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	sc[1].add_child(row)
	for m in [["set", "One set\nFirst to 6, tie-break at 6-6"], ["match", "Full match\nBest of three sets"]]:
		var id: String = m[0]
		var b := _button(m[1], 16, Color(1, 1, 1, 0.94), INK)
		b.custom_minimum_size = Vector2(260, 64)
		b.pressed.connect(func() -> void:
			_longer.visible = false
			mode_chosen.emit(id, Profile.golden_point()))
		row.add_child(b)
	sc[1].add_child(_back_button(_longer))


func _build_career() -> void:
	var sc := _screen("Career", "Win three rounds to take each title and unlock the next court")
	_career = sc[0]
	_career_list = VBoxContainer.new()
	_career_list.add_theme_constant_override("separation", 7)
	sc[1].add_child(_career_list)
	sc[1].add_child(_back_button(_career))


func show_career(on: bool) -> void:
	if not on:
		_career.visible = false
		return
	for c in _career_list.get_children():
		c.queue_free()
	for i in Roster.VENUES.size():
		var v: Dictionary = Roster.VENUES[i]
		var id: String = v.id
		var unlocked := Profile.venue_unlocked(i)
		var rnd := Profile.career_round(id)
		var status := ""
		if not unlocked:
			status = "Locked · win %s first" % Roster.VENUES[i - 1].name
		elif Profile.career_won(id) and rnd == 0:
			status = "CHAMPIONS · play it again"
		else:
			status = "Next: %s%s" % [Roster.ROUNDS[rnd], "  (rounds won: %d)" % rnd if rnd > 0 else ""]
		var b := _button("%s  ·  %s\n%s" % [v.name, v.sub, status], 15,
			(v.court as Color).lightened(0.08) if unlocked else Color(1, 1, 1, 0.12),
			Color.WHITE if unlocked else MUTED)
		b.custom_minimum_size = Vector2(560, 52)
		b.disabled = not unlocked
		b.pressed.connect(func() -> void:
			_career.visible = false
			career_chosen.emit(id))
		_career_list.add_child(b)
	_open(_career)


func _build_team() -> void:
	var sc := _screen("Your team", "Pick who you play as, then your partner. The other two are your rivals.")
	_team = sc[0]
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 6)
	sc[1].add_child(_team_box)
	sc[1].add_child(_back_button(_team, "Done"))


func show_team(on: bool) -> void:
	if not on:
		_team.visible = false
		return
	for c in _team_box.get_children():
		c.queue_free()
	var lu := Roster.lineup(Profile.character(), Profile.partner())
	for pass_i in 2:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var head := _label("You play as" if pass_i == 0 else "Partner", 15, MUTED)
		head.custom_minimum_size = Vector2(96, 0)
		row.add_child(head)
		for ch in Roster.CHARACTERS:
			var cid: String = ch.id
			if pass_i == 1 and cid == lu[0]:
				continue
			var picked: bool = cid == lu[pass_i]
			var b := _button("%s\n%s" % [ch.name, ch.style], 15, LIME if picked else Color(1, 1, 1, 0.94), INK)
			b.custom_minimum_size = Vector2(130, 52)
			b.pressed.connect(func() -> void:
				if pass_i == 0:
					Profile.set_v("team", "me", cid)
					if Profile.partner() == cid:
						Profile.set_v("team", "partner", lu[0])
				else:
					Profile.set_v("team", "partner", cid)
				Profile.save()
				team_changed.emit()
				show_team(true))
			row.add_child(b)
		_team_box.add_child(row)
	var side_row := HBoxContainer.new()
	side_row.alignment = BoxContainer.ALIGNMENT_CENTER
	side_row.add_theme_constant_override("separation", 8)
	var sh := _label("Your side", 15, MUTED)
	sh.custom_minimum_size = Vector2(96, 0)
	side_row.add_child(sh)
	for sd in [["left", "Left · revés side"], ["right", "Right · drive side"]]:
		var sid: String = sd[0]
		var picked := Profile.side() == sid
		var sb := _button(sd[1], 15, LIME if picked else Color(1, 1, 1, 0.94), INK)
		sb.custom_minimum_size = Vector2(200, 40)
		sb.pressed.connect(func() -> void:
			Profile.set_v("team", "side", sid)
			Profile.save()
			team_changed.emit()
			show_team(true))
		side_row.add_child(sb)
	_team_box.add_child(side_row)
	var me := Roster.character(lu[0])
	var mate := Roster.character(lu[1])
	var info := _label("%s: %s\n%s: %s\nRivals: %s & %s" % [me.name, me.desc, mate.name, mate.desc,
		Roster.character(lu[2]).name, Roster.character(lu[3]).name], 14, Color.WHITE)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_team_box.add_child(info)
	_open(_team)


func _build_settings() -> void:
	var sc := _screen("Settings")
	_settings = sc[0]
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 6)
	sc[1].add_child(_settings_box)
	sc[1].add_child(_back_button(_settings, "Done"))


const SETTINGS := [
	["sound", "Sound", ["Off", "On"], true],
	["haptics", "Vibration", ["Off", "On"], true],
	["left_handed", "Controls", ["Right-hand", "Left-hand"], false],
	["one_handed", "One-handed", ["Off", "On"], false],
	["button_size", "Buttons", ["S", "M", "L"], 1],
	["difficulty", "AI level", ["Easy", "Normal", "Hard"], 1],
	["golden_point", "Golden point", ["Off", "On"], true],
	["replays", "Replays", ["Off", "On"], true],
	["ball_trail", "Ball trail", ["Off", "On"], false],
	["ball_contrast", "Ball colour", ["Classic", "Contrast"], false],
	["ball_large", "Ball size", ["Normal", "Large"], false],
	["court_colour", "Court colour", [], ""],
]
const COURT_COLOURS := [["", "Venue"], ["blue", "Blue"], ["green", "Green"], ["red", "Red"], ["yellow", "Yellow"], ["purple", "Purple"], ["pink", "Pink"]]


func show_settings(on: bool) -> void:
	if not on:
		_settings.visible = false
		return
	for c in _settings_box.get_children():
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	_settings_box.add_child(grid)
	for st in SETTINGS:
		var key: String = st[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var l := _label(st[1], 15, Color.WHITE)
		l.custom_minimum_size = Vector2(112, 0)
		row.add_child(l)
		if key == "court_colour":
			var cur: String = Profile.court_colour()
			var idx := 0
			for i in COURT_COLOURS.size():
				if COURT_COLOURS[i][0] == cur:
					idx = i
			var cb := _button("%s  ›" % COURT_COLOURS[idx][1], 14, LIME if cur != "" else Color(1, 1, 1, 0.16), INK if cur != "" else Color.WHITE)
			cb.custom_minimum_size = Vector2(250, 34)
			cb.pressed.connect(func() -> void:
				Profile.set_v("settings", "court_colour", COURT_COLOURS[(idx + 1) % COURT_COLOURS.size()][0])
				Profile.save()
				settings_changed.emit()
				show_settings(true))
			row.add_child(cb)
			grid.add_child(row)
			continue
		var cur_v := int(Profile.get_v("settings", key, st[3]))
		var opts: Array = st[2]
		for i in opts.size():
			var picked: bool = cur_v == i
			var b := _button(opts[i], 13, LIME if picked else Color(1, 1, 1, 0.16), INK if picked else Color.WHITE)
			b.custom_minimum_size = Vector2((250.0 - 5.0 * (opts.size() - 1)) / opts.size(), 34)
			b.pressed.connect(func() -> void:
				var v: Variant = i if key in ["button_size", "difficulty"] else bool(i)
				Profile.set_v("settings", key, v)
				Profile.save()
				settings_changed.emit()
				_layout()
				show_settings(true))
			row.add_child(b)
		grid.add_child(row)
	_open(_settings)


func _build_locker() -> void:
	var sc := _screen("Locker", "Skills and paddles help you in career, training and quick play. Online is always even.")
	_locker = sc[0]
	_locker_box = VBoxContainer.new()
	_locker_box.add_theme_constant_override("separation", 6)
	sc[1].add_child(_locker_box)
	sc[1].add_child(_back_button(_locker, "Done"))


func show_locker(on: bool) -> void:
	if not on:
		_locker.visible = false
		return
	for c in _locker_box.get_children():
		c.queue_free()
	var pts := Profile.skill_points()
	var head := _label("Skill points: %d   ·   earn them by winning career matches, completing drills and scoring 5+ in the daily challenge" % pts, 14, LIME if pts > 0 else MUTED)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locker_box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	_locker_box.add_child(grid)
	for sk in Roster.SKILLS:
		var sid: String = sk[0]
		var lvl := Profile.skill(sid)
		var name := _label(sk[1], 16, Color.WHITE)
		name.custom_minimum_size = Vector2(80, 0)
		grid.add_child(name)
		var bar := _label("■".repeat(lvl) + "□".repeat(Roster.SKILL_MAX - lvl), 18, LIME)
		grid.add_child(bar)
		grid.add_child(_label(sk[2], 13, MUTED))
		var up := _button("+", 18, LIME if pts > 0 and lvl < Roster.SKILL_MAX else Color(1, 1, 1, 0.12), INK)
		up.custom_minimum_size = Vector2(52, 34)
		up.disabled = pts <= 0 or lvl >= Roster.SKILL_MAX
		up.pressed.connect(func() -> void:
			Profile.set_v("skills", sid, lvl + 1)
			Profile.save()
			locker_changed.emit()
			show_locker(true))
		grid.add_child(up)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	_locker_box.add_child(row)
	var current := Profile.paddle_id()
	for pd in Roster.PADDLES:
		var pid: String = pd.id
		var owned := Profile.paddle_owned(pid)
		var picked: bool = pid == current
		var stats := "Power %s · Control %s" % [_pips(pd.power / 2.6), _pips(0.5 + pd.touch / 0.14)]
		var text := "%s\n%s" % [pd.name, stats if owned else "Win %s" % Roster.venue(pd.unlock).name]
		var b := _button(text, 13, LIME if picked else ((pd.trim as Color).darkened(0.55) if owned else Color(1, 1, 1, 0.1)),
			INK if picked else (Color.WHITE if owned else MUTED))
		b.custom_minimum_size = Vector2(158, 50)
		b.disabled = not owned
		b.pressed.connect(func() -> void:
			Profile.set_v("kit", "paddle", pid)
			Profile.save()
			locker_changed.emit()
			show_locker(true))
		row.add_child(b)
	var desc := _label("%s: %s" % [Roster.paddle(current).name, Roster.paddle(current).desc], 14, Color.WHITE)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locker_box.add_child(desc)
	var wb := _button("Wardrobe  ·  %d coins" % Profile.coins(), 15, Color(1, 1, 1, 0.94), INK)
	wb.custom_minimum_size = Vector2(260, 40)
	wb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wb.pressed.connect(func() -> void:
		_locker.visible = false
		show_wardrobe(true))
	_locker_box.add_child(wb)
	_open(_locker)


## 0..1 as five pips.
func _pips(v: float) -> String:
	var n := clampi(roundi(clampf(v, 0.0, 1.0) * 5.0), 0, 5)
	return "●".repeat(n) + "○".repeat(5 - n)


func _build_wardrobe() -> void:
	var sc := _screen("Wardrobe", "Looks only. Earn coins by winning points, matches, career rounds and achievements.")
	_wardrobe = sc[0]
	_wardrobe_box = VBoxContainer.new()
	_wardrobe_box.add_theme_constant_override("separation", 7)
	sc[1].add_child(_wardrobe_box)
	sc[1].add_child(_back_button(_wardrobe, "Done"))


func show_wardrobe(on: bool) -> void:
	if not on:
		_wardrobe.visible = false
		return
	for c in _wardrobe_box.get_children():
		c.queue_free()
	var coins := _label("Coins: %d" % Profile.coins(), 16, LIME)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wardrobe_box.add_child(coins)
	var refresh := func() -> void:
		Profile.save()
		locker_changed.emit()
		show_wardrobe(true)
	# headwear
	var hats := _row("Headwear")
	for h in Roster.HATS:
		var hid: String = h[0]
		var price: int = h[2]
		var owned := hid == "" or Profile.owns("hat_" + hid)
		var on_now: bool = Profile.get_v("look", "hat", "") == hid
		var b := _button(h[1] if owned else "%s · %d" % [h[1], price], 14, LIME if on_now else Color(1, 1, 1, 0.94 if owned else 0.3), INK)
		b.custom_minimum_size = Vector2(120, 38)
		b.pressed.connect(func() -> void:
			if owned or Profile.buy("hat_" + hid, price):
				Profile.set_v("look", "hat", hid)
			refresh.call())
		hats.add_child(b)
	_wardrobe_box.add_child(hats)
	_wardrobe_box.add_child(_palette_row("Headwear colour", "hat_col", 2, refresh))
	# wristband
	var band := _row("Wristband")
	var has_band := Profile.owns("wristband")
	var bb := _button("Owned: pick a colour" if has_band else "Buy · %d" % Roster.WRISTBAND_PRICE, 14, Color(1, 1, 1, 0.94 if has_band else 0.3), INK)
	bb.custom_minimum_size = Vector2(240, 38)
	bb.disabled = has_band
	bb.pressed.connect(func() -> void:
		if Profile.buy("wristband", Roster.WRISTBAND_PRICE):
			Profile.set_v("look", "band_col", 0)
		refresh.call())
	band.add_child(bb)
	_wardrobe_box.add_child(band)
	if has_band:
		_wardrobe_box.add_child(_palette_row("Wristband colour", "band_col", 1, refresh))
	# paddle skins
	var skins := _row("Paddle skin")
	for sk in Roster.SKINS:
		var sid: String = sk[0]
		var price: int = sk[4]
		var owned := sid == "" or Profile.owns("skin_" + sid)
		var on_now: bool = Profile.get_v("look", "skin", "") == sid
		var bg: Color = LIME if on_now else ((sk[3] as Color).darkened(0.35) if sid != "" else Color(1, 1, 1, 0.94))
		if not owned:
			bg.a = 0.35
		var b := _button(sk[1] if owned else "%s · %d" % [sk[1], price], 13, bg, INK if on_now or sid == "" else Color.WHITE)
		b.custom_minimum_size = Vector2(96, 38)
		b.pressed.connect(func() -> void:
			if owned or Profile.buy("skin_" + sid, price):
				Profile.set_v("look", "skin", sid)
			refresh.call())
		skins.add_child(b)
	_wardrobe_box.add_child(skins)
	_open(_wardrobe)


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var l := _label(title, 15, MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	return row


func _palette_row(title: String, key: String, default: int, refresh: Callable) -> HBoxContainer:
	var row := _row(title)
	var cur := int(Profile.get_v("look", key, default))
	for i in Roster.PALETTE.size():
		var c: Color = Roster.PALETTE[i]
		var b := _button("●" if i == cur else "", 14, c, INK if c.get_luminance() > 0.5 else Color.WHITE)
		b.custom_minimum_size = Vector2(44, 34)
		b.pressed.connect(func() -> void:
			Profile.set_v("look", key, i)
			refresh.call())
		row.add_child(b)
	return row


func _build_awards() -> void:
	var sc := _screen("Achievements", "Each one is worth %d coins" % Awards.COINS)
	_awards = sc[0]
	_awards_grid = GridContainer.new()
	_awards_grid.columns = 3
	_awards_grid.add_theme_constant_override("h_separation", 8)
	_awards_grid.add_theme_constant_override("v_separation", 5)
	sc[1].add_child(_awards_grid)
	sc[1].add_child(_back_button(_awards))


func show_awards(on: bool) -> void:
	if not on:
		_awards.visible = false
		return
	for c in _awards_grid.get_children():
		c.queue_free()
	for a in Awards.list():
		var got := Awards.unlocked(a[0])
		var b := _button("%s%s\n%s" % ["✓ " if got else "", a[1], a[2]], 12, LIME if got else Color(1, 1, 1, 0.14), INK if got else MUTED)
		b.custom_minimum_size = Vector2(250, 40)
		b.disabled = true
		_awards_grid.add_child(b)
	_open(_awards)


func _build_stats() -> void:
	var sc := _screen("Your stats")
	_stats = sc[0]
	var ab := _button("Achievements", 15, LIME, INK)
	ab.custom_minimum_size = Vector2(200, 38)
	ab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ab.pressed.connect(func() -> void:
		_stats.visible = false
		show_awards(true))
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 22)
	_stats_grid.add_theme_constant_override("v_separation", 6)
	sc[1].add_child(_stats_grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(ab)
	# Game Center leaderboards + achievements (iOS, once signed in)
	_gc_button = _button("Game Center", 15, Color(1, 1, 1, 0.14), Color.WHITE)
	_gc_button.custom_minimum_size = Vector2(200, 38)
	_gc_button.pressed.connect(GameServices.show_dashboard)
	row.add_child(_gc_button)
	sc[1].add_child(row)
	sc[1].add_child(_back_button(_stats))


var _gc_button: Button


func show_stats(on: bool) -> void:
	if not on:
		_stats.visible = false
		return
	_gc_button.visible = GameServices.signed_in()
	for c in _stats_grid.get_children():
		c.queue_free()
	var played := Profile.stat("matches")
	var won := Profile.stat("wins")
	var pts := Profile.stat("points_played")
	var drills := 0
	for k in _training_info:
		if str(_training_info[k]).begins_with("✓"):
			drills += 1
	var trophies := 0
	for v in Roster.VENUES:
		trophies += 1 if Profile.career_won(v.id) else 0
	var rows := [
		["Matches played", str(played)], ["Matches won", "%d%s" % [won, "  (%d%%)" % roundi(100.0 * won / played) if played > 0 else ""]],
		["Points won", "%d of %d" % [Profile.stat("points_won"), pts]], ["Longest rally", "%d shots" % Profile.stat("longest_rally")],
		["Power smashes", str(Profile.stat("power_smashes"))], ["Bajadas", str(Profile.stat("bajadas"))],
		["Perfect hits", str(Profile.stat("perfect"))], ["Slices", str(Profile.stat("slices"))],
		["Career titles", "%d of %d" % [trophies, Roster.VENUES.size()]], ["Drills complete", "%d of %d" % [drills, TRAINING.size() - 1]],
		["Daily best", "%d goals" % Profile.stat("daily_best")], ["Online wins", "%d of %d" % [Profile.stat("online_wins"), Profile.stat("online_matches")]],
		["Víboras", str(Profile.stat("vibora"))], ["Chiquitas", str(Profile.stat("chiquita"))],
		["Contraparedes", str(Profile.stat("contrapared"))], ["Online rating", "%d · %s" % [Profile.rating(), Roster.tier(Profile.rating())]],
	]
	var got := 0
	for a in Awards.list():
		got += 1 if Awards.unlocked(a[0]) else 0
	rows.append(["Achievements", "%d of %d" % [got, Awards.list().size()]])
	rows.append(["Coins", str(Profile.coins())])
	for r in rows:
		var k := _label(r[0], 15, MUTED)
		var v := _label(r[1], 17, Color.WHITE)
		v.custom_minimum_size = Vector2(120, 0)
		_stats_grid.add_child(k)
		_stats_grid.add_child(v)
	_open(_stats)


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
		b.pressed.connect(func() -> void: online_create.emit(id, Profile.golden_point(), 2))
		host_row.add_child(b)
	col.add_child(host_row)

	# doubles: up to four phones, two per side; AI fills any empty places
	var dbl_row := HBoxContainer.new()
	dbl_row.add_theme_constant_override("separation", 8)
	dbl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dbl_row.add_child(_label("Doubles, 4 phones:", 16, Color.WHITE))
	for h in PRIVATE_LENGTHS:
		var b := _button(h[1], 16, Color(1, 1, 1, 0.94), INK)
		b.custom_minimum_size = Vector2(110, 44)
		var id: String = h[0]
		b.pressed.connect(func() -> void: online_create.emit(id, Profile.golden_point(), 4))
		dbl_row.add_child(b)
	col.add_child(dbl_row)
	_start_btn = _button("Start now", 17, LIME, INK)
	_start_btn.custom_minimum_size = Vector2(240, 46)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_btn.visible = false
	_start_btn.pressed.connect(func() -> void: online_start_now.emit())
	col.add_child(_start_btn)

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
	for sc in _screens:
		sc.position = Vector2.ZERO
		sc.size = vp
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
	var lefty := Profile.left_handed()

	_score_panel.reset_size()
	_score_panel.position = Vector2((w - _score_panel.size.x) * 0.5, 0)
	_rally_panel.reset_size()
	_rally_panel.position = Vector2(0.0 if lefty else w - _rally_panel.size.x, 0)

	# left-handed: stick on the right, buttons on the left (mirror every x)
	var k := Profile.button_scale()
	joystick.visible = not Profile.one_handed()   # one-handed: the player moves itself
	joystick.size = Vector2(w * 0.42, h * 0.6)
	joystick.position = Vector2(w - joystick.size.x if lefty else 0.0, h * 0.4)
	joystick.rest_centre = Vector2(joystick.size.x - 80 if lefty else 80.0, joystick.size.y - 80)
	var mx := func(x: float) -> float: return w - x if lefty else x
	hit_btn.radius = 50 * k
	lob_btn.radius = 32 * k
	smash_btn.radius = 32 * k
	_place(hit_btn, Vector2(mx.call(w - 70 * k), h - 70 * k), 72 * k)
	_place(lob_btn, Vector2(mx.call(w - 185 * k), h - 38 * k), 48 * k)
	_place(smash_btn, Vector2(mx.call(w - 60 * k), h - 195 * k), 48 * k)
	pause_btn.position = Vector2(w - pause_btn.size.x if lefty else 0.0, 0)
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
	if _wind_label:
		_wind_label.reset_size()
		_wind_label.position = Vector2((w - _wind_label.size.x) * 0.5, _score_panel.size.y + 6)
