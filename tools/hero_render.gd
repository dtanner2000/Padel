extends SceneTree
## Key art: characters celebrating on a transparent background (menu / store art).
## godot --path . -s tools/hero_render.gd -- out.png t_seconds
var frames := 0
var ps: Array[Player] = []
func _init():
	get_root().transparent_bg = true
	var root3 := Node3D.new(); get_root().add_child(root3)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("b8c8ff"); e.ambient_light_energy = 0.55
	env.environment = e; root3.add_child(env)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-30, 160, 0); key.light_energy = 1.25; root3.add_child(key)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(-10, -20, 0); rim.light_color = Color("c6f432"); rim.light_energy = 1.6; root3.add_child(rim)
	var specs := [["you", "dani", Vector3(-0.45, 0, 0), "jump"], ["ana", "ana", Vector3(0.5, 0, 0.25), "pump"]]
	for sp in specs:
		var c := Roster.character(sp[1])
		var p := Player.new().setup(0, c.name, 0, Color("f28c28"), c.skin, c.hair, true)
		p.position = sp[2]
		root3.add_child(p); p.use_model(load("res://assets/characters/%s.glb" % sp[0]))
		p.set_meta("kind", sp[3])
		p.set_meta("char", c)
		ps.append(p)
	var cam := Camera3D.new(); cam.fov = 36; cam.current = true; root3.add_child(cam)
	cam.look_at_from_position(Vector3(0.9, 1.35, -4.8), Vector3(0.05, 1.2, 0))
func _process(d):
	frames += 1
	if frames == 2:
		for p in ps:
			var c: Dictionary = p.get_meta("char")
			if c.id == "dani":
				p.set_cosmetics("bandana", Color("ff2d95"), Color("ff2d95"), Color("d8ff1a"), c.kit_key)
			else:
				p.set_cosmetics("headband", Color("f2f2f2"), Color("f2f2f2"), Color("ff2d95"), c.kit_key)
			p._tag.visible = false
			p._ring.visible = false
			p.celebrate(p.get_meta("kind"))
	var t := float(OS.get_cmdline_user_args()[1])
	if frames == int(t * 60.0):
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
