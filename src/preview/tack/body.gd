extends "res://src/preview/tack/body_coupled.gd"
## Two normal endpoint samples, without repeatedly sampling the side/hike
## inspection setters in between. No pose search and no second actor.
func capture(steering: float) -> void:
	endpoints.clear()
	for seat in [-1,1]:
		actor.seat_side=seat
		actor.hike=0
		actor.hike_target=0
		actor.grip_phase="HOLD"
		actor.grip_loosen=0
		actor.steering_phase="HOLD"
		actor.steering_release=0
		actor.sheet_control.weight=1
		actor.sheet_control.regrip_time=-1
		actor.sheet_control.work=.5
		actor.set_amount(steering if seat==-1 else -steering)
		var bones := []
		for bone in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(bone))
		var row := {"bones":bones,"root":actor.get_node("Pose").transform,"hip":actor.bone_pose_boat("Hips").origin,"head":actor.bone_pose_boat("Head").origin,"neck":actor.bone_pose_boat("Neck").origin,"feet":{},"palms":{},"elbows":{},"hands":{},"shoulders":{}}
		for side in ["Left","Right"]:
			row.feet[side]=actor.bone_pose_boat(side+"Foot")
			row.palms[side]=actor.palm_boat(side)
			row.elbows[side]=actor.bone_pose_boat(side+"LowerArm").origin
			row.hands[side]=actor.bone_pose_boat(side+"Hand")
			row.shoulders[side]=actor.bone_pose_boat(side+"UpperArm").origin
		endpoints[seat]=row
	actor.seat_side=-1
	actor.amount=steering
	actor.steering_target=steering
