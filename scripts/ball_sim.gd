class_name BallSim
extends RefCounted
## Deterministic ball physics. The live ball and the AI's trajectory
## prediction both run this, so what the AI predicts is what happens.
## Each step returns a list of events: [type, position, surface]
## where type is "floor", "wall", "net" or "out".

const RADIUS := 0.04
const GRAVITY := 9.81
const FLOOR_E := 0.74          # vertical restitution off the turf
const FLOOR_FRICTION := 0.82   # horizontal speed kept on a bounce
const GLASS_E := 0.62          # glass gives the ball back
const GLASS_TANGENT := 0.9
const MESH_E := 0.22           # mesh fence kills it
const MESH_TANGENT := 0.5

var pos := Vector3.ZERO
var vel := Vector3.ZERO
## -1 = heavy backspin (slice) .. +1 = topspin. Backspin keeps the bounce low
## and skidding, and makes the ball die off the glass. Halves on every bounce.
var spin := 0.0
## Steady wind on outdoor courts (m/s² of drift). Static so the live ball and
## every prediction feel the same wind.
static var wind := Vector3.ZERO


func copy() -> BallSim:
	var s := BallSim.new()
	s.pos = pos
	s.vel = vel
	s.spin = spin
	return s


func step(dt: float) -> Array:
	var events: Array = []
	var prev := pos
	vel.y -= GRAVITY * dt
	vel += wind * dt
	pos += vel * dt

	# net: did we cross z = 0 below the tape?
	if prev.z != 0.0 and signf(prev.z) != signf(pos.z) and absf(pos.x) < Court.HALF_W:
		var t := prev.z / (prev.z - pos.z)
		var cross := prev.lerp(pos, t)
		if cross.y - RADIUS < Court.net_height(cross.x):
			pos = Vector3(cross.x, cross.y, signf(prev.z) * (RADIUS + 0.02))
			vel = Vector3(vel.x * 0.3, minf(vel.y, 0.0) * 0.3, -vel.z * 0.1)
			events.append(["net", pos, ""])

	# floor
	if pos.y < RADIUS and vel.y < 0.0:
		pos.y = RADIUS
		# backspin: lower bounce that skids through; topspin: kicks up and slows
		vel.y = -vel.y * FLOOR_E * (1.0 + 0.45 * spin)
		var keep := FLOOR_FRICTION + (0.1 if spin < 0.0 else -0.05) * absf(spin)
		vel.x *= keep
		vel.z *= keep
		spin *= 0.5
		if absf(pos.x) <= Court.HALF_W and absf(pos.z) <= Court.HALF_L:
			events.append(["floor", pos, ""])

	# back walls
	var lim_z := Court.HALF_L - RADIUS
	if absf(pos.z) > lim_z and signf(vel.z) == signf(pos.z):
		var surf := Court.back_wall_surface(pos.y)
		if surf != "":
			pos.z = signf(pos.z) * lim_z
			_reflect(surf, Vector3(0, 0, 1))
			events.append(["wall", pos, surf])

	# side walls
	var lim_x := Court.HALF_W - RADIUS
	if absf(pos.x) > lim_x and signf(vel.x) == signf(pos.x):
		var surf := Court.side_wall_surface(pos.y, pos.z)
		if surf != "":
			pos.x = signf(pos.x) * lim_x
			_reflect(surf, Vector3(1, 0, 0))
			events.append(["wall", pos, surf])

	if absf(pos.x) > Court.HALF_W + 0.3 or absf(pos.z) > Court.HALF_L + 0.3 or pos.y < -0.5:
		events.append(["out", pos, ""])
	return events


func _reflect(surface: String, axis: Vector3) -> void:
	var e := GLASS_E if surface == "glass" else MESH_E
	var keep := GLASS_TANGENT if surface == "glass" else MESH_TANGENT
	if spin < 0.0:
		e *= 1.0 + 0.4 * spin      # a slice "dies" off the wall
	var normal_part := vel * axis
	var tangent := vel - normal_part
	vel = tangent * keep - normal_part * e
	if spin < 0.0:
		vel.y = minf(vel.y, vel.y * (1.0 + 0.5 * spin))   # and drops off it
	spin *= 0.6
