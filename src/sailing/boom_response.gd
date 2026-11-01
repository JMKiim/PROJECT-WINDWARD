extends RefCounted
## Effective angular response,not a calibrated boom torque/inertia solver.
## The confirmed side is an input;the response can never initiate a gybe.
var magnitude := 0.0
var angular_velocity := 0.0
var initialized := false
func synchronize(yaw: float) -> void:
	magnitude=absf(yaw); angular_velocity=0; initialized=true
func advance(delta: float,limit: float,side: float,air_boat: Vector3,scripted: bool) -> float:
	if not initialized: synchronize(limit)
	if magnitude>limit: magnitude=limit; angular_velocity=0
	if delta<=0: return side*magnitude
	if scripted:
		var previous := magnitude
		magnitude=move_toward(magnitude,limit,SailingState.MAX_BOOM_SPEED*delta)
		angular_velocity=(magnitude-previous)/delta
		return side*magnitude
	var remaining := delta
	while remaining>0:
		var dt := minf(remaining,1.0/120); remaining-=dt
		var difference := 0.0
		if Vector2(air_boat.x,air_boat.z).length_squared()>.000001:
			# Choose the wind's circular branch from the current boom,not the
			# principal atan2 sign. At179->181deg an already open boom stays
			# against its sheet on the same confirmed side.
			difference=wrapf(side*atan2(air_boat.x,air_boat.z)-magnitude,-PI,PI)
		var target := clampf(magnitude+difference,0,limit)
		var acceleration := (target-magnitude)*SailingState.BOOM_SPRING_STRENGTH-angular_velocity*SailingState.BOOM_DAMPING
		angular_velocity=clampf(angular_velocity+acceleration*dt,-SailingState.MAX_BOOM_SPEED,SailingState.MAX_BOOM_SPEED)
		var proposed := magnitude+angular_velocity*dt
		magnitude=clampf(proposed,0,limit)
		if proposed!=magnitude: angular_velocity=0
	return side*magnitude
