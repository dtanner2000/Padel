class_name Player
extends Node3D
## One of the four players. Movement and body animation; decisions live in main.gd.
##
## The body is a light procedural rig (no animation files): shoulder → elbow →
## hand chain holding the paddle, plus hips/legs that swing while running.
## Swings are short tweens on the arm joints: forehand around the body,
## overhead (smash/bandeja) over the head, underarm for the serve.

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
var last_swing := "drive"
var smash_charge := 0.0    # 0..1, people only (see main.gd)

var shirt := Color("f28c28")
var skin := Color("e3b48c")
var hair := Color("3a2a20")

# rig joints
var _body: Node3D          # everything above the feet; leans and bobs
var _torso: Node3D
var _shoulder: Node3D      # paddle arm
var _elbow: Node3D
var _hand: Node3D
var _off_shoulder: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _swing: Tween
var _tag: Label3D
var _run_phase := 0.0
var _swinging := false

# arm poses: [shoulder rot (x, y, z), elbow rot x]
const POSE_READY := [Vector3(-0.2, 0.25, 0.32), -1.25]
const POSE_BACK := [Vector3(-0.35, 1.35, 0.35), -0.85]
const POSE_THROUGH := [Vector3(-0.6, -1.45, 0.05), -0.55]
const POSE_UP := [Vector3(-2.75, 0.35, 0.15), -1.35]     # paddle cocked behind the head
const POSE_OVER := [Vector3(-0.35, -0.25, 0.05), -0.15]   # overhead follow-through
const POSE_UNDER_BACK := [Vector3(0.75, 0.2, 0.15), -0.25]
const POSE_UNDER_THROUGH := [Vector3(-1.2, -0.25, 0.1), -0.45]


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


# --- swings -------------------------------------------------------------------

func _pose_tween(t: Tween, pose: Array, secs: float, trans := Tween.TRANS_QUAD, ease := Tween.EASE_OUT) -> void:
	t.tween_property(_shoulder, "rotation", pose[0], secs).set_trans(trans).set_ease(ease)
	t.parallel().tween_property(_elbow, "rotation:x", pose[1], secs).set_trans(trans).set_ease(ease)


func _new_swing() -> Tween:
	if _swing and _swing.is_valid():
		_swing.kill()
	_swing = create_tween()
	_swinging = true
	return _swing


## Backswing the moment the player touches HIT, so input feels instant.
func ready_swing(overhead := false) -> void:
	var t := _new_swing()
	_pose_tween(t, POSE_UP if overhead else POSE_BACK, 0.09)
	t.tween_callback(func() -> void: _swinging = false)


## kind: drive | slice | lob | bandeja | smash | power_smash | serve | feed
func swing(kind := "drive") -> void:
	swing_count += 1
	last_swing = kind
	var t := _new_swing()
	match kind:
		"smash", "power_smash", "bandeja":
			_pose_tween(t, POSE_UP, 0.07)
			_pose_tween(t, POSE_OVER, 0.12 if kind != "bandeja" else 0.16, Tween.TRANS_QUAD, Tween.EASE_IN)
		"serve", "lob":
			_pose_tween(t, POSE_UNDER_BACK, 0.08)
			_pose_tween(t, POSE_UNDER_THROUGH, 0.16)
		_:
			# forehand; a slice cuts down through the ball with an open face
			if kind == "slice":
				_pose_tween(t, [POSE_BACK[0] + Vector3(-0.35, 0, 0), POSE_BACK[1]], 0.06)
				_pose_tween(t, [POSE_THROUGH[0] + Vector3(0.45, 0, 0), POSE_THROUGH[1]], 0.13)
			else:
				_pose_tween(t, POSE_BACK, 0.06)
				_pose_tween(t, POSE_THROUGH, 0.11)
	_pose_tween(t, POSE_READY, 0.28, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: _swinging = false)


func _process(delta: float) -> void:
	if _body == null:
		return
	var run := clampf(vel.length() / maxf(speed, 0.1), 0.0, 1.0)
	_run_phase += delta * (4.0 + 7.0 * run)
	var s := sin(_run_phase)
	# lean into the run, bob, and a slight split-step crouch when still
	_body.rotation.x = -0.2 * run
	_body.position.y = absf(s) * 0.05 * run - 0.04 * (1.0 - run)
	# legs and off arm swing with the stride
	_hip_l.rotation.x = s * 0.7 * run - 0.12 * (1.0 - run)
	_hip_r.rotation.x = -s * 0.7 * run - 0.12 * (1.0 - run)
	_off_shoulder.rotation.x = -s * 0.5 * run - 0.35
	# torso turns slightly towards the direction of travel
	var local_v := global_transform.basis.inverse() * vel
	_torso.rotation.y = lerpf(_torso.rotation.y, clampf(-local_v.x * 0.12, -0.35, 0.35), 1.0 - exp(-8.0 * delta))
	if not _swinging:
		# paddle arm breathes a little in the ready position
		_shoulder.rotation = POSE_READY[0] + Vector3(sin(_run_phase * 0.5) * 0.04, 0, 0)


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


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _build() -> void:
	var navy := Color("1b2a4a")
	_body = _joint(self, Vector3.ZERO)

	# legs: hip joints so they can swing; each leg hangs along -y
	for side: float in [-1.0, 1.0]:
		var hip := _joint(_body, Vector3(side * 0.1, 0.82, 0))
		_part(hip, _capsule(0.08, 0.5), Vector3(0, -0.2, 0), skin)          # thigh (shorts cover the top)
		_part(hip, _capsule(0.07, 0.48), Vector3(0, -0.55, 0), skin)         # shin
		var sock := CylinderMesh.new()
		sock.top_radius = 0.072
		sock.bottom_radius = 0.07
		sock.height = 0.1
		_part(hip, sock, Vector3(0, -0.72, 0), Color.WHITE)
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.12, 0.09, 0.27)
		_part(hip, shoe, Vector3(0, -0.78, -0.05), Color.WHITE)
		var sole := BoxMesh.new()
		sole.size = Vector3(0.125, 0.025, 0.28)
		_part(hip, sole, Vector3(0, -0.82, -0.05), shirt.darkened(0.1))
		if side < 0.0:
			_hip_l = hip
		else:
			_hip_r = hip

	_torso = _joint(_body, Vector3(0, 0.82, 0))
	var shorts := CylinderMesh.new()
	shorts.top_radius = 0.19
	shorts.bottom_radius = 0.22
	shorts.height = 0.3
	_part(_torso, shorts, Vector3(0, 0.0, 0), navy)
	var chest := _part(_torso, _capsule(0.21, 0.66), Vector3(0, 0.38, 0), shirt)
	chest.scale = Vector3(1.05, 1.0, 0.8)
	var collar := CylinderMesh.new()
	collar.top_radius = 0.06
	collar.bottom_radius = 0.07
	collar.height = 0.1
	_part(_torso, collar, Vector3(0, 0.72, 0), skin)
	_part(_torso, _sphere(0.125), Vector3(0, 0.88, 0), skin)
	var hair_cap := _part(_torso, _sphere(0.13), Vector3(0, 0.93, 0.025), hair)
	hair_cap.scale = Vector3(1.0, 0.75, 1.0)

	# off arm, relaxed and slightly forward for balance
	_off_shoulder = _joint(_torso, Vector3(-0.24, 0.6, 0))
	_off_shoulder.rotation = Vector3(-0.35, 0, -0.25)
	_part(_off_shoulder, _capsule(0.06, 0.32), Vector3(0, -0.14, 0), shirt)   # sleeve
	var off_elbow := _joint(_off_shoulder, Vector3(0, -0.28, 0))
	off_elbow.rotation.x = -0.6
	_part(off_elbow, _capsule(0.05, 0.3), Vector3(0, -0.13, 0), skin)

	# paddle arm: shoulder → elbow → hand, each segment hanging along -y
	_shoulder = _joint(_torso, Vector3(0.24, 0.6, 0))
	_part(_shoulder, _capsule(0.06, 0.32), Vector3(0, -0.14, 0), shirt)       # sleeve + upper arm
	_elbow = _joint(_shoulder, Vector3(0, -0.28, 0))
	_part(_elbow, _capsule(0.05, 0.3), Vector3(0, -0.13, 0), skin)
	var band := CylinderMesh.new()
	band.top_radius = 0.055
	band.bottom_radius = 0.055
	band.height = 0.05
	_part(_elbow, band, Vector3(0, -0.22, 0), Color("1a1d22"))              # sweatband
	_hand = _joint(_elbow, Vector3(0, -0.28, 0))
	_part(_hand, _sphere(0.045), Vector3.ZERO, skin)
	_build_paddle(_hand)
	_shoulder.rotation = POSE_READY[0]
	_elbow.rotation.x = POSE_READY[1]

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


## Paddle held in the hand: handle continues the forearm, then the grip
## bends the head up so the face points at the net in the ready position.
func _build_paddle(hand: Node3D) -> void:
	var grip := _joint(hand, Vector3.ZERO)
	# forearm runs forward-down in the ready pose; this bend stands the paddle up
	grip.rotation = Vector3(PI * 0.5 + 0.05, 0, -0.25)
	var dark := Color("1a1d22")
	var trim := Color("c6f432") if team == 0 else Color("7b5cd6")
	var handle := CylinderMesh.new()
	handle.top_radius = 0.018
	handle.bottom_radius = 0.02
	handle.height = 0.16
	_part(grip, handle, Vector3(0, 0.06, 0), dark)
	var throat := CylinderMesh.new()
	throat.top_radius = 0.06
	throat.bottom_radius = 0.025
	throat.height = 0.08
	_part(grip, throat, Vector3(0, 0.17, 0), dark)
	# head: a flattened, slightly tall disc, face normal along the grip's z
	var head := CylinderMesh.new()
	head.top_radius = 0.135
	head.bottom_radius = 0.135
	head.height = 0.032
	head.radial_segments = 20
	var face := _part(grip, head, Vector3(0, 0.33, 0), dark)
	face.rotation.x = PI * 0.5
	face.scale = Vector3(1.0, 1.0, 1.12)
	var rim := CylinderMesh.new()
	rim.top_radius = 0.142
	rim.bottom_radius = 0.142
	rim.height = 0.02
	rim.radial_segments = 20
	var edge := _part(grip, rim, Vector3(0, 0.33, 0), trim)
	edge.rotation.x = PI * 0.5
	edge.scale = Vector3(1.0, 1.0, 1.12)


## Floating name above the player; "" hides it (your own player has none).
func set_tag(text: String) -> void:
	if _tag:
		_tag.text = text
		_tag.visible = text != ""
