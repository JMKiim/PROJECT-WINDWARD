extends "res://src/preview/tack/body_balanced.gd"
var early_lean_degrees := -25.0
var contact_offset_field := Vector3.ZERO
## Explicit central weight transfer, coupled to the real tiller joint.
## Body dimensions and the endpoint seat contacts are unchanged.
func hips_at(cross: float,u: float) -> Vector3:
	var hips := super.hips_at(cross,u)
	var base_x := hips.x
	var joint: Vector3=actor.joint_boat()
	var peak := sin(PI*cross)
	hips+=Vector3(joint.x*.75,0,.20+joint.z-1.191942)*peak
	# Do not keep the centre-well duck depth when the live tiller carries
	# the stance back toward a side deck. The endpoint seating is untouched.
	hips.y+=.05*smoothstep(.5,.35,absf(base_x))-.05*smoothstep(.42,.25,absf(hips.x))
	return hips+contact_offset_field
func lean_at(u: float) -> float:
	var centre := smoothstep(.20,.40,u)*(1-smoothstep(.60,.80,u))
	var t: float=minf(u,1-u)
	var early: float=deg_to_rad(early_lean_degrees)*smoothstep(.005,.04,t)*(1-smoothstep(.10,.18,t))
	return super.lean_at(u)+deg_to_rad(lerpf(20,-20,centre))*sin(PI*coordinates_at(u).x)+early
func foot_step(side: String,u: float) -> float:
	return smoothstep(.28,.46,u) if side=="Left" else smoothstep(.54,.72,u)
func foot_lift(side: String,u: float,_step: float) -> float:
	if side=="Left": return .15*smoothstep(.20,.28,u)*(1-smoothstep(.46,.50,u))
	return .15*smoothstep(.50,.54,u)*(1-smoothstep(.72,.80,u))
func foot_fore_aft(_side: String,u: float) -> float:
	return 0.0
func tool_support(side: String) -> Vector3:
	var shoulder: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var outward := shoulder-chest
	outward.y=0
	outward=outward.normalized()
	var direction := Vector3(outward.x*.15,.35,.55+outward.z*.10).normalized()
	return actor.joint_boat()+direction*.34
func fit_foot_target(side: String,target: Vector3,u: float) -> Vector3:
	if u<=.20 or u>=.80: return target
	var hip: Vector3=actor.bone_pose_boat(side+"UpperLeg").origin
	var knee: Vector3=actor.bone_pose_boat(side+"LowerLeg").origin
	var ankle: Vector3=actor.bone_pose_boat(side+"Foot").origin
	var reach := hip.distance_to(knee)+knee.distance_to(ankle)-.005
	var square := reach*reach-pow(target.x-hip.x,2)-pow(target.y-hip.y,2)
	if square<=0: return target
	var radius := sqrt(square)
	var z := clampf(target.z,hip.z-radius,hip.z+radius)
	# A short floor step/slide is explicit placement, not stretched legs or
	# hidden IK clamping. Larger route errors remain visible to the guard.
	if absf(z-target.z)<=.075: target.z=z
	return target
