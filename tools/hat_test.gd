extends SceneTree
# Head close-ups of every character wearing a hat (front, side, back), one
# image per view and character: godot --path . -s tools/hat_test.gd -- out_prefix [hat] [json overrides]
# overrides: {"marco": {"y": 0.18}, "all": {...}} merged into Player.head_fit.
const FILES := ["you", "ana", "marco", "leo"]
const IDS := ["dani", "ana", "marco", "leo"]
const VIEWS := [["front", PI], ["side", -PI / 2], ["back", 0.0], ["three", PI * 0.75]]
var frames := 0
var players: Array = []
var cam: Camera3D
var shot := 0


func _init():
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("2a5d8f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.7
	env.environment = e; root3.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 20, 0); root3.add_child(sun)
	for i in 4:
		var c: Dictionary = Roster.character(IDS[i])
		var p := Player.new().setup(0, IDS[i], 0, Color("f28c28"), c.skin, c.hair, true)
		p.position = Vector3(i * 3.0, 0, 0)
		root3.add_child(p)
		p.use_model(load("res://assets/characters/%s.glb" % FILES[i]))
		players.append(p)
	cam = Camera3D.new(); root3.add_child(cam)
	cam.fov = 20; cam.current = true


func _head(p: Player) -> Vector3:
	var sk: Skeleton3D = p._skel
	var i := sk.find_bone("Head")
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin


func _process(_d):
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3:
		var over: Dictionary = JSON.parse_string(args[2]) if args.size() > 2 else {}
		for i in 4:
			var p: Player = players[i]
			var f: Dictionary = p.head_fit.duplicate()
			f.merge(over.get("all", {}), true)
			f.merge(over.get(FILES[i], {}), true)
			p.head_fit = f
			p.set_cosmetics(args[1] if args.size() > 1 else "bandana", Color("ff2d95"), Color(0, 0, 0, 0))
	# from frame 6: every 3 frames, place the camera, then save
	if frames >= 6 and (frames - 6) % 3 == 0:
		var v: int = shot / 4
		var c: int = shot % 4
		if shot > 0:
			var prev := shot - 1
			get_root().get_texture().get_image().save_png("%s_%s_%s.png" % [args[0], VIEWS[prev / 4][0], FILES[prev % 4]])
		if v >= VIEWS.size():
			quit()
			return false
		for p in players:
			p.rotation.y = VIEWS[v][1]
		var h := _head(players[c]) + Vector3(0, 0.1, 0)
		cam.look_at_from_position(h + Vector3(0, 0.05, 1.6), h)
		shot += 1
	return false
