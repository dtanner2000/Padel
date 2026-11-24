extends SceneTree
# godot --headless --path . -s tools/inspect_char.gd -- res://assets/characters/you.glb
func _init():
	var path: String = OS.get_cmdline_user_args()[0]
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	get_root().add_child(inst)
	await process_frame
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	print("skeleton path: ", inst.get_path_to(sk), "  bones: ", sk.get_bone_count())
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		print("mesh ", inst.get_path_to(mi), " aabb ", mi.get_aabb(), " skin ", mi.skin != null)
	for b in ["Hips", "Head", "head_end", "LeftHand", "RightHand", "RightArm", "RightForeArm", "LeftFoot", "RightFoot", "LeftToeBase"]:
		var i := sk.find_bone(b)
		if i >= 0:
			var g := sk.global_transform * sk.get_bone_global_pose(i)
			print("%-13s pos %s  x %s y %s z %s" % [b, g.origin.snapped(Vector3.ONE * 0.001), g.basis.x.snapped(Vector3.ONE * 0.01), g.basis.y.snapped(Vector3.ONE * 0.01), g.basis.z.snapped(Vector3.ONE * 0.01)])
	print("skeleton global scale ", sk.global_transform.basis.get_scale())
	quit()
