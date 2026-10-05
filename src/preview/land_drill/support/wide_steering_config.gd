extends RefCounted

## Supported training range, not the physical steering stop of every hull.
const DEGREES := 24.0
const STEERING_SAMPLES := 65
const HIKE_LEVELS := 129
const TUBE_METRES := 1.250
const JOINT_METRES := .030
const END_HAND_MARGIN := .060
const BANK := "res://src/boat/animation/land_drill/base_pose_bank.res"
const FEED := "res://src/boat/animation/land_drill/remote_feed.res"
const ENVELOPE := "res://src/boat/animation/land_drill/length_envelope.tres"
const POSTURE := preload("res://src/preview/land_drill/support/land_drill_port_source.tres")

static func resting_palm(amount: float,hike: float) -> Vector3:
	return POSTURE.palm_at(amount,hike)

static func resting_foot(side: String,hike: float) -> Vector3:
	return POSTURE.foot_at(side,hike)

static func _joint_at(amount: float) -> Vector3:
	return Vector3(0,0,2.171)+Basis(Vector3.UP,amount*deg_to_rad(12))*Vector3(0,.352952,-.979058)

static func base_name(side: int, layer: StringName, level: int) -> String:
	return "%s_%s_%d" % ["port" if side==-1 else "starboard",layer,level]

static func relay_name(section: String, index: int) -> String:
	return "relay_%s_%d" % [section,index]
