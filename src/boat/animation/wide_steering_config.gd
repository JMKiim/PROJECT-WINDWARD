extends RefCounted

## Supported training range, not the physical steering stop of every hull.
const DEGREES := 24.0
const STEERING_SAMPLES := 65
const HIKE_LEVELS := 129
const TUBE_METRES := 1.250
const JOINT_METRES := .030
const END_HAND_MARGIN := .060
const BANK := "res://src/boat/animation/wide_steering_bank.res"
const FEED := "res://src/boat/animation/wide_steering_feed.tres"
const ENVELOPE := "res://src/boat/animation/wide_steering_envelope.tres"
const HIKE := preload("res://src/boat/animation/hiking_port_source.tres")

static func resting_palm(amount: float,hike: float) -> Vector3:
	var edge := clampf(amount,-1,1)
	var palm: Vector3=HIKE.palm_at(edge,hike)
	if absf(amount)<=1: return palm
	var joint := _joint_at(amount)
	var direction := palm+Vector3(0,-lerpf(.060,.120,hike),0)*clampf(amount-1,0,1)-joint
	# Basic steering holds the same place on the extension. Axial travel is
	# reserved for an authored regrip, not a closed hand sliding at the stop.
	var radius := palm.distance_to(_joint_at(edge))
	if amount<0:
		# A hiked sailor must change grip to reach the far pushing arc. Keep
		# that separate authored reach; seated steering has no axial slide.
		radius=lerpf(radius,direction.length(),smoothstep(0,.25,hike))
	else:
		direction=direction.rotated(Vector3.RIGHT,deg_to_rad(4)*pow(hike,4)*clampf(amount-1,0,1))
	return joint+direction.normalized()*radius

static func _joint_at(amount: float) -> Vector3:
	return Vector3(0,0,2.171)+Basis(Vector3.UP,amount*deg_to_rad(12))*Vector3(0,.352952,-.979058)

static func base_name(side: int, layer: StringName, level: int) -> String:
	return "%s_%s_%d" % ["port" if side==-1 else "starboard",layer,level]

static func relay_name(section: String, index: int) -> String:
	return "relay_%s_%d" % [section,index]
