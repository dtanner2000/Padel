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
var style := ""            # Roster style: "Power" | "Touch" | "Speed" | "All-rounder"
var _ring: MeshInstance3D  # team colour at the feet (the character kits are baked in)

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
var _grip: Node3D           # the paddle, held in the hand
var _fist: MeshInstance3D   # closed fingers round the handle (character models only)
var _face: MeshInstance3D   # paddle head
var _edge: MeshInstance3D   # paddle rim
const FIST_Y := 0.045       # where the hand closes on the handle, from the grip origin
const PALM := 0.06          # wrist bone -> centre of the (shrunk) palm, along the forearm
const HAND_SHRINK := 0.55   # the model's open paddle hand, tucked inside the fist
var _off_hand: Node3D
var _knee_l: Node3D
var _knee_r: Node3D

# optional skinned character model (Higgsfield/Meshy GLB): the procedural rig
# above becomes an invisible driver, and the model's bones are aimed at it
var _model: Node3D
var _skel: Skeleton3D
var _bones := {}            # name -> index
const MODEL_BONES := ["Spine01", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
var _run_phase := 0.0
var _swinging := false
var replaying := false     # a replay is posing the rig: skip the live animation
var celebrate_kind := ""   # "" | "jump" | "pump" | "five" | "sad": after a big point
var _celeb_t := 0.0
var _celeb_yaw := 0.0
var _meet: Variant = null   # Vector3: jog here first (partners come together), then celebrate
var _band_off: MeshInstance3D   # second sweatband, on the free wrist
var _hat: Node3D           # cosmetic headwear, on the model's head bone
var _band: MeshInstance3D  # cosmetic wristband on the paddle arm
var _hat_holder: Node3D
var _clip_mats: Array[ShaderMaterial] = []   # cap on: character materials that hide the hair under it
const CLIP_SHADER := preload("res://shaders/character_clip.gdshader")

# Paddle-arm poses, written as where the upper arm and the forearm point, in
# the player's own frame: +x = out to the paddle side, +y = up, -z = forwards
# (towards the net). _arm_pose() turns each into a shoulder rotation plus an
# elbow bend, so the elbow only ever bends the way a real one does.
static var POSE_READY := _arm_pose(Vector3(0.3, -1, -0.15), Vector3(-0.1, 0.25, -1))       # forearm forwards at the waist
static var POSE_BACK := _arm_pose(Vector3(0.85, -0.55, 0.45), Vector3(0.55, 0.15, 0.8))     # forehand take-back, out to the side
static var POSE_THROUGH := _arm_pose(Vector3(-0.25, -0.45, -1), Vector3(-1, 0.35, -0.2))     # follow-through across the front
static var POSE_SLICE_BACK := _arm_pose(Vector3(0.8, -0.1, 0.5), Vector3(0.3, 0.75, 0.6))   # high take-back
static var POSE_SLICE_THROUGH := _arm_pose(Vector3(-0.1, -0.8, -0.7), Vector3(-0.9, -0.35, -0.5))   # cuts down and across
static var POSE_UP := _arm_pose(Vector3(0.45, 1, 0.1), Vector3(-0.25, -0.35, 0.9))          # elbow high, paddle cocked behind the head
static var POSE_OVER := _arm_pose(Vector3(0.05, -0.55, -1), Vector3(-0.4, -0.75, -0.55))    # overhead follow-through
static var POSE_UNDER_BACK := _arm_pose(Vector3(0.35, -0.85, 0.55), Vector3(0.25, -0.55, 0.85))
static var POSE_UNDER_THROUGH := _arm_pose(Vector3(0.15, -0.15, -1), Vector3(0, 0.55, -1))
# celebrations
static var POSE_CHEER := _arm_pose(Vector3(0.3, 1, 0.05), Vector3(0.1, 1, -0.15))          # paddle straight up
static var POSE_PUMP_LOW := _arm_pose(Vector3(0.45, -0.25, -0.85), Vector3(0.05, 1, -0.25))  # fist cocked at the shoulder
static var POSE_PUMP_HIGH := _arm_pose(Vector3(0.35, 0.95, -0.3), Vector3(0.15, 1, -0.15))
static var POSE_FIVE := _arm_pose(Vector3(0.05, 1, -0.6), Vector3(-0.1, 1, -0.45))         # reaching up and forward
static var POSE_HANG := _arm_pose(Vector3(0.15, -1, 0.05), Vector3(0.05, -1, -0.3))         # arm hanging, paddle down


## [shoulder Quaternion, elbow bend] that points the upper arm along `upper`
## and the forearm along `fore`. The rig's arm hangs along -y and the elbow
## bends about the shoulder's x axis (positive = forearm towards the shoulder's
## -z), so the shoulder is turned to put `fore` in that bending plane.
static func _arm_pose(upper: Vector3, fore: Vector3) -> Array:
	var u := upper.normalized()
	var f := fore.normalized()
	var y := -u
	var perp := f - u * f.dot(u)
	if perp.length() < 0.05:
		perp = Vector3(0, 0, -1) - u * -u.z      # straight arm: any plane will do
	var z := -perp.normalized()
	var x := y.cross(z).normalized()
	var bend := acos(clampf(u.dot(f), -1.0, 1.0))
	return [Basis(x, y, z).orthonormalized().get_rotation_quaternion(), bend]


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
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34
	tm.outer_radius = 0.42
	tm.rings = 24
	_ring.mesh = tm
	_ring.scale = Vector3(1, 0.03, 1)
	_ring.position.y = 0.015
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.16, 0.55) if team == 0 else Color(0.6, 0.45, 1.0, 0.55)
	_ring.material_override = m
	_ring_mat = m
	_ring_col = m.albedo_color
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## The pose of the whole rig, for replays (see apply_rig_state).
func rig_state() -> Array:
	return [position, rotation.y, _body.rotation.x, _body.position.y, _hip_l.rotation.x, _hip_r.rotation.x,
		_off_shoulder.rotation.x, _torso.rotation.y, _shoulder.quaternion, _elbow.rotation.x, visible,
		_knee_l.rotation.x, _knee_r.rotation.x, _hip_l.rotation.z, _hip_r.rotation.z, _body.rotation.z]


func apply_rig_state(a: Array) -> void:
	position = a[0]
	rotation.y = a[1]
	_body.rotation.x = a[2]
	_body.position.y = a[3]
	_hip_l.rotation.x = a[4]
	_hip_r.rotation.x = a[5]
	_off_shoulder.rotation.x = a[6]
	_torso.rotation.y = a[7]
	_shoulder.quaternion = a[8]
	_elbow.rotation.x = a[9]
	visible = a[10]
	_knee_l.rotation.x = a[11]
	_knee_r.rotation.x = a[12]
	_hip_l.rotation.z = a[13]
	_hip_r.rotation.z = a[14]
	_body.rotation.z = a[15]


## Cosmetics: headwear ("" | "headband" | "cap" | "visor") and wristband colour
## (transparent = none). Needs a character model (attached to its head bone).
func set_cosmetics(hat: String, hat_col: Color, band_col: Color, kit_col := Color(0, 0, 0, 0), kit_key := {}) -> void:
	if _skel == null:
		return
	_kit_col = kit_col
	_kit_key = kit_key
	if _hat:
		_hat.queue_free()
		_hat = null
	if hat != "":
		var att := BoneAttachment3D.new()
		att.bone_name = "Head"
		_skel.add_child(att)
		_hat = att
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * 100.0   # the skeleton is in centimetres
		att.add_child(holder)
		_hat_holder = holder
		var m := StandardMaterial3D.new()
		m.albedo_color = hat_col
		m.roughness = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var add := func(mesh: Mesh, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = m
			mi.position = pos
			mi.rotation = rot
			mi.scale = scl
			holder.add_child(mi)
		var ring := CylinderMesh.new()
		ring.top_radius = 0.098
		ring.bottom_radius = 0.1
		ring.height = 0.035
		ring.radial_segments = 16
		match hat:
			"headband":
				add.call(ring, Vector3(0, 0.2, 0.0), Vector3(-0.2, 0, 0), Vector3(1.0, 1.0, 1.12))
			"bandana":
				# a deeper band tied at the back, two tails hanging down
				var deep := CylinderMesh.new()
				deep.top_radius = 0.097
				deep.bottom_radius = 0.101
				deep.height = 0.055
				deep.radial_segments = 16
				add.call(deep, Vector3(0, 0.205, 0.0), Vector3(-0.2, 0, 0), Vector3(1.0, 1.0, 1.12))
				var knot := SphereMesh.new()
				knot.radius = 0.022
				knot.height = 0.036
				add.call(knot, Vector3(0, 0.215, -0.118))
				var tail := BoxMesh.new()
				tail.size = Vector3(0.03, 0.12, 0.006)
				add.call(tail, Vector3(-0.022, 0.16, -0.13), Vector3(0.35, 0, 0.25))
				add.call(tail, Vector3(0.024, 0.15, -0.128), Vector3(0.3, 0, -0.18))
			"visor":
				add.call(ring, Vector3(0, 0.2, 0.0), Vector3(-0.2, 0, 0), Vector3(1.0, 1.0, 1.12))
				var peak := CylinderMesh.new()
				peak.top_radius = 0.08
				peak.bottom_radius = 0.08
				peak.height = 0.01
				add.call(peak, Vector3(0, 0.205, 0.12), Vector3(-0.3, 0, 0), Vector3(1.1, 1.0, 1.0))
			"cap":
				# crown: a full-height dome sitting low enough to cover the hair,
				# tipped forward so the front edge meets the forehead
				var dome := SphereMesh.new()
				dome.radius = CAP_R.x
				dome.height = 0.125
				dome.is_hemisphere = true
				dome.radial_segments = 28
				dome.rings = 10
				add.call(dome, Vector3(0, CAP_BASE, 0.012), Vector3(CAP_TILT, 0, 0), Vector3(1.0, 1.0, CAP_R.y / CAP_R.x))
				var button := SphereMesh.new()
				button.radius = 0.009
				button.height = 0.012
				add.call(button, Vector3(0, CAP_BASE + 0.121, -0.03))
				var brim := MeshInstance3D.new()
				brim.mesh = _cap_brim()
				brim.position = Vector3(0, CAP_BASE - 0.004, 0.014)
				brim.rotation.x = CAP_TILT
				brim.material_override = m
				holder.add_child(brim)
	_set_hair_clip(hat == "cap")
	if _band == null:
		var bm := CylinderMesh.new()
		bm.top_radius = 0.045
		bm.bottom_radius = 0.048
		bm.height = 0.06
		_band = _part(_grip, bm, Vector3(0, -0.06, 0), Color.BLACK)
		_band.top_level = true
		_band_off = _part(_grip, bm, Vector3(0, -0.06, 0), Color.BLACK)
		_band_off.top_level = true
	for b in [_band, _band_off]:
		b.visible = band_col.a > 0.0
		(b.material_override as StandardMaterial3D).albedo_color = band_col


## Cap on and/or a kit colour: draw the character with the shader material
## (hides the hair under a snug cap; repaints the shirt). Neither: the
## imported material.
var _kit_col := Color(0, 0, 0, 0)
var _kit_key := {}


func _set_hair_clip(on: bool) -> void:
	_clip_mats.clear()
	var kit := _kit_col.a > 0.0 and not _kit_key.is_empty()
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if _hat and _hat.is_ancestor_of(mi):
			continue   # the cap itself
		if not on and not kit:
			mi.material_override = null
			continue
		mi.material_override = null
		var src := mi.get_active_material(0) as BaseMaterial3D
		if src == null:
			continue
		var sm := ShaderMaterial.new()
		sm.shader = CLIP_SHADER
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("albedo_col", src.albedo_color)
		sm.set_shader_parameter("roughness_v", src.roughness)
		sm.set_shader_parameter("clip_on", on)
		if kit:
			sm.set_shader_parameter("kit_on", true)
			sm.set_shader_parameter("kit_col", _kit_col)
			sm.set_shader_parameter("key_hue", _kit_key.hue)
			sm.set_shader_parameter("key_hue_w", _kit_key.hue_w)
			sm.set_shader_parameter("key_sat", _kit_key.sat)
			sm.set_shader_parameter("key_val", _kit_key.val)
		mi.material_override = sm
		if on:
			_clip_mats.append(sm)


## Keep the hair clip on the cap's rim as the head moves.
func _update_hair_clip() -> void:
	if _clip_mats.is_empty() or _hat_holder == null:
		return
	var g := _hat_holder.global_transform
	var tilt := Basis(Vector3.RIGHT, CAP_TILT)
	var centre := g * Vector3(0, CAP_BASE, 0.012)
	var up := (g.basis * (tilt * Vector3.UP)).normalized()
	for sm in _clip_mats:
		sm.set_shader_parameter("clip_centre", centre)
		sm.set_shader_parameter("clip_normal", up)


const CAP_TILT := -0.26
const CAP_BASE := 0.14
const CAP_R := Vector2(0.106, 0.12)   # crown rim radii (x across, z front-back): hugs the head    # cap crown rim height above the head bone (m)


## A cap peak: the front half of a ring, longest at the front, tapering to the
## sides and curving down at the edges like a worn-in brim. Double-sided.
static func _cap_brim() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 18
	var inner := CAP_R   # crown rim (x, z radii)
	var pts: Array = []
	for i in n + 1:
		var a := lerpf(-PI * 0.42, PI * 0.42, float(i) / n)   # around the front only
		var s := sin(a)
		var c := cos(a)
		var length := 0.088 * pow(c, 1.2)                     # longest straight ahead
		var droop := -0.03 * s * s                             # edges curl down
		var p_in := Vector3(s * inner.x, 0.0, c * inner.y)
		var p_out := Vector3(s * (inner.x + length * 0.15), droop - 0.012 * c, c * (inner.y + length))
		pts.append([p_in, p_out])
	for i in n:
		var a0: Array = pts[i]
		var a1: Array = pts[i + 1]
		for tri in [[a0[0], a0[1], a1[1]], [a0[0], a1[1], a1[0]]]:
			for v in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Rename (tag over the head for everyone but your own player).
func set_display_name(n: String) -> void:
	display_name = n
	set_tag("" if is_human else n)


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


# --- celebrations ----------------------------------------------------------------

## kind: "jump" | "pump" | "five" (turn to `face` and reach for a high five,
## then jump) | "sad" (the losing side: shoulders down). face: world point.
func celebrate(kind: String, face: Variant = null, meet: Variant = null) -> void:
	celebrate_kind = kind
	_tag.visible = false             # the camera comes in close: no name tags
	_celeb_t = randf() * 0.25        # partners don't move in perfect lockstep
	if _swing and _swing.is_valid():
		_swing.kill()
	_swinging = false
	vel = Vector3.ZERO
	_celeb_yaw = rotation.y
	_meet = meet
	_face_pt = face
	_aim_face()


var _face_pt: Variant = null
var _ring_mat: StandardMaterial3D
var _ring_col := Color.WHITE
var _flash_t := 0.0


## "This one's you": the ring at your feet pulses bright lime for a moment.
func flash_ring(secs := 1.4) -> void:
	_flash_t = secs


func _tick_ring(delta: float) -> void:
	if _ring_mat == null:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
		var pulse := 0.5 + 0.5 * sin(_flash_t * 14.0)
		_ring_mat.albedo_color = Color(0.78, 0.96, 0.2, 0.95).lerp(Color(1, 1, 1, 1), pulse * 0.6)
		var sc := 1.0 + 0.35 * pulse * clampf(_flash_t / 0.3, 0.0, 1.0)
		_ring.scale = Vector3(sc, 0.03, sc)
	elif _ring.scale.x != 1.0:
		_ring_mat.albedo_color = _ring_col
		_ring.scale = Vector3(1, 0.03, 1)


func _aim_face() -> void:
	if _face_pt is Vector3:
		var d: Vector3 = (_face_pt as Vector3) - position
		if Vector2(d.x, d.z).length() > 0.05:
			_celeb_yaw = atan2(-d.x, -d.z)


func stop_celebrating() -> void:
	if celebrate_kind == "":
		return
	celebrate_kind = ""
	_meet = null
	_tag.visible = true
	_body.position.y = 0.0
	_body.rotation = Vector3.ZERO
	_off_shoulder.rotation = Vector3(0.1, 0, -0.25)
	_shoulder.quaternion = POSE_READY[0]
	_elbow.rotation.x = POSE_READY[1]


func _arm_to(pose: Array, delta: float, rate := 12.0) -> void:
	var k := 1.0 - exp(-rate * delta)
	_shoulder.quaternion = _shoulder.quaternion.slerp(pose[0], k)
	_elbow.rotation.x = lerpf(_elbow.rotation.x, pose[1], k)


func _legs(hip: float, knee: float, spread := 0.07) -> void:
	_hip_l.rotation = Vector3(hip, 0.0, -spread)
	_hip_r.rotation = Vector3(hip, 0.0, spread)
	_knee_l.rotation.x = knee
	_knee_r.rotation.x = knee


func _celebrate_tick(delta: float) -> void:
	_celeb_t += delta
	var t := _celeb_t
	rotation.y = lerp_angle(rotation.y, _celeb_yaw, 1.0 - exp(-7.0 * delta))
	var kind := celebrate_kind
	if kind == "five" and t > 1.25:
		kind = "jump"
	var off_k := 1.0 - exp(-10.0 * delta)
	match kind:
		"jump":
			# bounce on the spot, paddle and free arm up
			var ph := fposmod(t, 0.62) / 0.62
			var air := sin(clampf(ph / 0.72, 0.0, 1.0) * PI) if ph < 0.72 else 0.0
			var land := sin(clampf((ph - 0.72) / 0.28, 0.0, 1.0) * PI) if ph >= 0.72 else 0.0
			_body.position.y = 0.3 * air - 0.08 * land
			_body.rotation.x = 0.06 * air
			_legs(0.2 + 0.5 * air + 0.3 * land, -0.35 - 0.9 * air - 0.6 * land)
			_arm_to(POSE_CHEER, delta, 14.0)
			_off_shoulder.rotation = _off_shoulder.rotation.lerp(Vector3(2.85, 0, -0.35), off_k)
		"pump":
			# feet planted, a big double fist pump
			var pump := 0.5 + 0.5 * sin(t * TAU * 1.7)
			_body.position.y = -0.06
			_body.rotation.x = -0.12 * pump + 0.04
			_legs(0.35, -0.7, 0.1)
			_arm_to(POSE_PUMP_HIGH if pump > 0.5 else POSE_PUMP_LOW, delta, 16.0)
			_off_shoulder.rotation = _off_shoulder.rotation.lerp(Vector3(lerpf(2.0, 2.9, pump), 0, -0.3), off_k)
		"five":
			# turn to your partner and reach up; a little hop on the slap
			var hop := maxf(0.0, sin(clampf((t - 0.55) / 0.35, 0.0, 1.0) * PI))
			_body.position.y = 0.16 * hop
			_legs(0.25 + 0.3 * hop, -0.45 - 0.5 * hop)
			_arm_to(POSE_FIVE, delta, 10.0)
			_off_shoulder.rotation = _off_shoulder.rotation.lerp(Vector3(0.9, 0, -0.3), off_k)
		"sad":
			# head down, paddle hanging, a slow shake of the head (body sway)
			_body.position.y = lerpf(_body.position.y, -0.03, off_k)
			_body.rotation.x = lerpf(_body.rotation.x, -0.3, off_k * 0.5)
			_body.rotation.z = 0.05 * sin(t * 1.3)
			_legs(0.12, -0.25, 0.05)
			_arm_to(POSE_HANG, delta, 5.0)
			_off_shoulder.rotation = _off_shoulder.rotation.lerp(Vector3(-0.05, 0, -0.08), off_k * 0.5)
	_torso.rotation.y = lerpf(_torso.rotation.y, 0.0, off_k)


# --- swings -------------------------------------------------------------------

func _pose_tween(t: Tween, pose: Array, secs: float, trans := Tween.TRANS_QUAD, ease := Tween.EASE_OUT) -> void:
	t.tween_property(_shoulder, "quaternion", pose[0], secs).set_trans(trans).set_ease(ease)   # slerps
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
		"smash", "power_smash", "bandeja", "vibora":
			_pose_tween(t, POSE_UP, 0.07)
			_pose_tween(t, POSE_OVER, 0.12 if kind in ["smash", "power_smash"] else 0.16, Tween.TRANS_QUAD, Tween.EASE_IN)
		"serve", "lob", "contrapared":
			_pose_tween(t, POSE_UNDER_BACK, 0.08)
			_pose_tween(t, POSE_UNDER_THROUGH, 0.16)
		_:
			# forehand; a slice cuts down through the ball with an open face
			if kind == "slice":
				_pose_tween(t, POSE_SLICE_BACK, 0.06)
				_pose_tween(t, POSE_SLICE_THROUGH, 0.13)
			else:
				_pose_tween(t, POSE_BACK, 0.06)
				_pose_tween(t, POSE_THROUGH, 0.11)
	_pose_tween(t, POSE_READY, 0.28, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: _swinging = false)


func _process(delta: float) -> void:
	if _body == null:
		return
	_tick_ring(delta)
	if replaying:
		if _skel:
			_drive_model()
		return
	if celebrate_kind != "":
		if _meet is Vector3:
			# jog in to your partner first, with the normal running legs
			move_towards(_meet, delta)
			_locomotion(delta)
			if Vector2(position.x - _meet.x, position.z - _meet.z).length() < 0.12:
				_meet = null
				vel = Vector3.ZERO
				_celeb_t = randf() * 0.25
				_aim_face()
		else:
			_celebrate_tick(delta)
		if _skel:
			_drive_model()
		return
	_locomotion(delta)
	if _skel:
		_drive_model()


func _locomotion(delta: float) -> void:
	var run := clampf(vel.length() / maxf(speed, 0.1), 0.0, 1.0)
	_run_phase += delta * (4.0 + 7.0 * run)
	var s := sin(_run_phase)
	# which way we're moving, in our own frame: forward/back strides, or the
	# side-on shuffle padel players use to move across the court
	var local_v := global_transform.basis.inverse() * vel
	var dir := Vector2(local_v.x, -local_v.z)
	var dn := dir / dir.length() if dir.length() > 0.3 else Vector2(0, 1)
	var fwd := dn.y
	var side := dn.x
	# lean into the run, bob, and an athletic crouch when still
	_body.rotation.x = -0.18 * run * fwd
	_body.rotation.z = 0.06 * run * side
	_body.position.y = absf(s) * 0.045 * run - 0.03 * (1.0 - run)
	# legs: the thigh swings with the stride; the knee folds as the leg comes
	# through (heel up behind), and stays soft when standing ready
	var c := cos(_run_phase)
	var stance_hip := 0.28 * (1.0 - run)      # thighs forward, knees bent: ready position
	var stance_knee := -0.55 * (1.0 - run)
	# side shuffle: the feet open and close together (never cross)
	var spread := absf(s) * 0.3 * run * absf(side) + 0.06 * (1.0 - run)
	_hip_l.rotation = Vector3(s * 0.62 * run * fwd + stance_hip, 0.0, -spread)
	_hip_r.rotation = Vector3(-s * 0.62 * run * fwd + stance_hip, 0.0, spread)
	_knee_l.rotation.x = stance_knee - run * (0.2 + 0.95 * maxf(0.0, c) * absf(fwd) + 0.35 * absf(side))
	_knee_r.rotation.x = stance_knee - run * (0.2 + 0.95 * maxf(0.0, -c) * absf(fwd) + 0.35 * absf(side))
	_off_shoulder.rotation.x = -s * 0.5 * run * fwd + 0.1
	# torso turns slightly towards the direction of travel
	_torso.rotation.y = lerpf(_torso.rotation.y, clampf(-local_v.x * 0.12, -0.35, 0.35), 1.0 - exp(-8.0 * delta))
	if not _swinging:
		# paddle arm breathes a little in the ready position
		_shoulder.quaternion = Quaternion(Vector3.RIGHT, sin(_run_phase * 0.5) * 0.04) * POSE_READY[0]


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
		var knee := _joint(hip, Vector3(0, -0.42, 0))
		_joint(knee, Vector3(0, -0.4, 0)).name = "Ankle"
		if side < 0.0:
			_hip_l = hip
			_knee_l = knee
		else:
			_hip_r = hip
			_knee_r = knee

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
	_off_shoulder.rotation = Vector3(0.1, 0, -0.25)
	_part(_off_shoulder, _capsule(0.06, 0.32), Vector3(0, -0.14, 0), shirt)   # sleeve
	var off_elbow := _joint(_off_shoulder, Vector3(0, -0.28, 0))
	off_elbow.rotation.x = 0.7      # forearm forwards (positive bends towards the front)
	_part(off_elbow, _capsule(0.05, 0.3), Vector3(0, -0.13, 0), skin)
	_off_hand = _joint(off_elbow, Vector3(0, -0.28, 0))

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
	_shoulder.quaternion = POSE_READY[0]
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
	_grip = grip
	# forearm runs forward-down in the ready pose; this bend stands the paddle up
	grip.rotation = Vector3(PI * 0.5 + 0.05, 0, -0.25)
	var dark := Color("1a1d22")
	var trim := Color("c6f432") if team == 0 else Color("7b5cd6")
	# closed fingers round the handle: hidden for the procedural body, shown (in the
	# model's own skin tone) when a character model is used, whose hands are open
	var fist := SphereMesh.new()
	fist.radius = 0.043
	fist.height = 0.11
	fist.radial_segments = 12
	fist.rings = 6
	_fist = _part(grip, fist, Vector3(0, FIST_Y, 0), Color.WHITE)
	_fist.scale = Vector3(1.0, 1.0, 0.85)
	_fist.visible = false
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
	_face = face
	var rim := CylinderMesh.new()
	rim.top_radius = 0.142
	rim.bottom_radius = 0.142
	rim.height = 0.02
	rim.radial_segments = 20
	var edge := _part(grip, rim, Vector3(0, 0.33, 0), trim)
	edge.rotation.x = PI * 0.5
	edge.scale = Vector3(1.0, 1.0, 1.12)
	_edge = edge


## Paddle shape and colours: round (big sweet spot), teardrop, or diamond.
func set_paddle(shape: String, face_col: Color, trim_col: Color) -> void:
	if _face == null:
		await ready
	var segs := 6 if shape == "diamond" else 20
	var long: float = {"round": 1.06, "teardrop": 1.2, "diamond": 1.28}.get(shape, 1.1)
	var wide := 1.12 if shape == "diamond" else 1.0
	var y := 0.35 if shape != "round" else 0.33
	for part: MeshInstance3D in [_face, _edge]:
		var cm := (part.mesh as CylinderMesh).duplicate() as CylinderMesh
		cm.radial_segments = segs
		part.mesh = cm
		part.position.y = y
		# a 6-sided "cylinder" has a corner on the shaft line: stretched along the
		# shaft it is a diamond paddle with a point at the top
		part.basis = Basis(Vector3.RIGHT, PI * 0.5)
		part.scale = Vector3(wide, 1.0, long)
	(_face.material_override as StandardMaterial3D).albedo_color = face_col
	(_edge.material_override as StandardMaterial3D).albedo_color = trim_col


# --- skinned model ---------------------------------------------------------------

## Swap the procedural body for a rigged character (humanoid GLB, Meshy/Mixamo
## bone names, facing +Z as Meshy exports). The procedural joints keep
## animating, unseen, and drive the model's bones every frame.
func use_model(scene: PackedScene) -> void:
	if _body == null:
		await ready
	if _model:
		_model.queue_free()       # swapping characters
		_model = null
		_skel = null
		_bones.clear()
	_model = scene.instantiate()
	_model.rotation.y = PI          # Meshy faces +Z; players face -Z
	_body.add_child(_model)
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_warning("character model has no skeleton")
		return
	_skel = found[0]
	_skel.reset_bone_poses()       # every bone at rest: _aim_limb builds on the rest pose
	for b in MODEL_BONES:
		_bones[b] = _skel.find_bone(b)
	# hide the procedural body; keep the paddle and name tag
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		if not (_grip.is_ancestor_of(mi) or _model.is_ancestor_of(mi)):
			(mi as MeshInstance3D).visible = false
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var tone: Variant = _hand_tone()
	if tone != null:
		_fist.material_override = _mat(tone)
		_fist.visible = true
		# the model's hand is modelled open; shrink it so the fist reads as the grip
		var h := _skel.find_bone("RightHand")
		_skel.set_bone_pose_scale(h, _skel.get_bone_rest(h).basis.get_scale() * HAND_SHRINK)


## Average colour of the model's right hand (vertices mostly bound to
## RightHand, sampled from the albedo texture), so the closed fist matches the
## skin. null if it can't be read.
func _hand_tone() -> Variant:
	var hand := _skel.find_bone("RightHand")
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind := -1
		for b in mi.skin.get_bind_count():
			if mi.skin.get_bind_bone(b) == hand or mi.skin.get_bind_name(b) == &"RightHand":
				bind = b
		var mat := mi.get_active_material(0) as BaseMaterial3D
		if bind < 0 or mat == null or mat.albedo_texture == null:
			continue
		var img := mat.albedo_texture.get_image()
		if img == null:
			continue
		if img.is_compressed() and img.decompress() != OK:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		if uvs.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / uvs.size()
		var sum := Vector3.ZERO
		var count := 0
		for v in uvs.size():
			for k in per:
				if bones[v * per + k] == bind and weights[v * per + k] > 0.85:
					var uv := uvs[v]
					var c := img.get_pixel(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1),
						clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
					sum += Vector3(c.r, c.g, c.b)
					count += 1
		if count > 10:
			sum /= count
			return Color(sum.x, sum.y, sum.z) * mat.albedo_color
	return null


## Aim a two-bone limb (upper -> lower -> end) so the joint lands on `mid_world`
## and the end on `end_world`. Only bone ROTATIONS are written, each computed
## from the rest pose every frame, so nothing can accumulate: the skeleton's
## cached global poses are never read back (a stale cache on device once let
## position/scale errors build up until the arms stretched). Returns the end
## bone's skeleton-space position, or null if the bones are missing.
func _aim_limb(upper: String, lower: String, end: String, mid_world: Vector3, end_world: Vector3) -> Variant:
	var u: int = _bones.get(upper, -1)
	var l: int = _bones.get(lower, -1)
	var e: int = _bones.get(end, -1)
	if u < 0 or l < 0 or e < 0:
		return null
	var to_skel := _skel.global_transform.affine_inverse()
	var p := _skel.get_bone_parent(u)
	var parent_g := _skel.get_bone_global_rest(p) if p >= 0 else Transform3D()   # never driven
	var ug := _aim_one(u, l, parent_g, to_skel * mid_world)
	var lg := _aim_one(l, e, ug, to_skel * end_world)
	return lg * _skel.get_bone_rest(e).origin


## Rotate bone `i` (rest pose under `parent_g`) so it points at `target`
## (skeleton space); writes its local rotation and returns its new global pose.
func _aim_one(i: int, child: int, parent_g: Transform3D, target: Vector3) -> Transform3D:
	var rest := _skel.get_bone_rest(i)
	_skel.set_bone_pose_position(i, rest.origin)
	_skel.set_bone_pose_scale(i, rest.basis.get_scale())
	var g := parent_g * rest
	var along := (g.basis * _skel.get_bone_rest(child).origin).normalized()
	var want := (target - g.origin).normalized()
	if not (along.is_zero_approx() or want.is_zero_approx() or along.dot(want) > 0.99999):
		g.basis = Basis(Quaternion(along, want)) * g.basis
	var local := parent_g.affine_inverse() * g
	_skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	return g


func _drive_model() -> void:
	_update_hair_clip()
	var wrist: Variant = _aim_limb("RightArm", "RightForeArm", "RightHand", _elbow.global_position, _hand.global_position)
	var wrist_l: Variant = _aim_limb("LeftArm", "LeftForeArm", "LeftHand", _off_hand.get_parent_node_3d().global_position, _off_hand.global_position)
	if wrist_l != null and _band_off and _band_off.visible:
		var along_l := (_off_hand.global_position - _off_hand.get_parent_node_3d().global_position).normalized()
		_band_off.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, -along_l)), _skel.global_transform * (wrist_l as Vector3) - along_l * 0.04)
	_aim_limb("LeftUpLeg", "LeftLeg", "LeftFoot", _knee_l.global_position, _knee_l.get_node("Ankle").global_position)
	_aim_limb("RightUpLeg", "RightLeg", "RightFoot", _knee_r.global_position, _knee_r.get_node("Ankle").global_position)
	# the paddle sits in the model's real hand
	if wrist != null:
		var along := (_hand.global_position - _elbow.global_position).normalized()
		var basis := _paddle_basis(along)
		var palm := _skel.global_transform * (wrist as Vector3) + along * PALM
		_grip.global_basis = basis
		_grip.global_position = palm - basis.y * FIST_Y   # the handle runs through the palm
		if _band and _band.visible:
			var wrist_w := _skel.global_transform * (wrist as Vector3)
			_band.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, -along)), wrist_w - along * 0.04)


## World orientation for the held paddle: the shaft follows the forearm with the
## wrist cocked up (head up at the ready, straight up on a smash), and the face
## turns as square to the net as the shaft allows.
const WRIST_COCK := 1.0
func _paddle_basis(forearm: Vector3) -> Basis:
	var fwd := -_torso.global_basis.z
	var f := forearm
	var back := -f.dot(fwd)
	if back > 0.0:
		f += fwd * back            # never let the head lean back towards the camera
	var axis := (f + Vector3.UP * WRIST_COCK + fwd * 0.15).normalized()
	var face := fwd - axis * fwd.dot(axis)
	if face.length() < 0.15:
		face = _torso.global_basis.x.cross(axis)
	face = face.normalized()
	return Basis(axis.cross(face), axis, face)


## Floating name above the player; "" hides it (your own player has none).
func set_tag(text: String) -> void:
	if _tag:
		_tag.text = text
		_tag.visible = text != ""
