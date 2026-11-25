class_name Ball
extends Node3D
## The live ball: runs BallSim with substeps and re-emits its events.

signal floor_bounce(pos: Vector3)
signal wall_hit(pos: Vector3, surface: String)
signal net_hit(pos: Vector3)
signal out_of_court(pos: Vector3)

const RADIUS := BallSim.RADIUS
const GRAVITY := BallSim.GRAVITY
const SUBSTEPS := 4

var sim := BallSim.new()
var live := false

var velocity: Vector3:
	get:
		return sim.vel
	set(v):
		sim.vel = v

var _shadow: MeshInstance3D
var _mat: StandardMaterial3D
var _mesh: MeshInstance3D
var _trail: MultiMeshInstance3D
var _trail_pos: Array[Vector3] = []
const TRAIL_N := 14
const CONTRAST_COLOUR := Color("ff3df2")   # high-contrast: magenta reads on every court colour
var base_colour := BALL_COLOUR
var trail_on := false
var _burst := 0.0                 # a smash: a hot trail for a moment, whatever the setting
const BALL_COLOUR := Color("d9f542")
const SLICE_COLOUR := Color("7fd6ff")
## Shown spin for the visual tint; the online guest sets this from snapshots.
var shown_spin := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06   # drawn a little larger than real so it reads on a phone
	sm.height = 0.12
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("d9f542")
	m.emission_enabled = true
	m.emission = Color("d9f542")
	m.emission_energy_multiplier = 0.35
	mi.material_override = m
	_mat = m
	_mesh = mi
	add_child(mi)
	# fading trail of recent positions (accessibility: easier to track the ball)
	_trail = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var tsm := SphereMesh.new()
	tsm.radius = 0.05
	tsm.height = 0.1
	tsm.radial_segments = 8
	tsm.rings = 4
	mm.mesh = tsm
	mm.instance_count = TRAIL_N
	_trail.multimesh = mm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.vertex_color_use_as_albedo = true
	_trail.material_override = tm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.top_level = true
	_trail.visible = false
	add_child(_trail)


## Accessibility: ball size, high-contrast colour, and the trail.
func set_look(large: bool, contrast: bool, trail: bool) -> void:
	_mesh.scale = Vector3.ONE * (1.5 if large else 1.0)
	base_colour = CONTRAST_COLOUR if contrast else BALL_COLOUR
	trail_on = trail
	_trail.visible = trail
	_trail_pos.clear()

	_shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 0.002
	_shadow.mesh = cm
	var sh := StandardMaterial3D.new()
	sh.albedo_color = Color(0, 0, 0, 0.45)
	sh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = sh
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)


func burst(secs: float) -> void:
	if _burst <= 0.0:
		_trail_pos.clear()
	_burst = secs


func place(p: Vector3) -> void:
	sim.pos = p
	sim.vel = Vector3.ZERO
	sim.rolling = false
	sim.spin = 0.0
	shown_spin = 0.0
	position = p


func _physics_process(delta: float) -> void:
	if live:
		for i in SUBSTEPS:
			if not live:
				break
			for e in sim.step(delta / SUBSTEPS):
				match e[0]:
					"floor": floor_bounce.emit(e[1])
					"wall": wall_hit.emit(e[1], e[2])
					"net": net_hit.emit(e[1])
					"out": out_of_court.emit(e[1])
		position = sim.pos
	if live:
		shown_spin = sim.spin
	# a sliced ball glows cool blue so the spin reads on a phone screen
	var c := base_colour.lerp(SLICE_COLOUR, clampf(-shown_spin, 0.0, 1.0))
	_mat.albedo_color = c
	_mat.emission = c
	_shadow.global_position = Vector3(position.x, 0.012, position.z)
	_burst = maxf(0.0, _burst - delta)
	_trail.visible = trail_on or _burst > 0.0
	if _trail.visible:
		if _burst > 0.0:
			c = Color(1.0, 0.62, 0.18).lerp(c, clampf(1.0 - _burst, 0.0, 1.0))
		if _trail_pos.is_empty() or _trail_pos[0].distance_to(position) > 0.02:
			_trail_pos.push_front(position)
			if _trail_pos.size() > TRAIL_N:
				_trail_pos.pop_back()
		var mm := _trail.multimesh
		for i in TRAIL_N:
			var on := i < _trail_pos.size() and live
			var k := 1.0 - float(i) / TRAIL_N
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.3 + 0.7 * k) * _mesh.scale.x), _trail_pos[i] if on else Vector3(0, -50, 0)))
			mm.set_instance_color(i, Color(c.r, c.g, c.b, 0.55 * k))
	var s := clampf(1.2 - position.y * 0.12, 0.4, 1.2)
	_shadow.scale = Vector3(s, 1, s)


## Simulates ahead. Returns samples {t, pos, vel, floors: [team0, team1]}
## where floors counts floor bounces on each half from now.
func predict(seconds := 3.0) -> Array:
	var s := sim.copy()
	var out: Array = []
	var dt := 1.0 / 120.0
	var t := 0.0
	var floors := [0, 0]
	for i in int(seconds / dt):
		var ended := false
		for e in s.step(dt):
			if e[0] == "floor":
				floors[Court.side_of(e[1].z)] += 1
			elif e[0] == "out":
				ended = true
		t += dt
		if i % 2 == 1 or ended:
			out.append({"t": t, "pos": s.pos, "vel": s.vel, "floors": floors.duplicate()})
		if ended:
			break
	return out
