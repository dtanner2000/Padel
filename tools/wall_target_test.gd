extends SceneTree
# How often a ground stroke can light each glass-targets panel: sweeps where
# you stand, where you aim and how deep, flies the ball with BallSim and
# counts bounce-then-panel hits. godot --headless --path . -s tools/wall_target_test.gd -- [json panels]
# panels: [[side, centre_along, centre_y, width, height], ...]
#   side 0 = back wall (centre_along = x), -1/1 = side wall (centre_along = z)

func _init():
	var args := OS.get_cmdline_user_args()
	var panels: Array = JSON.parse_string(args[0]) if args.size() > 0 else [
		[0, -3.2, 1.2, 2.2, 1.3], [0, 0.0, 1.2, 2.2, 1.3], [1, -8.4, 1.2, 2.2, 1.3]]
	for pn in panels:
		var hits := 0
		var tries := 0
		for px in [-3.5, -2.0, 0.0, 2.0, 3.5]:
			for ax in range(-10, 11):
				for dp in [0.6, 0.8, 1.0]:
					for spin in [0.15, -1.0]:     # drive, slice
						tries += 1
						if _fly(Vector3(px, 0.9, 7.4), ax / 10.0, dp, spin, pn):
							hits += 1
		print("panel %s: %d / %d (%.0f%%)" % [str(pn), hits, tries, 100.0 * hits / tries])
	quit()


func _fly(from: Vector3, aim_x: float, depth: float, spin: float, pn: Array) -> bool:
	var to := Vector3(aim_x * float(OS.get_environment("REACH") if OS.get_environment("REACH") != "" else "3.8"), BallSim.RADIUS, -lerpf(3.0, 8.6, depth))
	var speed := lerpf(10.0, 18.0, 0.85 * 0.6 + depth * 0.4)
	var sim := BallSim.new()
	sim.pos = from
	sim.vel = Shot.solve(from, to, speed, 0.4 if spin > 0.0 else 0.25)
	sim.spin = spin
	var bounces := 0
	for i in 600:
		for ev in sim.step(1.0 / 120.0):
			var p: Vector3 = ev[1]
			match ev[0]:
				"floor":
					if p.z < 0.0:
						bounces += 1
						if bounces >= 2:
							return false
				"wall":
					if p.z > -1.0:
						continue
					if bounces == 0:
						return false     # glass on the full
					var side: int = pn[0]
					var m := BallSim.RADIUS + 0.06
					var inside := absf(p.y - float(pn[2])) <= float(pn[4]) * 0.5 + m
					if side == 0:
						inside = inside and absf(p.z) > Court.HALF_L - 0.3 and absf(p.x - float(pn[1])) <= float(pn[3]) * 0.5 + m
					else:
						inside = inside and signf(p.x) == side and absf(p.x) > Court.HALF_W - 0.3 and absf(p.z - float(pn[1])) <= float(pn[3]) * 0.5 + m
					if inside and ev[2] == "glass":
						return true     # as in the game: a miss plays on (off another wall) until the 2nd bounce
				"out", "net":
					return false
	return false
