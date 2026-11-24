class_name Scenery
extends Node3D
## What surrounds the court at each venue: an indoor hall, a park, a beach at
## sunset, a packed arena, or a city rooftop. Low-poly and batched
## (MultiMesh) so it stays cheap on phones.

var kind := ""
var _crowd: MultiMeshInstance3D
var _crowd_base: Array[Transform3D] = []
var _cheer := 0.0


func build(k: String) -> void:
	if k == kind:
		return
	kind = k
	for c in get_children():
		c.queue_free()
	_crowd = null
	_crowd_base.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	match k:
		"hall": _hall()
		"park": _park(rng)
		"beach": _beach(rng)
		"arena": _arena(rng)
		"rooftop": _rooftop(rng)


## The crowd jumps after a big point (arena only).
func cheer(amount := 1.0) -> void:
	_cheer = maxf(_cheer, amount)


func _process(delta: float) -> void:
	if _crowd == null or _cheer <= 0.0:
		return
	_cheer = maxf(0.0, _cheer - delta * 0.8)
	var mm := _crowd.multimesh
	var t := Time.get_ticks_msec() / 1000.0
	for i in _crowd_base.size():
		var hop := absf(sin(t * 9.0 + i * 1.7)) * 0.25 * _cheer
		var tr := _crowd_base[i]
		tr.origin.y += hop
		mm.set_instance_transform(i, tr)


# --- helpers ----------------------------------------------------------------------

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, c: Color, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, unshaded)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Many copies of one mesh, each with its own transform and colour.
func _multi(mesh: Mesh, xforms: Array, colours: Array, unshaded := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colours[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := _mat(Color.WHITE, unshaded)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Seated spectators on a stepped stand: rows along x (or z) facing the court.
func _stand(rng: RandomNumberGenerator, centre: Vector3, along_x: bool, length: float, rows: int, facing: float, xf: Array, cols: Array) -> void:
	var step := Vector3(0, 0.55, 0.0)
	var back := Vector3(0, 0, -facing) if along_x else Vector3(-facing, 0, 0)
	for r in rows:
		var base := centre + back * (r * 0.8) + step * r
		_box(Vector3(length, 0.5, 0.8) if along_x else Vector3(0.8, 0.5, length), base + Vector3(0, 0.25, 0), Color("2a2f3a"))
		var n := int(length / 0.55)
		for i in n:
			if rng.randf() < 0.12:
				continue
			var off := -length * 0.5 + (i + 0.5) * length / n
			var p := base + (Vector3(off, 0.85, 0) if along_x else Vector3(0, 0.85, off))
			xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, rng.randf_range(0.9, 1.15), 1)), p))
			cols.append(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.55, 1.0)))


func _person_mesh() -> Mesh:
	var cm := CapsuleMesh.new()
	cm.radius = 0.17
	cm.height = 0.7
	cm.radial_segments = 6
	cm.rings = 2
	return cm


# --- venues -------------------------------------------------------------------------

func _hall() -> void:
	# indoor club: walls, roof and rows of ceiling lights
	var wall := Color("1b2433")
	_box(Vector3(30, 12, 0.3), Vector3(0, 6, -21), wall)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.3, 12, 44), Vector3(sx * 13.5, 6, 0), wall)
		_box(Vector3(0.05, 0.5, 30), Vector3(sx * 13.3, 1.4, 0), Color("4a5a1c"), true)   # club stripe
	_box(Vector3(30, 0.3, 44), Vector3(0, 12, 0), Color("10151f"))
	for z in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		for x in [-4.0, 4.0]:
			_box(Vector3(2.4, 0.08, 0.5), Vector3(x, 11.8, z), Color("fff6dd"), true)


func _park(rng: RandomNumberGenerator) -> void:
	_box(Vector3(120, 0.02, 120), Vector3(0, -0.06, 0), Color("4f8a3c"))
	var trunk_x: Array = []
	var crown_x: Array = []
	var tc: Array = []
	var cc: Array = []
	for i in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(16.0, 40.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r * 0.9)
		if p.z > 12.0 and absf(p.x) < 14.0:
			continue   # keep the camera's view clear
		var h := rng.randf_range(3.0, 6.0)
		trunk_x.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, h / 3.0, 1)), p + Vector3(0, h * 0.5, 0)))
		tc.append(Color("6b4a2f"))
		crown_x.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(1.6, 2.6)), p + Vector3(0, h + 0.6, 0)))
		cc.append(Color.from_hsv(rng.randf_range(0.22, 0.32), 0.55, rng.randf_range(0.35, 0.55)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.25
	trunk.height = 3.0
	trunk.radial_segments = 6
	_multi(trunk, trunk_x, tc)
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 1.8
	crown.radial_segments = 8
	crown.rings = 4
	_multi(crown, crown_x, cc)


func _beach(rng: RandomNumberGenerator) -> void:
	_box(Vector3(120, 0.02, 70), Vector3(0, -0.06, 5), Color("e2c48e"))      # sand
	_box(Vector3(220, 0.02, 120), Vector3(0, -0.2, -90), Color("2a6f9e"), true)   # sea
	_box(Vector3(220, 0.02, 1.5), Vector3(0, -0.04, -30.5), Color("f3ecdc"), true)  # surf line
	var sun := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 6.0
	sm.height = 12.0
	sun.mesh = sm
	sun.material_override = _mat(Color("ffd08a"), true)
	sun.position = Vector3(-18, 6, -140)
	add_child(sun)
	# palms: leaning trunks with a tuft of fronds
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * rng.randf_range(13.0, 24.0), 0, rng.randf_range(-26.0, 4.0))
		var lean := rng.randf_range(-0.25, 0.25)
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.14
		tm.bottom_radius = 0.24
		tm.height = 7.0
		tm.radial_segments = 6
		trunk.mesh = tm
		trunk.position = p + Vector3(0, 3.5, 0)
		trunk.rotation.z = lean
		trunk.material_override = _mat(Color("7a5a3a"))
		add_child(trunk)
		var top := p + Vector3(-sin(lean) * 7.0, 7.0, 0)
		for f in 6:
			var fr := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(2.6, 0.06, 0.55)
			fr.mesh = fb
			fr.position = top
			fr.rotation = Vector3(0, f * TAU / 6.0, -0.35)
			fr.material_override = _mat(Color("2f7a3a"))
			add_child(fr)


func _arena(rng: RandomNumberGenerator) -> void:
	_box(Vector3(60, 0.02, 70), Vector3(0, -0.06, 0), Color("0f0c1c"))
	var xf: Array = []
	var cols: Array = []
	for sx in [-1.0, 1.0]:
		_stand(rng, Vector3(sx * 8.0, 0, 0), false, 26.0, 7, -sx, xf, cols)
	_stand(rng, Vector3(0, 0, -13.5), true, 18.0, 7, 1.0, xf, cols)
	_crowd = _multi(_person_mesh(), xf, cols)
	for t in xf:
		_crowd_base.append(t)
	# a ring of light boards above the stands
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.2, 1.0, 26), Vector3(sx * 13.0, 7.5, 0), Color("5a3fa8"), true)
	_box(Vector3(18, 1.0, 0.2), Vector3(0, 7.5, -19.5), Color("c6f432"), true)


func _rooftop(rng: RandomNumberGenerator) -> void:
	_box(Vector3(26, 0.4, 36), Vector3(0, -0.25, 0), Color("3a3f48"))          # roof deck
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.3, 1.1, 36), Vector3(sx * 13.0, 0.5, 0), Color("5b616b"))   # parapet
	_box(Vector3(26, 1.1, 0.3), Vector3(0, 0.5, -18), Color("5b616b"))
	# skyline: towers with lit windows, all around below the roof line
	var xf: Array = []
	var cols: Array = []
	var win_x: Array = []
	var win_c: Array = []
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(40.0, 110.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.z > 20.0 and absf(p.x) < 30.0:
			continue
		var h := rng.randf_range(8.0, 45.0)
		var w := rng.randf_range(5.0, 12.0)
		xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, w)), p + Vector3(0, h * 0.5 - 22.0, 0)))
		cols.append(Color.from_hsv(0.62, 0.25, rng.randf_range(0.1, 0.2)))
		for k in 6:
			var wp := p + Vector3(rng.randf_range(-w, w) * 0.45, rng.randf_range(-20.0, h - 23.0), 0)
			wp += (Vector3.ZERO - p).normalized() * (w * 0.5 + 0.05)
			win_x.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.6, 1.0, 1.6)), wp))
			win_c.append(Color("ffd98a") if rng.randf() < 0.7 else Color("9fd3ff"))
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_multi(cube, xf, cols)
	var win := BoxMesh.new()
	win.size = Vector3(1, 1, 1)
	_multi(win, win_x, win_c, true)
