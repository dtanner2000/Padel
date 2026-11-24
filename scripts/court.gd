class_name Court
extends Node3D
## Court dimensions, wall surface lookup and procedural geometry.
## World axes: x = across the court (width), z = along it (length), y = up.
## Team 0 (you + Ana) owns z > 0, nearest the camera. Team 1 owns z < 0.

const HALF_W := 5.0           # 10 m wide
const HALF_L := 10.0          # 20 m long
const SERVICE_Z := 6.95       # service line distance from the net
const NET_H_CENTRE := 0.88
const NET_H_POST := 0.92
const GLASS_H := 3.0          # back glass height
const WALL_TOP := 4.0         # glass + mesh above it
const SIDE_GLASS_LEN := 4.0   # side glass runs 4 m out from each back wall
const SIDE_MESH_H := 3.0      # mesh fence height along the middle of the sides

const COURT_BLUE := Color("1d64a6")
const APRON := Color("13263d")
const LINE := Color("ffffff")
const FRAME := Color("2c3846")


static func net_height(x: float) -> float:
	return lerpf(NET_H_CENTRE, NET_H_POST, clampf(absf(x) / HALF_W, 0.0, 1.0))


## Which team's half a z position is in.
static func side_of(z: float) -> int:
	return 0 if z > 0.0 else 1


## Sign of z for a team's half.
static func team_sign(team: int) -> float:
	return 1.0 if team == 0 else -1.0


## Surface of a back wall at height y: "glass", "mesh" or "" (open air, out).
static func back_wall_surface(y: float) -> String:
	if y < GLASS_H:
		return "glass"
	if y < WALL_TOP:
		return "mesh"
	return ""


## Surface of a side wall at height y and length position z.
static func side_wall_surface(y: float, z: float) -> String:
	if absf(z) > HALF_L - SIDE_GLASS_LEN:
		if y < GLASS_H:
			return "glass"
		if y < WALL_TOP:
			return "mesh"
		return ""
	if y < SIDE_MESH_H:
		return "mesh"
	return ""


var _back_glass: Array[MeshInstance3D] = [null, null]
var _back_frame: Array[Node3D] = [null, null]
var _glass: Material
var _near_glass: Material
var _turf: StandardMaterial3D
var _apron: StandardMaterial3D
var _lamps: Array[OmniLight3D] = []


func _ready() -> void:
	_build_floor()
	_build_lines()
	_build_net()
	_build_walls()
	_build_lights()
	set_viewer_end(0)


# --- geometry -----------------------------------------------------------------

func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_floor() -> void:
	_apron = _mat(APRON)
	_box(Vector3(18.0, 0.02, 30.0), Vector3(0, -0.02, 0), _apron)
	var turf := _mat(COURT_BLUE)
	turf.roughness = 1.0
	_turf = turf
	_box(Vector3(HALF_W * 2.0, 0.02, HALF_L * 2.0), Vector3(0, -0.005, 0), turf)


func _build_lines() -> void:
	var m := _mat(LINE, true)
	var w := 0.05
	var h := 0.004
	for s: float in [-1.0, 1.0]:
		_box(Vector3(HALF_W * 2.0, h, w), Vector3(0, 0.008, s * (HALF_L - w * 0.5)), m, false)
		_box(Vector3(HALF_W * 2.0, h, w), Vector3(0, 0.008, s * SERVICE_Z), m, false)
	_box(Vector3(w, h, SERVICE_Z * 2.0 + 0.4), Vector3(0, 0.008, 0), m, false)


func _build_net() -> void:
	var mesh_tex := _mesh_texture(Color(0.92, 0.95, 1.0, 0.75), 6)
	var net_mat := _mat(Color(1, 1, 1, 1))
	net_mat.albedo_texture = mesh_tex
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	net_mat.uv1_scale = Vector3(30, 3, 1)
	_box(Vector3(HALF_W * 2.0, NET_H_CENTRE, 0.01), Vector3(0, NET_H_CENTRE * 0.5, 0), net_mat, false)
	_box(Vector3(HALF_W * 2.0, 0.06, 0.03), Vector3(0, NET_H_CENTRE, 0), _mat(LINE), true)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.08, NET_H_POST + 0.05, 0.08), Vector3(s * (HALF_W + 0.04), (NET_H_POST + 0.05) * 0.5, 0), _mat(FRAME))


func _build_walls() -> void:
	var glass := _mat(Color(0.8, 0.92, 1.0, 0.12))
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var fence := _mat(Color(1, 1, 1, 1))
	fence.albedo_texture = _mesh_texture(Color(0.62, 0.7, 0.78, 0.7), 8)
	fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence.uv1_scale = Vector3(14, 5, 1)
	var frame := _mat(FRAME)
	var near_glass := _mat(Color(0.8, 0.92, 1.0, 0.05))

	_glass = glass
	_near_glass = near_glass
	for s: float in [-1.0, 1.0]:
		# back wall: glass, mesh above. The wall behind the camera sits between
		# the viewer and the action, so set_viewer_end() fades it and hides its frame.
		var end := 0 if s > 0.0 else 1
		_back_glass[end] = _box(Vector3(HALF_W * 2.0, GLASS_H, 0.03), Vector3(0, GLASS_H * 0.5, s * HALF_L), glass, false)
		var frame_group := Node3D.new()
		add_child(frame_group)
		_back_frame[end] = frame_group
		for part: MeshInstance3D in [
			_box(Vector3(HALF_W * 2.0, WALL_TOP - GLASS_H, 0.01), Vector3(0, (GLASS_H + WALL_TOP) * 0.5, s * HALF_L), fence, false),
			_box(Vector3(HALF_W * 2.0, 0.05, 0.05), Vector3(0, WALL_TOP, s * (HALF_L + 0.03)), frame),
		]:
			part.reparent(frame_group)
		for x: float in [-HALF_W, -HALF_W * 0.5, 0.0, HALF_W * 0.5, HALF_W]:
			_box(Vector3(0.06, WALL_TOP, 0.06), Vector3(x, WALL_TOP * 0.5, s * (HALF_L + 0.03)), frame).reparent(frame_group)
		# side walls
		for sx: float in [-1.0, 1.0]:
			var zc := s * (HALF_L - SIDE_GLASS_LEN * 0.5)
			_box(Vector3(0.03, GLASS_H, SIDE_GLASS_LEN), Vector3(sx * HALF_W, GLASS_H * 0.5, zc), glass, false)
			_box(Vector3(0.01, WALL_TOP - GLASS_H, SIDE_GLASS_LEN), Vector3(sx * HALF_W, (GLASS_H + WALL_TOP) * 0.5, zc), fence, false)
			for z: float in [HALF_L - SIDE_GLASS_LEN, HALF_L - SIDE_GLASS_LEN * 0.5]:
				_box(Vector3(0.06, WALL_TOP, 0.06), Vector3(sx * (HALF_W + 0.03), WALL_TOP * 0.5, s * z), frame)
	# middle mesh sections of the side walls
	var mid_len := (HALF_L - SIDE_GLASS_LEN) * 2.0
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.01, SIDE_MESH_H, mid_len), Vector3(sx * HALF_W, SIDE_MESH_H * 0.5, 0), fence, false)
		for z: float in [-3.0, 0.0, 3.0]:
			_box(Vector3(0.05, SIDE_MESH_H, 0.05), Vector3(sx * (HALF_W + 0.03), SIDE_MESH_H * 0.5, z), frame)


## Fade the back wall at the viewer's end (team 0 = near end, 1 = far end).
func set_viewer_end(team: int) -> void:
	for end in 2:
		var behind := end == team
		_back_glass[end].material_override = _near_glass if behind else _glass
		_back_frame[end].visible = not behind


func _build_lights() -> void:
	var lamp := _mat(Color("fff4d2"), true)
	var pole := _mat(FRAME)
	for sx: float in [-1.0, 1.0]:
		for z: float in [-6.0, 6.0]:
			_box(Vector3(0.1, 6.5, 0.1), Vector3(sx * 5.8, 3.25, z), pole)
			_box(Vector3(0.9, 0.12, 0.4), Vector3(sx * 5.5, 6.5, z), lamp, false)
			var l := OmniLight3D.new()
			l.position = Vector3(sx * 5.0, 6.2, z)
			l.omni_range = 11.0
			l.light_energy = 0.28
			l.light_color = Color("fff4d2")
			add_child(l)
			_lamps.append(l)


## A career venue's look: court and surround colours, floodlight strength.
func apply_venue(v: Dictionary) -> void:
	_turf.albedo_color = v.court
	_apron.albedo_color = v.apron
	for l in _lamps:
		l.light_energy = v.lamps
		l.visible = v.lamps > 0.0


## Small tiling diamond-mesh texture used for the fence and net.
func _mesh_texture(color: Color, cell: int) -> ImageTexture:
	var n := cell * 4
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		img.set_pixel(i, i, color)
		img.set_pixel(n - 1 - i, i, color)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
