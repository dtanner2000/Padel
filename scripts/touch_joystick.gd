class_name TouchJoystick
extends Control
## Floating thumbstick: touch anywhere in this control's area and drag.
## value is -1..1 on each axis (y down = towards your own back wall).

var value := Vector2.ZERO
var radius := 62.0
var rest_centre := Vector2(90, 90)   # local position drawn when idle

var _touch := -1
var _origin := Vector2.ZERO          # global
var _knob := Vector2.ZERO            # global


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if _touch != -1:
			_touch = -1
			value = Vector2.ZERO
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1 and get_global_rect().has_point(t.position):
			_touch = t.index
			_origin = t.position
			_knob = t.position
			value = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _touch:
			_touch = -1
			value = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch:
			var off := d.position - _origin
			if off.length() > radius:
				_origin += off - off.normalized() * radius   # base follows the thumb
				off = off.normalized() * radius
			_knob = _origin + off
			value = off / radius
			queue_redraw()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var c := rest_centre
	var k := rest_centre
	if _touch != -1:
		c = _origin - global_position
		k = _knob - global_position
	draw_circle(c, radius, Color(0.035, 0.06, 0.11, 0.38))
	draw_arc(c, radius, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.0, true)
	draw_circle(k, radius * 0.42, Color(1, 1, 1, 0.88))
