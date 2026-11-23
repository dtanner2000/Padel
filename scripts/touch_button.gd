class_name TouchButton
extends Control
## Round multi-touch button. Fires `released(aim)` on release, where aim is
## the swipe from press to release: x -1..1 (left/right), y -1..1 (up = deeper).
## A plain tap gives Vector2.ZERO.

signal released(aim: Vector2)
signal pressed_down

const SWIPE := 110.0
const LIME := Color("c6f432")

var radius := 44.0
var label := "HIT"
var sublabel := ""
var font_size := 26
var fill := Color(0.035, 0.06, 0.11, 0.75)
var text_color := Color.WHITE
var outline := Color(1, 1, 1, 0.6)
var enabled := true:
	set(v):
		if v != enabled:
			enabled = v
			queue_redraw()
var readiness := -1.0:   # 0..1 draws the timing arc; < 0 hides it
	set(v):
		if not is_equal_approx(v, readiness):
			readiness = v
			queue_redraw()

var fire_on_press := false   # LOB / SMASH: act on touch-down, no swipe

var _touch := -1
var _start := Vector2.ZERO
var _drag := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_held() -> bool:
	return _touch != -1


## Swipe so far while held: same mapping as the release aim.
func live_aim() -> Vector2:
	if _drag.length() < 12.0:
		return Vector2.ZERO
	return Vector2(clampf(_drag.x / SWIPE, -1.0, 1.0), clampf(-_drag.y / SWIPE, -1.0, 1.0))


func centre_global() -> Vector2:
	return global_position + size * 0.5


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touch == -1 and enabled and t.position.distance_to(centre_global()) <= radius * 1.25:
				_touch = t.index
				_start = t.position
				_drag = Vector2.ZERO
				queue_redraw()
				get_viewport().set_input_as_handled()
				pressed_down.emit()
				if fire_on_press:
					released.emit(Vector2.ZERO)
		elif t.index == _touch:
			var d := t.position - _start
			_touch = -1
			_drag = Vector2.ZERO
			queue_redraw()
			var aim := Vector2(clampf(d.x / SWIPE, -1.0, 1.0), clampf(-d.y / SWIPE, -1.0, 1.0))
			if d.length() < 12.0:
				aim = Vector2.ZERO
			if not fire_on_press:
				released.emit(aim)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == _touch:
			_drag = (dr.position - _start).limit_length(SWIPE)
			queue_redraw()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var c := size * 0.5
	if readiness >= 0.0:
		draw_arc(c, radius + 10, 0, TAU, 64, Color(1, 1, 1, 0.22), 5.0, true)
		if readiness > 0.01:
			draw_arc(c, radius + 10, -PI * 0.5, -PI * 0.5 + TAU * readiness, 64, LIME, 5.0, true)
	var f := fill
	if not enabled:
		f = Color(f.r, f.g, f.b, f.a * 0.45)
	if _touch != -1:
		f = f.lightened(0.15)
	draw_circle(c, radius, f)
	draw_arc(c, radius, 0, TAU, 64, Color(outline, outline.a * (1.0 if enabled else 0.4)), 2.0, true)
	var font := ThemeDB.fallback_font
	var tc := text_color if enabled else Color(text_color, 0.45)
	var y := c.y + font_size * 0.35 - (7.0 if sublabel != "" else 0.0)
	draw_string(font, Vector2(c.x - radius, y), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, tc)
	if sublabel != "":
		draw_string(font, Vector2(c.x - radius, y + 17), sublabel, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 11, tc)
	if _touch != -1 and _drag.length() > 10.0:
		var tip := c + _drag * 0.75
		draw_line(c, tip, Color.WHITE, 4.0, true)
		draw_circle(tip, 7.0, Color.WHITE)
