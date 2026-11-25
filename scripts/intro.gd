class_name Intro
extends CanvasLayer
## Studio ident at launch: SOLO GAMES, a padel ball flies in, cracks off the
## logo (it jolts, the glass rings) and bounces away. About 3 s; tap to skip.

signal finished

const BG := Color("070b16")
const LIME := Color("c6f432")
const DUR := 3.1
const HIT_T := 1.0

var _t := 0.0
var _root: Control
var _canvas: Control        # ball, trail and impact ring are drawn here
var _logo: Control
var _tag: Label
var _hit_done := false
var _ball := Vector2.ZERO
var _ball_v := Vector2.ZERO
var _spin := 0.0
var _trail: Array[Vector2] = []
var _impact := Vector2.ZERO
var _impact_t := -1.0
var _shake := 0.0
var _skip := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = ColorRect.new()
	(_root as ColorRect).color = BG
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.is_pressed() and _t > 0.4:
			_skip = true)
	add_child(_root)
	_logo = Control.new()
	_root.add_child(_logo)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var font := preload("res://assets/fonts/Anton-Regular.ttf")
	for part in [["SOLO", Color.WHITE], ["GAMES", LIME]]:
		var l := Label.new()
		l.text = part[0]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 128)
		l.add_theme_color_override("font_color", part[1])
		row.add_child(l)
	_logo.add_child(row)
	row.reset_size()
	_logo.size = row.size
	_logo.pivot_offset = row.size * 0.5
	_tag = Label.new()
	_tag.text = "P R E S E N T S"
	_tag.add_theme_font_size_override("font_size", 18)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_tag.modulate.a = 0.0
	_root.add_child(_tag)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_ball)
	_root.add_child(_canvas)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	_logo.position = (vp - _logo.size) * 0.5 + Vector2(0, -16)
	_tag.reset_size()
	_tag.position = Vector2((vp.x - _tag.size.x) * 0.5, _logo.position.y + _logo.size.y + 4)


## Where the ball strikes: the middle of the first O, on the logo's face.
func _target() -> Vector2:
	return _logo.position + Vector2(_logo.size.x * 0.12, _logo.size.y * 0.5)


func _process(delta: float) -> void:
	_t += delta
	if _skip and _t < DUR - 0.35:
		_t = DUR - 0.35
	var vp := get_viewport().get_visible_rect().size
	# logo arrives: fade and settle
	var arrive := clampf(_t / 0.4, 0.0, 1.0)
	_logo.modulate.a = arrive
	var s := lerpf(0.92, 1.0, 1.0 - pow(1.0 - arrive, 3.0))
	# the ball: in on an arc from the top left, then off the logo
	if not _hit_done:
		var k := clampf((_t - 0.25) / (HIT_T - 0.25), 0.0, 1.0)
		var from := Vector2(-60, vp.y * 0.12)
		var to := _target()
		_ball = from.lerp(to, k) + Vector2(0, -sin(k * PI) * vp.y * 0.18)
		_spin += delta * 14.0
		if _t >= HIT_T:
			_hit_done = true
			_ball = to
			_impact = to
			_impact_t = 0.0
			_shake = 1.0
			_ball_v = Vector2(-vp.x * 0.32, -vp.y * 1.1)     # back and up, off the glass
			if Sfx.instance:
				Sfx.instance.ui("glass", 0.0)
			Input.vibrate_handheld(25)
	else:
		_ball_v.y += vp.y * 2.6 * delta
		_ball += _ball_v * delta
		_spin -= delta * 18.0
		_impact_t += delta
	if _t > 0.25 and _ball.y < vp.y + 80:
		_trail.push_front(_ball)
		if _trail.size() > 10:
			_trail.pop_back()
	# the hit: a squash and a decaying jolt
	_shake = maxf(0.0, _shake - delta * 2.2)
	var jolt := sin(_t * 70.0) * 16.0 * _shake * _shake
	_logo.scale = Vector2.ONE * s * (1.0 + 0.06 * _shake * _shake)
	_logo.rotation = deg_to_rad(jolt * 0.12)
	_place()
	_logo.position.x += jolt
	_tag.modulate.a = clampf((_t - HIT_T - 0.3) / 0.5, 0.0, 1.0)
	# fade out to the menu
	var out := clampf((_t - (DUR - 0.35)) / 0.35, 0.0, 1.0)
	_root.modulate.a = 1.0 - out
	_canvas.queue_redraw()
	if _t >= DUR:
		finished.emit()
		queue_free()


func _draw_ball() -> void:
	if _t < 0.25:
		return
	if _impact_t >= 0.0 and _impact_t < 0.6:
		# a ring of light off the impact
		var r := 20.0 + _impact_t * 380.0
		var a := (1.0 - _impact_t / 0.6) * 0.7
		_canvas.draw_arc(_impact, r, 0, TAU, 64, Color(LIME, a), 5.0 * (1.0 - _impact_t / 0.6) + 1.0, true)
		_canvas.draw_arc(_impact, r * 0.6, 0, TAU, 48, Color(1, 1, 1, a * 0.5), 2.0, true)
	for i in _trail.size():
		var k := 1.0 - float(i) / _trail.size()
		_canvas.draw_circle(_trail[i], 22.0 * (0.4 + 0.6 * k), Color(LIME, 0.25 * k))
	_canvas.draw_circle(_ball, 22.0, LIME)
	# the seam, turning with the spin
	var seam := Color(1, 1, 1, 0.9)
	_canvas.draw_arc(_ball + Vector2(cos(_spin), sin(_spin)) * 9.0, 15.0, _spin + 2.2, _spin + 4.1, 16, seam, 2.5, true)
	_canvas.draw_arc(_ball - Vector2(cos(_spin), sin(_spin)) * 9.0, 15.0, _spin - 0.95, _spin + 0.95, 16, seam, 2.5, true)
