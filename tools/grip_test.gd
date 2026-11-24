extends SceneTree
# Grid of paddle grip angles x poses, for tuning the hold.
# godot --path . -s tools/grip_test.gd -- out.png "0" back|front [res://assets/characters/NAME.glb]
var frames := 0
var cam: Camera3D
func _init():
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("2a5d8f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.6
	env.environment = e; root3.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); root3.add_child(sun)
	var args := OS.get_cmdline_user_args()
	var bends: PackedStringArray = args[1].split(",")
	var model: PackedScene = load(args[3] if args.size() > 3 else "res://assets/characters/you.glb")
	var poses := [
		[Player.POSE_READY[0], Player.POSE_READY[1]],
		[Vector3(-0.45, 0.0, 0.2), -0.7],          # forehand contact
		[Vector3(-2.9, 0.0, 0.1), -0.4],           # smash contact
	]
	for r in bends.size():
		for c in 3:
			var p := Player.new().setup(0, "P", 0, Color("f28c28"), Color("e3b48c"), Color("3a2a20"), true)
			p.position = Vector3((c - 1) * 1.5, 0, -r * 2.6)
			root3.add_child(p)
			p.use_model(model)
			p.set_meta("pose", poses[c])
			p.set_meta("bend", float(bends[r]))
	cam = Camera3D.new(); cam.fov = 40; cam.current = true; root3.add_child(cam)
func _process(_d):
	frames += 1
	for p in get_root().get_child(0).get_children():
		if p is Player and p._shoulder:
			p._swinging = true
			var pose: Array = p.get_meta("pose")
			p._shoulder.rotation = pose[0]
			p._elbow.rotation.x = pose[1]
	var n := OS.get_cmdline_user_args()[1].split(",").size()
	var back := OS.get_cmdline_user_args().size() < 3 or OS.get_cmdline_user_args()[2] == "back"
	var mid := Vector3(0, 1.0, -(n - 1) * 1.3)
	if back:
		cam.look_at_from_position(mid + Vector3(0.6, 3.2 + n * 0.9, 5.5 + n * 1.6), mid)
	else:
		cam.look_at_from_position(mid + Vector3(0.6, 1.6 + n * 0.5, -(5.5 + n * 1.6)), mid)
	if frames == 8:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
