class_name Hop
extends RefCounted

## Jump maths, isolated so it can be tested without a scene.
##
## A hop is two independent animations glued together:
##   * the horizontal (x/z) travel, which is linear, so a cube-to-cube hop
##     starts and stops crisply the way an arcade sprite does;
##   * the vertical bump, 4*t*(1-t), a parabola that is 0 at both ends and
##     exactly `height` at t = 0.5.
##
## Doing the maths here rather than inside a Tween means the tests can assert
## "a hop never starts below its start and never ends above its destination",
## which is the kind of bug that only shows up as a one-frame jitter on a real
## display.

## Position along a hop at normalised time `t` (0 = takeoff, 1 = landing).
static func arc(t: float, from: Vector3, to: Vector3, height: float) -> Vector3:
	var p := from.lerp(to, t)
	p.y += height * 4.0 * t * (1.0 - t)
	return p


## Smoothstep, for things that should start and stop gently (camera moves,
## the disc ride, the level-clear flash). Hop arcs deliberately do not use it.
static func smoothstep(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
