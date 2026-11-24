extends SceneTree
# Soak test: swings and runs each character for many frames and checks the
# arm/leg lengths stay constant (no stretching). godot --headless --path . -s tools/limb_soak.gd
var frames := 0
var ps: Array = []
var base := {}
func _init():
	var root3 := Node3D.new(); get_root().add_child(root3)
	for n in ["you", "ana", "marco", "leo"]:
		var p := Player.new().setup(1 if n in ["marco", "leo"] else 0, n, 0, Color.WHITE, Color.WHITE, Color.BLACK, false)
		root3.add_child(p); p.use_model(load("res://assets/characters/%s.glb" % n)); ps.append(p)
func _len(p, a, b) -> float:
	var s: Skeleton3D = p._skel
	return (s.get_bone_global_pose(s.find_bone(a)).origin - s.get_bone_global_pose(s.find_bone(b)).origin).length()
func _process(d):
	frames += 1
	for p in ps:
		if frames % 23 == 0: p.swing(["drive", "slice", "smash", "lob", "bandeja"][randi() % 5])
		p.position.x = sin(frames * 0.05) * 3.0
	if frames == 30 or frames == 3000:
		for p in ps:
			var v := [_len(p, "RightArm", "RightForeArm"), _len(p, "RightForeArm", "RightHand"), _len(p, "LeftArm", "LeftForeArm"), _len(p, "LeftForeArm", "LeftHand"), _len(p, "LeftLeg", "LeftFoot")]
			if frames == 30: base[p] = v
			else: print(p.name, " upper/fore/upper/fore/shin at start ", base[p], " after 3000 frames ", v)
	if frames == 3000: quit()
