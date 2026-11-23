class_name DebugOverlay
extends CanvasLayer
## Playtest overlay. Toggle with a triple-tap in the top-right corner, or F3.
##
## Shows frame rate and frame time, screen refresh rate, device and safe
## area, online round-trip time, the touch zones of every control (so you
## can see why a tap missed), and a dot wherever a finger lands.

const CORNER := Vector2(150, 90)   # top-right tap zone, in viewport pixels
const TAP_WINDOW := 0.7

var main: Node        # main.gd: provides net_debug_text()
var hud: Hud
var on := false

var _canvas: Control
var _label: Label
var _taps: Array[float] = []
var _touches: Array = []           # [position, time]


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	_label = Label.new()
	_label.position = Vector2(14, 104)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("c6f432"))
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_canvas.add_child(_label)
	set_on(on)


func set_on(v: bool) -> void:
	on = v
	_canvas.visible = v
	_touches.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		set_on(not on)
	elif event is InputEventScreenTouch and event.pressed:
		var vp := get_viewport().get_visible_rect().size
		var t := _now()
		if on:
			_touches.append([event.position, t])
		if event.position.x > vp.x - CORNER.x and event.position.y < CORNER.y:
			_taps.append(t)
			while not _taps.is_empty() and t - _taps[0] > TAP_WINDOW:
				_taps.pop_front()
			if _taps.size() >= 3:
				_taps.clear()
				set_on(not on)


func _process(_delta: float) -> void:
	if not on:
		return
	var now := _now()
	while not _touches.is_empty() and now - _touches[0][1] > 1.2:
		_touches.pop_front()
	var win := DisplayServer.window_get_size()
	var sa := DisplayServer.get_display_safe_area()
	var interp := get_tree().physics_interpolation
	var hz := DisplayServer.screen_get_refresh_rate()
	var hz_text := "%d Hz" % roundi(hz) if hz > 0.0 and hz < 1000.0 else "? Hz"
	var lines := [
		"%d fps  ·  frame %.1f ms  ·  screen %s  ·  physics %d Hz%s" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			hz_text,
			Engine.physics_ticks_per_second,
			" (interpolated)" if interp else ""],
		"%s %s  ·  window %d×%d  ·  safe %d,%d %d×%d  ·  draw calls %d" % [
			OS.get_name(), OS.get_model_name(), win.x, win.y,
			sa.position.x, sa.position.y, sa.size.x, sa.size.y,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)],
	]
	if main and main.has_method("net_debug_text"):
		lines.append(main.net_debug_text())
	_label.text = "\n".join(lines)
	_canvas.queue_redraw()


func _draw_canvas() -> void:
	if hud == null:
		return
	var zone := Color(0.78, 0.96, 0.2, 0.55)
	_canvas.draw_rect(hud.safe.get_global_rect(), Color(1, 0.85, 0.2, 0.6), false, 2.0)
	if hud.controls.is_visible_in_tree():
		_canvas.draw_rect(hud.joystick.get_global_rect(), zone, false, 2.0)
		for b: TouchButton in [hud.hit_btn, hud.lob_btn, hud.smash_btn]:
			_canvas.draw_arc(b.centre_global(), b.radius * 1.25, 0, TAU, 48, zone, 2.0, true)
	var vp := get_viewport().get_visible_rect().size
	_canvas.draw_rect(Rect2(Vector2(vp.x - CORNER.x, 0), CORNER), Color(1, 1, 1, 0.15), false, 1.0)
	var now := _now()
	for t in _touches:
		var age: float = now - t[1]
		_canvas.draw_circle(t[0], 14.0, Color(1, 0.3, 0.3, 0.8 * (1.0 - age / 1.2)))
