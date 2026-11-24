extends SceneTree
# renders the player rig in a few poses: godot --path . -s tools/pose_test.gd -- out_prefix [res://model.glb]
var frames := 0
var players: Array = []
func _init():
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("2a5d8f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.6
	env.environment = e; root3.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 30, 0); root3.add_child(sun)
	for i in 6:
		var p := Player.new().setup(0, "P%d" % i, 0, Color("f28c28"), Color("e3b48c"), Color("3a2a20"), true)
		p.position = Vector3((i % 3 - 1) * 1.6, 0, 0 if i < 3 else -30)
		if i >= 3: p.rotation.y = PI
		root3.add_child(p)
		if OS.get_cmdline_user_args().size() > 1:
			p.use_model(load(OS.get_cmdline_user_args()[1]))
		players.append(p)
	var cam := Camera3D.new(); cam.position = Vector3(1.2, 1.6, 4.2); root3.add_child(cam)
	cam.fov = 45; cam.current = true; cam.look_at_from_position(Vector3(1.2, 1.6, 4.2), Vector3(0, 1.0, 0))
func _process(_d):
	frames += 1
	if frames == 7:
		players[1].swing("drive"); players[4].swing("drive")
		players[2].swing("smash"); players[5].swing("smash")
	if frames == 10:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "_back.png")
		var cam: Camera3D = get_root().get_camera_3d()
		cam.look_at_from_position(Vector3(1.2, 1.6, -34.2), Vector3(0, 1.0, -30))
	if frames == 12:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "_front.png")
		quit()
