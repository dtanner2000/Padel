class_name Player
extends Node3D
## One of the four players. Movement only; decisions live in main.gd.

var team := 0
var is_human := false
var display_name := ""
var slot_x := 0.0          # home half when receiving (world x)
var speed := 4.7           # m/s
var react := 0.0           # seconds left before reacting to the last shot
var accel := 20.0          # m/s² — the human gets much more, so the stick feels direct
var reach := 1.15          # horizontal reach to the ball, m
var skill := 0.7           # 0..1, scales AI shot error
var vel := Vector3.ZERO
var hit_cooldown := 0.0
var swing_count := 0       # bumped on every swing; lets a network client replay swings

var shirt := Color("f28c28")
var skin := Color("e3b48c")
var hair := Color("3a2a20")

var _pivot: Node3D
var _body: Node3D
var _swing: Tween
var _tag: Label3D


func setup(p_team: int, p_name: String, p_slot: float, p_shirt: Color, p_skin: Color, p_hair: Color, human := false) -> Player:
	team = p_team
	display_name = p_name
	slot_x = p_slot
	shirt = p_shirt
	skin = p_skin
	hair = p_hair
	is_human = human
	name = p_name
	return self


func _ready() -> void:
	_build()
	face_net()


func face_net() -> void:
	rotation.y = 0.0 if team == 0 else PI


## World-space x direction of this player's forehand side.
func right_x() -> float:
	return 1.0 if team == 0 else -1.0


func move_towards(target: Vector3, delta: float, speed_scale := 1.0) -> void:
	var to := target - position
	to.y = 0.0
	var desired := Vector3.ZERO
	var d := to.length()
	if d > 0.03:
		desired = to / d * speed * speed_scale * clampf(d / 0.5, 0.0, 1.0)
	_apply(desired, delta)


## dir: world-space direction, length 0..1.
func move_dir(dir: Vector3, delta: float) -> void:
	_apply(dir.limit_length(1.0) * speed, delta)


func _apply(desired: Vector3, delta: float) -> void:
	vel = vel.move_toward(desired, accel * delta)
	position += vel * delta
	position.y = 0.0
	position.x = clampf(position.x, -Court.HALF_W + 0.3, Court.HALF_W - 0.3)
	var s := Court.team_sign(team)
	position.z = s * clampf(absf(position.z), 0.45, Court.HALF_L - 0.35)


## Backswing pose shown the moment the player touches HIT, so input feels instant.
func ready_swing() -> void:
	if _swing and _swing.is_valid():
		_swing.kill()
	_swing = create_tween()
	_swing.tween_property(_pivot, "rotation:y", 1.4, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func swing() -> void:
	swing_count += 1
	if _swing and _swing.is_valid():
		_swing.kill()
	_swing = create_tween()
	_swing.tween_property(_pivot, "rotation:y", -1.5, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing.tween_property(_pivot, "rotation:y", 0.35, 0.3)


func _process(_delta: float) -> void:
	if _body:
		var run := clampf(vel.length() / speed, 0.0, 1.0)
		_body.rotation.x = -0.18 * run
		_body.position.y = absf(sin(Time.get_ticks_msec() * 0.018)) * 0.05 * run


# --- visuals ------------------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c)
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var navy := Color("1b2a4a")
	for x: float in [-0.1, 0.1]:
		_part(_body, _capsule(0.075, 0.8), Vector3(x, 0.4, 0), skin)
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.12, 0.08, 0.24)
		_part(_body, shoe, Vector3(x, 0.04, -0.04), Color.WHITE)
	var shorts := CylinderMesh.new()
	shorts.top_radius = 0.2
	shorts.bottom_radius = 0.21
	shorts.height = 0.28
	_part(_body, shorts, Vector3(0, 0.82, 0), navy)
	_part(_body, _capsule(0.21, 0.72), Vector3(0, 1.2, 0), shirt)
	_part(_body, _sphere(0.13), Vector3(0, 1.7, 0), skin)
	_part(_body, _sphere(0.135), Vector3(0, 1.75, 0.03), hair)
	# off arm
	var arm := _part(_body, _capsule(0.055, 0.55), Vector3(-0.27, 1.2, 0), skin)
	arm.rotation.z = -0.25

	# paddle on the forehand side, swung from the shoulder
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.24, 1.38, 0)
	_pivot.rotation.y = 0.35
	_body.add_child(_pivot)
	var forearm := _part(_pivot, _capsule(0.055, 0.55), Vector3(0.22, -0.12, 0), skin)
	forearm.rotation.z = PI * 0.5 + 0.4
	var handle := BoxMesh.new()
	handle.size = Vector3(0.18, 0.035, 0.035)
	_part(_pivot, handle, Vector3(0.52, -0.22, 0), Color("1a1d22"))
	var face := CylinderMesh.new()
	face.top_radius = 0.19
	face.bottom_radius = 0.19
	face.height = 0.035
	var paddle := _part(_pivot, face, Vector3(0.78, -0.22, 0), Color("1a1d22"))
	paddle.rotation.z = PI * 0.5
	var rim := CylinderMesh.new()
	rim.top_radius = 0.2
	rim.bottom_radius = 0.2
	rim.height = 0.02
	var trim := _part(_pivot, rim, Vector3(0.78, -0.22, 0), Color("c6f432") if team == 0 else Color("7b5cd6"))
	trim.rotation.z = PI * 0.5

	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, 2.15, 0)
	_tag.font_size = 48
	_tag.pixel_size = 0.004
	_tag.outline_size = 10
	_tag.modulate = Color(1, 1, 1, 0.85)
	_tag.no_depth_test = true
	add_child(_tag)
	set_tag("" if is_human else display_name)


## Floating name above the player; "" hides it (your own player has none).
func set_tag(text: String) -> void:
	if _tag:
		_tag.text = text
		_tag.visible = text != ""
