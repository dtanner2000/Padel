class_name Shot
extends RefCounted
## Projectile solver for shots: finds a launch velocity that lands the
## ball on a target point and clears the net.

static func launch_velocity(from: Vector3, to: Vector3, t: float) -> Vector3:
	var d := to - from
	return Vector3(d.x / t, (d.y + 0.5 * BallSim.GRAVITY * t * t) / t, d.z / t)


## Ball height (minus net height) where the flight crosses z = 0, or INF if it never does.
static func net_clearance(from: Vector3, v: Vector3) -> float:
	if absf(v.z) < 0.01:
		return INF
	var tn := -from.z / v.z
	if tn <= 0.0:
		return INF
	var y := from.y + v.y * tn - 0.5 * BallSim.GRAVITY * tn * tn
	var x := from.x + v.x * tn
	return y - BallSim.RADIUS - Court.net_height(x)


## Aim at `to` with roughly `speed` m/s of horizontal pace, slowing the shot
## (giving it more arc) until it clears the net by `min_clear`.
static func solve(from: Vector3, to: Vector3, speed: float, min_clear := 0.25) -> Vector3:
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var t := maxf(dist / maxf(speed, 1.0), 0.3)
	var v := launch_velocity(from, to, t)
	for i in 40:
		if net_clearance(from, v) >= min_clear:
			return v
		t *= 1.06
		v = launch_velocity(from, to, t)
	return v
