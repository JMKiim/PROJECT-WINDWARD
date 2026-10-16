extends RefCounted

## Small geometric closure of a prescribed traveller slide. No force solve or
## body-pose search. The original finite groove/joint tolerances still apply.
const SUPPORT := preload("res://src/boat/traveller_supported_route.gd")
const PIN := preload("res://src/boat/revolute_pin_joint.gd")
const CABLE := preload("res://src/boat/cylinder_cable_route.gd")
const ORTHOGONAL := preload("res://src/boat/orthogonal_pin_route.gd")
var seed := Vector2.ZERO

func _trial(boundary: Dictionary,x: float,radius: float,azimuth: float,a: Vector3,b: Vector3) -> Dictionary:
	if radius<.008 or radius>.35 or absf(azimuth)>deg_to_rad(75): return {"valid":false}
	var support := SUPPORT.route(boundary,Vector3(x,radius*cos(azimuth),radius*sin(azimuth)))
	if not support.valid: return support
	var axis: Vector3=(a-support.center).cross(b-a).normalized()
	return {"valid":true,"support":support,"axis":axis,"error":axis.dot(support.frame.basis.x),"radius":radius,"azimuth":azimuth}

func solve(boundary: Dictionary,length: float,x: float,a: Vector3,b: Vector3,lower_eye: Transform3D,upper_eye: Transform3D,minimum: float,maximum: float) -> Dictionary:
	var datum: Vector3=(boundary.port+boundary.starboard)*.5
	var local := boundary.duplicate(true)
	local.port-=datum
	local.starboard-=datum
	local.tiller.origin-=datum
	var at := a-datum
	var bt := b-datum
	var v := seed if seed.x>0 else Vector2(.12*sqrt(maxf(.01,1-pow(x/.51,2))),.4)
	var trial := {}
	var iterations := 0
	for iteration in 10:
		iterations=iteration+1
		trial=_trial(local,x,v.x,v.y,at,bt)
		if not trial.valid: return {"valid":false,"reason":"prescribed support leaves finite contact domain"}
		var residual := Vector2(trial.support.length-length,trial.error)
		if absf(residual.x)<=SUPPORT.LENGTH_TOLERANCE*.5 and absf(residual.y)<.0000002: break
		var dr := .0001
		var da := .001
		var radial := _trial(local,x,v.x+dr,v.y,at,bt)
		var angular := _trial(local,x,v.x,v.y+da,at,bt)
		if not radial.valid or not angular.valid: return {"valid":false,"reason":"support derivative leaves finite contact domain"}
		var jx := Vector2((radial.support.length-trial.support.length)/dr,(radial.error-trial.error)/dr)
		var jy := Vector2((angular.support.length-trial.support.length)/da,(angular.error-trial.error)/da)
		var determinant := jx.cross(jy)
		if absf(determinant)<.000001: return {"valid":false,"reason":"singular prescribed support closure"}
		var step := Vector2(residual.cross(jy),jx.cross(residual))/determinant
		step.x=clampf(step.x,-.03,.03)
		step.y=clampf(step.y,-.2,.2)
		v-=step
	if trial.is_empty() or absf(trial.support.length-length)>SUPPORT.LENGTH_TOLERANCE or absf(trial.error)>.000001:
		return {"valid":false,"reason":"prescribed support closure not reached","trial":trial,"seed":v}
	seed=Vector2(trial.radius,trial.azimuth)
	var normal: Vector3=trial.support.frame.basis.x
	var pin_axis: Vector3=(trial.axis-normal*normal.dot(trial.axis)).normalized()
	var up := normal.cross(pin_axis).normalized()
	if up.dot(trial.support.frame.basis.y)<0:
		up=-up
		pin_axis=-pin_axis
	var lower := Transform3D(Basis(normal,up,normal.cross(up)),trial.support.center)
	var pin := lower*lower_eye
	var toward := (at+bt)*.5-pin.origin
	toward=(toward-pin.basis.x*pin.basis.x.dot(toward)).normalized()
	var zero_up := upper_eye.basis.inverse().y
	var desired := pin.basis.transposed()*(-toward)
	var angle := atan2(zero_up.cross(desired).x,zero_up.dot(desired))
	var joint := PIN.compose(pin,upper_eye,angle,minimum,maximum)
	if not joint.valid: return joint
	var cable := CABLE.route(joint.body,.0195,at,bt,true,true,Vector3.ZERO,INF,.0085)
	if not cable.valid: return cable
	var result := {"valid":true,"lower":lower,"upper":joint.body,"pin":pin,"support":trial.support,"upper_route":cable,"azimuth":trial.azimuth,"joint":joint,"iterations":iterations,"orthogonal_error":absf(trial.error)}
	for key in ["lower","upper","pin"]: result[key].origin+=datum
	result.support.center+=datum
	result.support.frame.origin+=datum
	result.support.path=Transform3D(Basis.IDENTITY,datum)*result.support.path
	for key in ["approach","departure","sheave"]: ORTHOGONAL._shift_cable(result.support[key],datum)
	ORTHOGONAL._shift_cable(result.upper_route,datum)
	return result
