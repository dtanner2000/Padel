extends SceneTree
# Every celebration / reaction pose in a row, from the front and the side:
# godot --path . --fixed-fps 30 -s tools/react_test.gd -- out_prefix seconds [model] [kinds,comma,separated]
const KINDS := ["jump", "pump", "five", "chest", "point", "crowd", "twirl", "nod",
	"sad", "angry", "head", "blame", "shrug", "hips", "applaud", "slump"]
var frames := 0
var players: Array = []
var kinds: Array = []
var cam: Camera3D


func _init():
	var args := OS.get_cmdline_user_args()
	var model: String = args[2] if args.size() > 2 else "you"
	kinds = Array(args[3].split(",")) if args.size() > 3 else KINDS
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color("2a5d8f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.7
	env.environment = e; root3.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 20, 0); root3.add_child(sun)
	var c := Roster.character({"you": "dani", "ana": "ana", "marco": "marco", "leo": "leo"}[model])
	for i in kinds.size():
		var p := Player.new().setup(0, kinds[i], 0, Color("f28c28"), c.skin, c.hair, true)
		p.position = Vector3((i - (kinds.size() - 1) / 2.0) * 1.3, 0, 0)
		p.rotation.y = PI
		root3.add_child(p)
		p.use_model(load("res://assets/characters/%s.glb" % model))
		players.append(p)
	cam = Camera3D.new(); root3.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.6
	cam.current = true


func _process(_d):
	frames += 1
	var args := OS.get_cmdline_user_args()
	var secs := float(args[1])
	if frames == 3:
		for i in players.size():
			var p: Player = players[i]
			p.set_tag(kinds[i])
			# partner-facing kinds turn towards the camera side
			p.celebrate(kinds[i], p.position + Vector3(0, 0, 3))
	var at := 3 + int(secs * 30.0)
	if frames == 4:
		cam.look_at_from_position(Vector3(0, 1.0, 10), Vector3(0, 1.0, 0))
	if frames == at:
		get_root().get_texture().get_image().save_png(args[0] + "_front.png")
		for p in players:
			p._celeb_yaw -= PI / 2
			p.rotation.y -= PI / 2
	if frames == at + 2:
		get_root().get_texture().get_image().save_png(args[0] + "_side.png")
		quit()
	return false
