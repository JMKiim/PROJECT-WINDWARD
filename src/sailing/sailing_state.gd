class_name SailingState
extends RefCounted

const PRESSURE := preload("res://src/sailing/sail_pressure.gd")

const HEAD_TO_WIND_ZERO_DRIVE_DEGREES := 20.0
const CLOSE_HAULED_REFERENCE_DEGREES := 42.0
const MAX_SHEET_RATE := 0.45
const MAX_TURN_RATE := deg_to_rad(42.0)
const BOOM_SPRING_STRENGTH := 20.0
const BOOM_DAMPING := 5.8
const MAX_BOOM_SPEED := deg_to_rad(260.0)
const LATERAL_LINEAR_DRAG := 2.4
const LATERAL_QUADRATIC_DRAG := 1.1
# Nominal dry boat58kg plus assumed crew75kg;not measured all-up mass.
const BASE_MASS_KG := 58.0
const REFERENCE_DISPLACEMENT_MASS_KG := 133.0
# Effective foil speed scale,not an identified daggerboard lift coefficient.
const FOIL_RESPONSE_SPEED_MPS := 3.0
# Effective depowered-rig windage coefficient rho*Cd*A/(2*mass),in1/m.
# This small aggregate is not a measured ILCA sail-pressure calibration.
const LUFFING_AIR_DRAG_PER_MASS := .001
const REVERSE_LINEAR_DRAG := .20
const REVERSE_QUADRATIC_DRAG := .15
# Installed-sail resistance uses relative-water speed squared. Preserve the
# old law's force at the existing3m/s reference,not its unmeasured low-speed
# fractional brake. This is an effective coefficient,not hull tow-test data.
const INSTALLED_REVERSE_QUADRATIC_DRAG := REVERSE_QUADRATIC_DRAG+REVERSE_LINEAR_DRAG/FOIL_RESPONSE_SPEED_MPS

var heading_radians: float = 0.0
var speed_mps: float = 0.0
var sheet_position: float = 0.45
var true_wind_velocity := Vector3(6.0, 0.0, 0.0)
var water_current_velocity := Vector3.ZERO
var boom_angle_radians := deg_to_rad(38.0)
var boom_angular_velocity := 0.0
var water_relative_velocity := Vector3.ZERO
var fixed_boom_side := 0.0
var geometric_boom_limit_radians := -1.0
var installed_boom_yaw_radians := NAN
var sail_chord_boat := Vector3.ZERO
var sail_span_boat := Vector3.ZERO
var sail_frame_active := false
var sail_pressure := PRESSURE.new()
var sail_attitude_basis := Basis.IDENTITY
var displacement_mass_kg := REFERENCE_DISPLACEMENT_MASS_KG
var sail_lateral_force_n := 0.0
var lateral_water_force_n := 0.0
var lateral_hull_force_n := 0.0
var lateral_foil_force_n := 0.0
var sail_forward_force_n := 0.0
var aggregate_forward_force_n := 0.0
var axial_air_force_n := 0.0
var reverse_water_force_n := 0.0

var _boom_side := 1.0
var _water_velocity_initialized := false


func step(delta: float, command: SailingCommand) -> void:
	_initialize_water_velocity_from_legacy_speed()
	sheet_position = clampf(
		sheet_position + command.sheet_delta * MAX_SHEET_RATE * delta,
		0.0,
		1.0
	)

	var steering_authority := rudder_authority()
	heading_radians = wrapf(
		heading_radians - command.rudder * MAX_TURN_RATE * steering_authority * delta,
		-PI,
		PI
	)

	if sail_frame_active:
		sail_pressure.advance(delta,sail_chord_boat,sail_span_boat,heading_radians,apparent_wind_velocity(),sail_attitude_basis)
	var target_speed := _calculate_target_speed()
	if target_speed > speed_mps:
		speed_mps = move_toward(speed_mps, target_speed, 0.65 * delta)
	else:
		# Pointing too high removes drive, but the hull keeps its momentum and
		# slows progressively from hydrodynamic drag instead of hitting a brake.
		var drag_rate := 0.11 + speed_mps * speed_mps * 0.024
		speed_mps = maxf(target_speed, speed_mps - drag_rate * delta)
	_update_water_relative_velocity(delta,target_speed)
	_update_boom(delta)


func forward_vector() -> Vector3:
	return Vector3(-sin(heading_radians), 0.0, -cos(heading_radians))


func set_sail_frame(chord: Vector3,span: Vector3) -> bool:
	sail_frame_active=chord.is_finite() and span.is_finite() and chord.cross(span).length_squared()>.000001
	sail_chord_boat=chord.normalized() if sail_frame_active else Vector3.ZERO
	sail_span_boat=span.normalized() if sail_frame_active else Vector3.ZERO
	return sail_frame_active


func velocity_vector() -> Vector3:
	return ground_velocity_vector()


func water_velocity_vector() -> Vector3:
	_initialize_water_velocity_from_legacy_speed()
	return water_relative_velocity


func forward_water_speed_mps() -> float:
	return water_velocity_vector().dot(forward_vector())


func lateral_water_speed_mps() -> float:
	var forward := forward_vector()
	return water_velocity_vector().dot(Vector3(-forward.z,0,forward.x))


func leeway_degrees() -> float:
	# Signed keel-line drift angle;abs(forward) also describes sternway.
	if water_velocity_vector().length_squared()<.00000001: return 0.0
	return rad_to_deg(atan2(lateral_water_speed_mps(),absf(forward_water_speed_mps())))


func rudder_authority() -> float:
	# The same physical blade produces the opposite yaw with sternway.
	# Ground/current speed is not water flow over the rudder.
	return clampf(forward_water_speed_mps()/3.0,-1.0,1.0)


func luffing_air_acceleration() -> Vector3:
	var weight := 1.0-smoothstep(HEAD_TO_WIND_ZERO_DRIVE_DEGREES,CLOSE_HAULED_REFERENCE_DEGREES,wind_angle_degrees())
	var air := apparent_wind_velocity()
	air.y=0
	var acceleration := air*air.length()*LUFFING_AIR_DRAG_PER_MASS*weight
	# With an installed sail,the pressure owns transverse air force. Retain
	# only this legacy depowered model's longitudinal backing contribution.
	return forward_vector()*acceleration.dot(forward_vector()) if sail_frame_active else acceleration


func axial_air_acceleration() -> Vector3:
	var legacy := luffing_air_acceleration()
	var forward := forward_vector()
	var mass := maxf(displacement_mass_kg,1.0)
	aggregate_forward_force_n=legacy.dot(forward)*mass
	sail_forward_force_n=sail_pressure.force_world_newtons().dot(forward) if sail_frame_active else 0.0
	axial_air_force_n=aggregate_forward_force_n
	if sail_frame_active and sail_forward_force_n<0:
		# The aggregate already includes depowered sail windage. Replace its
		# overlapping backward estimate when the actual plane predicts more;
		# do not add both forces or invent a separately calibrated bare hull.
		axial_air_force_n=minf(aggregate_forward_force_n,sail_forward_force_n)
		return forward*axial_air_force_n/mass
	return legacy


func ground_velocity_vector() -> Vector3:
	return water_velocity_vector() + water_current_velocity


func ground_speed_mps() -> float:
	return ground_velocity_vector().length()


func apparent_wind_velocity() -> Vector3:
	return true_wind_velocity - ground_velocity_vector()


func wind_angle_degrees() -> float:
	var wind_from := -true_wind_velocity.normalized()
	var alignment := clampf(forward_vector().dot(wind_from), -1.0, 1.0)
	return rad_to_deg(acos(alignment))


func apparent_wind_speed_mps() -> float:
	return apparent_wind_velocity().length()


func optimal_sheet_position() -> float:
	return clampf(remap(wind_angle_degrees(), 30.0, 180.0, 0.08, 1.0), 0.08, 1.0)


func boom_angle_degrees() -> float:
	return rad_to_deg(boom_angle_radians)


func _update_boom(delta: float) -> void:
	# The installed display has already integrated its one boom response.
	# Keep the sheet limit separate;do not overwrite the actual opening.
	if is_finite(installed_boom_yaw_radians):
		boom_angle_radians=installed_boom_yaw_radians
		return
	# The limited seated scene has an authoritative geometric sheet purchase.
	# It does not opt into the legacy automatic tack/gybe side switch.
	if fixed_boom_side!=0 and geometric_boom_limit_radians>=0:
		_boom_side = signf(fixed_boom_side)
		boom_angle_radians = _boom_side*geometric_boom_limit_radians
		boom_angular_velocity = 0
		return
	var apparent_wind := apparent_wind_velocity()
	if apparent_wind.length_squared() > 0.001:
		var apparent_wind_from := -apparent_wind.normalized()
		var side_signal := forward_vector().cross(apparent_wind_from).y
		if absf(side_signal) > 0.025:
			_boom_side = signf(side_signal)

	var maximum_angle := deg_to_rad(lerpf(5.0, 84.0, sheet_position))
	var target_angle := _boom_side * maximum_angle
	var angular_acceleration := (
		(target_angle - boom_angle_radians) * BOOM_SPRING_STRENGTH
		- boom_angular_velocity * BOOM_DAMPING
	)
	boom_angular_velocity = clampf(
		boom_angular_velocity + angular_acceleration * delta,
		-MAX_BOOM_SPEED,
		MAX_BOOM_SPEED
	)
	boom_angle_radians = clampf(
		boom_angle_radians + boom_angular_velocity * delta,
		-maximum_angle,
		maximum_angle
	)


func _initialize_water_velocity_from_legacy_speed() -> void:
	# Existing callers and saved tests still seed scalar speed directly. Treat it
	# as an initial through-water velocity, then retain vector momentum thereafter.
	if _water_velocity_initialized:
		return
	if water_relative_velocity.length_squared() < 0.000001 and speed_mps > 0.0001:
		water_relative_velocity = forward_vector() * speed_mps
	_water_velocity_initialized = true


func _update_water_relative_velocity(delta: float,target_speed: float) -> void:
	# Installed sail and aggregate sample the same pre-integration air flow.
	var air_acceleration := axial_air_acceleration() if sail_frame_active else Vector3.ZERO
	var forward := forward_vector()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var forward_speed := water_relative_velocity.dot(forward)
	var lateral_speed := water_relative_velocity.dot(right)
	reverse_water_force_n=0
	if forward_speed<0:
		# Retain signed momentum instead of pulling sternway toward the
		# legacy nonnegative HUD speed at1.35m/s². Water drag dissipates it;
		# available sail drive can then establish forward way continuously.
		if sail_frame_active:
			forward_speed=_advance_sternway(delta,forward_speed)
		else:
			var resistance := absf(forward_speed)*REVERSE_LINEAR_DRAG+forward_speed*forward_speed*REVERSE_QUADRATIC_DRAG
			forward_speed=move_toward(forward_speed,0,resistance*delta)
		var available := clampf(target_speed/maxf(true_wind_velocity.length()*.72,.0001),0,1)
		forward_speed+=.65*available*delta
	else:
		forward_speed = move_toward(forward_speed, speed_mps, 1.35 * delta)
	var lateral_drag := (
		lateral_speed * LATERAL_LINEAR_DRAG
		+ lateral_speed * absf(lateral_speed) * LATERAL_QUADRATIC_DRAG
	)
	var new_lateral_speed := move_toward(
		lateral_speed,
		0.0,
		absf(lateral_drag) * delta
	)
	sail_lateral_force_n=0; lateral_water_force_n=0
	lateral_hull_force_n=0; lateral_foil_force_n=0
	if sail_frame_active:
		new_lateral_speed=_advance_lateral_speed(delta,forward_speed,lateral_speed,right)
	water_relative_velocity = (
		forward * forward_speed
		+ right * new_lateral_speed
	)
	# Actual negative sail load/overlapping windage supplies real sternway.
	# No minimum speed,yaw impulse,escape timer or input-triggered boost.
	if not sail_frame_active: air_acceleration=axial_air_acceleration()
	water_relative_velocity+=air_acceleration*delta
	speed_mps = maxf(0.0, water_relative_velocity.dot(forward))


func _advance_sternway(delta: float,velocity: float) -> float:
	var coefficient := REFERENCE_DISPLACEMENT_MASS_KG*INSTALLED_REVERSE_QUADRATIC_DRAG
	var a := delta*coefficient/maxf(displacement_mass_kg,1.0)
	# Backward Euler: magnitude+dt*C*magnitude²/mass=old magnitude.
	# The rationalized root dissipates without reversing passive motion.
	var result := -2*absf(velocity)/(1+sqrt(1+4*a*absf(velocity)))
	reverse_water_force_n=coefficient*result*result
	return result


func _advance_lateral_speed(delta: float,forward_speed: float,lateral_speed: float,right: Vector3) -> float:
	sail_lateral_force_n=sail_pressure.force_world_newtons().dot(right)
	# Hull/crossflow damping remains at low speed. A foil-like term grows
	# with signed-flow magnitude and its horizontal normal projection².
	# This is an effective resistance,not foil geometry or measured CL.
	var projection := (sail_attitude_basis*Vector3.RIGHT).dot(Vector3.RIGHT)
	var linear := REFERENCE_DISPLACEMENT_MASS_KG*LATERAL_LINEAR_DRAG*(1+absf(forward_speed)/FOIL_RESPONSE_SPEED_MPS*projection*projection)
	var quadratic := REFERENCE_DISPLACEMENT_MASS_KG*LATERAL_QUADRATIC_DRAG
	var mass := maxf(displacement_mass_kg,1.0)
	# Backward Euler solves v+dt*(k*v+c*abs(v)*v)/m=v0+dt*F/m.
	# Rationalized quadratic root is finite at zero and does not flip a
	# passive drift by overdamping it across zero on a long frame.
	var target := lateral_speed+delta*sail_lateral_force_n/mass
	var b := 1+delta*linear/mass
	var a := delta*quadratic/mass
	var speed := signf(target)*2*absf(target)/(b+sqrt(b*b+4*a*absf(target)))
	lateral_water_force_n=-linear*speed-quadratic*absf(speed)*speed
	# Split the already-applied force,without changing velocity integration.
	lateral_hull_force_n=-REFERENCE_DISPLACEMENT_MASS_KG*LATERAL_LINEAR_DRAG*speed-quadratic*absf(speed)*speed
	lateral_foil_force_n=lateral_water_force_n-lateral_hull_force_n
	return speed


func _calculate_target_speed() -> float:
	var angle := wind_angle_degrees()
	var polar_efficiency: float
	if angle <= HEAD_TO_WIND_ZERO_DRIVE_DEGREES:
		polar_efficiency = 0.0
	elif angle < CLOSE_HAULED_REFERENCE_DEGREES:
		var close_reach_ratio := smoothstep(
			HEAD_TO_WIND_ZERO_DRIVE_DEGREES,
			CLOSE_HAULED_REFERENCE_DEGREES,
			angle
		)
		polar_efficiency = lerpf(0.0, 0.70, close_reach_ratio)
	elif angle <= 100.0:
		polar_efficiency = remap(angle, CLOSE_HAULED_REFERENCE_DEGREES, 100.0, 0.70, 1.0)
	else:
		polar_efficiency = remap(angle, 100.0, 180.0, 1.0, 0.72)

	if sail_frame_active:
		return true_wind_velocity.length()*.72*polar_efficiency*sail_pressure.speed_factor(true_wind_velocity.length())
	# Legacy callers without an installed sail frame retain their old model.
	var trim_error := absf(sheet_position - optimal_sheet_position())
	var trim_efficiency := 1.0 - clampf(trim_error / 0.65, 0.0, 1.0)
	return true_wind_velocity.length() * 0.72 * polar_efficiency * lerpf(0.2, 1.0, trim_efficiency)
