class_name MenuHero
extends SubViewport
## The start menu's key art: your pair, in your kit, celebrating on a
## transparent background. Its own little 3D world, rendered only while the
## menu is showing.

var _ps: Array[Player] = []
var _world: Node3D


func _ready() -> void:
	own_world_3d = true
	transparent_bg = true
	size = Vector2i(640, 860)
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world = Node3D.new()
	add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b8c8ff")
	e.ambient_light_energy = 0.55
	env.environment = e
	_world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 160, 0)
	key.light_energy = 1.25
	_world.add_child(key)
	var rim := DirectionalLight3D.new()       # lime rim light, like the floodlights
	rim.rotation_degrees = Vector3(-10, -20, 0)
	rim.light_color = Color("c6f432")
	rim.light_energy = 1.3
	_world.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.current = true
	_world.add_child(cam)
	cam.look_at_from_position(Vector3(0.85, 1.32, -4.9), Vector3(0.05, 1.18, 0))


## ids: [you, partner] character ids. look: {hat, hat_col, band, kit_col,
## paddle: [shape, face, trim]} for you.
func show_team(ids: Array, look: Dictionary) -> void:
	for p in _ps:
		p.queue_free()
	_ps.clear()
	var spots := [Vector3(-0.45, 0, 0), Vector3(0.5, 0, 0.25)]
	for i in 2:
		var c := Roster.character(ids[i])
		var p := Player.new().setup(0, c.name, 0, Color("f28c28"), c.skin, c.hair, true)
		p.position = spots[i]
		_world.add_child(p)
		var path := "res://assets/characters/%s.glb" % ("you" if c.id == "dani" else c.id)
		if ResourceLoader.exists(path):
			p.use_model(load(path))
		_ps.append(p)
	await get_tree().process_frame
	for i in _ps.size():
		var p := _ps[i]
		p._tag.visible = false
		p._ring.visible = false
		if i == 0 and look.has("paddle"):
			p.set_paddle(look.paddle[0], look.paddle[1], look.paddle[2])
		if i == 0:
			p.set_cosmetics(look.get("hat", ""), look.get("hat_col", Color.WHITE), look.get("band", Color(0, 0, 0, 0)),
				look.get("kit_col", Color(0, 0, 0, 0)), Roster.character(ids[0]).get("kit_key", {}))
		p.celebrate("jump" if i == 0 else "pump")


func set_active(on: bool) -> void:
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if render_target_update_mode != mode:
		render_target_update_mode = mode
		_world.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
