extends RefCounted

## A low, deck-resting form of the same 6 mm bowline. The nipping turn,
## returning strands, standing-part collar and tails keep their crossing
## order. This authored geometry is separate from the loose hand loop.
const BOWLINE := preload("res://src/boat/rope_bowline.gd")

static func nipping() -> PackedVector3Array:
	var points := PackedVector3Array([Vector3(-.012,-.004,-.050),Vector3(-.012,-.004,-.018)])
	for i in 65:
		var t := i/64.0
		# Most of the turn rests low; the returning standing leg rises only
		# near its exit. A uniformly pitched helix unnecessarily lifts every
		# crossing and makes the entire knot too tall beneath the tiller.
		var y := lerpf(-.004,-.002,smoothstep(0,.1,t)) if t<.1 else lerpf(-.002,.004,smoothstep(.8,.92,t))
		var angle := PI-TAU*t
		points.append(Vector3(.012*cos(angle),y,.012*sin(angle)))
	points.append(Vector3(-.012,.004,.022))
	return points

static func returning() -> PackedVector3Array:
	return BOWLINE.smooth(PackedVector3Array([
		Vector3(.016,.0045,.022),Vector3(.0035,.0045,.006),
		Vector3(.0035,-.0083,-.002),Vector3(.0035,-.0083,-.016),
		Vector3(-.012,-.0105,-.025),Vector3(-.025,-.004,-.025),
		Vector3(-.012,.0025,-.025),Vector3(-.0035,.0045,-.015),
		Vector3(-.0035,.0045,.001),Vector3(-.0035,-.0083,.007),
		Vector3(-.004,-.0093,.025),Vector3(-.008,-.0063,.046),
	]))
