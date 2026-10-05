extends RefCounted

## Finite supports fitted to the lab's actual skinned palms, fingertips and
## thumb web. Loaded channels remain open; a convex whole-hand shell does not
## replace the individual surfaces. CPU skin tests guard these approximations.
var supports := []
var base_count := 0

func prepare(actor: Node3D) -> void:
	supports=actor.sheet_study._tail_supports().duplicate()
	base_count=supports.size()
	# Only the final two whole-hand shells are excluded; every original body,
	# limb, shaft, finger, palm and wrist support remains unchanged.
	supports.remove_at(supports.size()-1)
	supports.remove_at(supports.size()-1)
	for side in ["Left","Right"]:
		var suffix := "_l" if side=="Left" else "_r"
		var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
		var scale := hand.basis.x.length()
		var handed := -1.0 if side=="Left" else 1.0
		for row in [[.090,.030,.020],[.105,.024,.018]]:
			supports.append([hand*Vector3(-row[1],row[0],.002),hand*Vector3(row[1],row[0],.002),row[2]*scale+.005])
		supports.append([hand*Vector3(.048*handed,.045,.004),hand*Vector3(.048*handed,.105,.004),.016*scale+.005])
		supports.append([hand*Vector3(.060*handed,.040,.013),hand*Vector3(.060*handed,.085,.013),.013*scale+.005])
		supports.append([hand*Vector3(-.017*handed,-.012,.004),hand*Vector3(-.021*handed,.015,.004),.018*scale+.005])
		for digit in [["Index","index"],["Middle","middle"],["Ring","ring"],["Little","pinky"]]:
			supports.append([actor.bone_pose_boat(side+digit[0]+"Distal").origin,actor.bone_pose_boat(digit[1]+"_04_leaf"+suffix).origin,.013])
		supports.append([actor.bone_pose_boat(side+"MiddleProximal").origin,actor.bone_pose_boat(side+"MiddleIntermediate").origin,.016])
		for pair in [["Metacarpal","Proximal",.030 if side=="Left" else .022],["Proximal","Distal",.014]]:
			supports.append([actor.bone_pose_boat(side+"Thumb"+pair[0]).origin,actor.bone_pose_boat(side+"Thumb"+pair[1]).origin,pair[2]])
		supports.append([actor.bone_pose_boat(side+"ThumbDistal").origin,actor.bone_pose_boat("thumb_04_leaf"+suffix).origin,.012])

func hand_indices(actor: Node3D,side: String) -> PackedInt32Array:
	var first := 3 if side==actor.sheet_hand() else 13
	var palm := 22 if side==actor.sheet_hand() else 25
	var result := PackedInt32Array()
	for index in range(first,first+8): result.append(index)
	for index in range(palm,palm+3): result.append(index)
	var extra := base_count-2+(0 if side=="Left" else 13)
	for index in range(extra,extra+13): result.append(index)
	return result
