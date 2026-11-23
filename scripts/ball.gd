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
	add_child(mi)

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


func place(p: Vector3) -> void:
	sim.pos = p
	sim.vel = Vector3.ZERO
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
	var c := BALL_COLOUR.lerp(SLICE_COLOUR, clampf(-shown_spin, 0.0, 1.0))
	_mat.albedo_color = c
	_mat.emission = c
	_shadow.global_position = Vector3(position.x, 0.012, position.z)
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
