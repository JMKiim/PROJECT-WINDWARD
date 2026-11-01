extends RefCounted

## Quasi-steady representative-plane pressure,not calibrated ILCA aerodynamics.
## It can attenuate drive; it never owns boom,seat,trim or heading.
const RESPONSE_SECONDS := .18
const FACE_THRESHOLD := .04
const FACE_DWELL_SECONDS := .15
const AIR_DENSITY := 1.225
const SAIL_AREA_M2 := 7.06
var valid := false
var normal_world := Vector3.ZERO
var force_coefficient := Vector3.ZERO
var air_speed_mps := 0.0
var incidence_degrees := 0.0
var signed_load_m2_s2 := 0.0
var raw_drive := 0.0
var drive_fraction := 0.0
var load_side := 0
var pending_side := 0
var pending_seconds := 0.0
var reverse_flow := false
var condition := "무풍"

func advance(delta: float,chord_boat: Vector3,span_boat: Vector3,heading: float,air_world: Vector3,tilt := Basis.IDENTITY) -> void:
	var yaw := Basis(Vector3.UP,heading)
	var turn := yaw*tilt
	var chord := turn*chord_boat.normalized()
	normal_world=(turn*span_boat.cross(chord_boat)).normalized()
	var air := Vector3(air_world.x,0,air_world.z)
	air_speed_mps=air.length()
	valid=normal_world.is_finite() and normal_world.length_squared()>.99
	if not valid: return
	var incoming := air/maxf(air_speed_mps,.000001)
	var normal_flow := incoming.dot(normal_world)
	incidence_degrees=rad_to_deg(asin(clampf(absf(normal_flow),0,1)))
	signed_load_m2_s2=air.dot(normal_world)*absf(air.dot(normal_world))
	force_coefficient=normal_world*normal_flow*absf(normal_flow)
	# Horizontal motion still uses yaw;the sail normal follows physical tilt.
	var forward := yaw*Vector3.FORWARD
	var beta := acos(clampf(forward.dot(-incoming),-1,1))
	# Analytic maximum of sin(theta)*sin(beta-theta)^2 for an upright
	# representative plane:theta=(beta-asin(sin(beta)/3))/2.No pose search.
	var theta := .5*(beta-asin(sin(beta)/3))
	var reference := sin(theta)*pow(sin(beta-theta),2)
	raw_drive=clampf(force_coefficient.dot(forward)/maxf(reference,.00000001),0,1) if air_speed_mps>.001 else 0.0
	drive_fraction=lerpf(drive_fraction,raw_drive,1-exp(-delta/RESPONSE_SECONDS))
	reverse_flow=air.dot(chord)<0
	var candidate := int(signf(normal_flow)) if absf(normal_flow)>FACE_THRESHOLD and air_speed_mps>.01 else 0
	if candidate==0:
		pending_side=0; pending_seconds=0
	elif candidate!=pending_side:
		pending_side=candidate; pending_seconds=delta
	else: pending_seconds+=delta
	if pending_side!=0 and pending_seconds>=FACE_DWELL_SECONDS: load_side=pending_side
	if air_speed_mps<=.01: condition="무풍"
	elif absf(normal_flow)<=FACE_THRESHOLD: condition="러핑"
	elif force_coefficient.dot(forward)<-.00001: condition="역압"
	else: condition="구동" if raw_drive>.02 else "낮은 구동"

func speed_factor(true_wind_speed: float) -> float:
	# A velocity target scales with sqrt(force) under quadratic water drag.
	# Limit by actual relative air as well; remembered loading cannot drive
	# the boat in zero relative air.Neither factor is a minimum-speed floor.
	return sqrt(clampf(drive_fraction,0,1))*clampf(air_speed_mps/maxf(true_wind_speed,.000001),0,1)

func force_world_newtons() -> Vector3:
	# One representative force shared by lateral motion and load heel.
	return force_coefficient*(.5*AIR_DENSITY*SAIL_AREA_M2*air_speed_mps*air_speed_mps) if valid else Vector3.ZERO
