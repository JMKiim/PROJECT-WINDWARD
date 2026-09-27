extends RefCounted

## Inspection-only rigid guide state. Rebuild the approved baseline rig first,
## then carry its existing wrapped arc with the moved upper block. The loaded
## production route, lower support and other fitted hardware stay unchanged.
const MOVING := preload("res://src/boat/spatial_guide_boundary.gd")
var pose := Transform3D.IDENTITY
var key := Vector3.ZERO
var valid := false

func setup(value: Transform3D,yaw: float,pitch: float,steering: float) -> void:
	pose=value
	key=Vector3(yaw,pitch,steering)
	valid=value.is_finite()

func matches(rig: Node3D,yaw: float,pitch: float) -> bool:
	return valid and rig.traveller_pose_locked and rig.traveller_pose_override==pose and Vector3(yaw,pitch,rig.tiller_angle).distance_to(key)<.000001

func apply(rig: Node3D,yaw: float,pitch: float) -> bool:
	if not matches(rig,yaw,pitch): return false
	rig.traveller_pose_locked=false
	rig.set_angles(yaw,pitch,false)
	var moved := MOVING.move(rig.route,rig.wraps,"traveller",rig.traveller.transform,pose)
	if not moved.valid:
		valid=false
		return false
	rig.traveller.transform=pose
	rig.lock_traveller_pose(pose)
	rig.route=moved.path
	rig.wraps=moved.wraps
	return true
