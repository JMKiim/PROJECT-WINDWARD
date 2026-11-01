extends RefCounted
## Offline composition of the same approved endpoints. One unwrapped
## bow-facing body turn; feet withdraw before stepping over the strap.
const LIMB := preload("res://src/boat/sailor_leg_pose.gd")
var actor: Node3D
var endpoints := {}
func setup(value: Node3D) -> void: actor=value
func capture(steering: float) -> void:
	endpoints.clear()
	for seat in [-1,1]:
		actor.set_side(seat)
		actor.set_hike(0)
		actor.sheet_control.weight=1
		actor.sheet_control.regrip_time=-1
		actor.sheet_control.work=.5
		actor.set_amount(steering if seat==-1 else -steering)
		var bones := []
		for bone in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(bone))
		var row := {"bones":bones,"root":actor.get_node("Pose").transform,"hip":actor.bone_pose_boat("Hips").origin,"head":actor.bone_pose_boat("Head").origin,"neck":actor.bone_pose_boat("Neck").origin,"feet":{},"palms":{},"elbows":{},"hands":{}}
		for side in ["Left","Right"]:
			row.feet[side]=actor.bone_pose_boat(side+"Foot")
			row.palms[side]=actor.palm_boat(side)
			row.elbows[side]=actor.bone_pose_boat(side+"LowerArm").origin
			row.hands[side]=actor.bone_pose_boat(side+"Hand")
		endpoints[seat]=row
	actor.set_side(-1)
	actor.amount=steering
func sample(u: float) -> Dictionary:
	var sk: Skeleton3D=actor.skeleton
	var coordinates := coordinates_at(u)
	var cross: float=coordinates.x
	var turn: float=coordinates.y
	for index in sk.get_bone_count():
		var a: Transform3D=endpoints[-1].bones[index]
		var b: Transform3D=endpoints[1].bones[index]
		sk.set_bone_pose_position(index,a.origin.lerp(b.origin,cross))
		sk.set_bone_pose_rotation(index,a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(),cross))
		sk.set_bone_pose_scale(index,a.basis.get_scale().lerp(b.basis.get_scale(),cross))
	var pose: Node3D=actor.get_node("Pose")
	pose.basis=Basis(Vector3.UP,PI*.5+PI*turn)
	pose.position=Vector3.ZERO
	var hips: Vector3=hips_at(cross,u)
	pose.position+=hips-actor.bone_pose_boat("Hips").origin
	var lean := lean_at(u)
	if not is_zero_approx(lean):
		var spine := sk.find_bone("Spine")
		var transform := sk.get_bone_global_pose(spine)
		var to_boat: Basis=actor.skeleton_to_boat().basis if actor.has_method("skeleton_to_boat") else actor.global_basis.inverse()*sk.global_basis
		var axis := Vector3.UP.cross(pose.basis.z).normalized()
		transform.basis=to_boat.inverse()*Basis(axis,lean)*to_boat*transform.basis
		sk.set_bone_global_pose(spine,transform)
		sk.force_update_bone_child_transform(spine)
	var conversion: Transform3D=actor.skeleton_to_boat() if actor.has_method("skeleton_to_boat") else actor.global_transform.affine_inverse()*sk.global_transform
	var inverse := conversion.affine_inverse()
	var withdraw := smoothstep(0,.12,u)
	var insert := smoothstep(.88,1,u)
	var targets := {}
	var corrections := {}
	for side in ["Left","Right"]:
		var a: Transform3D=endpoints[-1].feet[side]
		var b: Transform3D=endpoints[1].feet[side]
		var step := foot_step(side,u)
		var out_a := a.origin+Vector3(-.14,0,0)*withdraw
		var out_b := b.origin+Vector3(.14,0,0)*(1-insert)
		var target := out_a.lerp(out_b,step)+Vector3.UP*foot_lift(side,u,step)
		target.z+=foot_fore_aft(side,u)
		target.x+=(-.04 if side=="Left" else .04)*sin(PI*step)
		var nominal := target
		target=fit_foot_target(side,target,u)
		corrections[side]=target-nominal
		var knee: Vector3=actor.bone_pose_boat(side+"LowerLeg").origin
		var forward := Vector3(sin(PI*.5+PI*turn),0,cos(PI*.5+PI*turn))
		var pole: Vector3=knee.lerp(target+Vector3(0,.3,0)+forward*.4,sin(PI*cross))
		LIMB.solve(sk,sk.find_bone(side+"UpperLeg"),sk.find_bone(side+"LowerLeg"),sk.find_bone(side+"Foot"),inverse*target,inverse*pole)
		var foot := sk.get_bone_global_pose(sk.find_bone(side+"Foot"))
		var expected := Basis(Vector3.UP,PI)*a.basis
		var correction := expected.inverse()*b.basis
		foot.basis=conversion.basis.inverse()*Basis(Vector3.UP,PI*step)*a.basis*Basis.IDENTITY.slerp(correction,step)
		sk.set_bone_global_pose(sk.find_bone(side+"Foot"),foot)
		sk.force_update_bone_child_transform(sk.find_bone(side+"Foot"))
		targets[side]=target
	return {"cross":cross,"turn":turn,"feet":targets,"foot_corrections":corrections}
func coordinates_at(u: float) -> Vector2:
	return Vector2(smoothstep(.15,.85,u),smoothstep(.12,.88,u))
func hips_at(cross: float,_u: float) -> Vector3:
	return (endpoints[-1].hip as Vector3).lerp(endpoints[1].hip,cross)+Vector3(0,0,.13)*sin(PI*cross)
func lean_at(_u: float) -> float: return 0.0
func foot_step(side: String,u: float) -> float:
	return smoothstep(.18,.62,u) if side=="Left" else smoothstep(.40,.85,u)
func foot_lift(_side: String,_u: float,step: float) -> float: return .13*sin(PI*step)
func foot_fore_aft(_side: String,_u: float) -> float: return 0.0
func fit_foot_target(_side: String,target: Vector3,_u: float) -> Vector3: return target
