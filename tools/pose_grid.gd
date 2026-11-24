extends SceneTree
# Renders one character in a row of arm poses, for tuning the POSE_* constants.
# godot --path . -s tools/pose_grid.gd -- out.png back|front|side res://assets/characters/NAME.glb "ux,uy,uz,fx,fy,fz;..." (upper arm and forearm directions, as Player._arm_pose)
var frames := 0
var ps: Array = []
var cam: Camera3D
func _init():
	var a := OS.get_cmdline_user_args()
	var root3 := Node3D.new(); get_root().add_child(root3)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("2a5d8f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.6
	env.environment = e; root3.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); root3.add_child(sun)
	var poses: PackedStringArray = a[3].split(";")
	for i in poses.size():
		var v := poses[i].split(",")
		var p := Player.new().setup(0, "P", 0, Color("f28c28"), Color("e3b48c"), Color("3a2a20"), true)
		p.position = Vector3((i - (poses.size() - 1) * 0.5) * 1.3, 0, 0)
		root3.add_child(p); p.use_model(load(a[2]))
		p.set_meta("pose", Player._arm_pose(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5]))))
		ps.append(p)
	cam = Camera3D.new(); cam.fov = 40; cam.current = true; root3.add_child(cam)
	var w := poses.size() * 1.3
	var d := 1.2 + w * 0.75
	match a[1]:
		"front": cam.look_at_from_position(Vector3(0, 1.5, -d), Vector3(0, 1.0, 0))
		"side": cam.look_at_from_position(Vector3(0, 1.3, d), Vector3(0, 1.0, 0))
		_: cam.look_at_from_position(Vector3(0, 1.0 + d * 0.45, d), Vector3(0, 1.0, 0))   # like the game camera
func _process(_d):
	frames += 1
	for p in ps:
		if p._shoulder:
			p._swinging = true
			if OS.get_cmdline_user_args()[1] == "side": p.rotation.y = -PI * 0.5   # seen side-on, facing left
			p._shoulder.quaternion = p.get_meta("pose")[0]
			p._elbow.rotation.x = p.get_meta("pose")[1]
	if frames == 8:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
