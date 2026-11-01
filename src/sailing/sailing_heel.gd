extends RefCounted

## Bounded small-angle roll coupling,not measured hull hydrostatics/capsize.
## The effective inertia is assumed;25/s^2 and10/s retain the old response.
const GRAVITY := 9.81
const EFFECTIVE_INERTIA_KG_M2 := 60.0
const RESTORING_NM := EFFECTIVE_INERTIA_KG_M2*25.0
const DAMPING_NMS := EFFECTIVE_INERTIA_KG_M2*10.0
var crew_mass_kg := 75.0
var angle := 0.0
var angular_velocity := 0.0
var wind_force_world := Vector3.ZERO
var wind_moment_nm := 0.0
var crew_moment_nm := 0.0
var restoring_moment_nm := 0.0
var water_moment_nm := 0.0

func advance(delta: float,body_basis: Basis,pressure: RefCounted,sail_center: Vector3,crew_center: Vector3,limit: float,water_moment := 0.0) -> bool:
	if not is_finite(delta) or delta<=0 or not sail_center.is_finite() or not crew_center.is_finite(): return false
	wind_force_world=pressure.force_world_newtons()
	wind_moment_nm=sail_center.cross(body_basis.inverse()*wind_force_world).z
	crew_moment_nm=crew_center.cross(body_basis.inverse()*(Vector3.DOWN*GRAVITY*crew_mass_kg)).z
	water_moment_nm=water_moment
	var count := maxi(1,ceili(delta*120))
	var step := delta/count
	for index in count:
		restoring_moment_nm=-RESTORING_NM*sin(angle)
		angular_velocity+=(wind_moment_nm+crew_moment_nm+water_moment_nm+restoring_moment_nm-DAMPING_NMS*angular_velocity)/EFFECTIVE_INERTIA_KG_M2*step
		angle+=angular_velocity*step
		if absf(angle)>limit:
			angle=clampf(angle,-limit,limit)
			if angular_velocity*angle>0: angular_velocity=0
	return true
