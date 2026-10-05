extends "res://src/boat/mainsheet_material_lead.gd"
var anatomy := []
var original_support_count := 0
var segment_rest := PackedFloat32Array()
var material_total := 0.0
var candidate_dt := 0.0
var fan_paths := []

func _length_iterations() -> int: return 12
func _surface_iterations() -> int: return 12
func _outlet_fraction(index: int) -> float: return index/8.0

func _prepare_anatomy(actor: Node3D) -> void:
	anatomy=actor.sheet_study._tail_supports().duplicate()
	original_support_count=anatomy.size()
	# The two convex whole-hand shells close real grip channels. Use the
	# persistent palm/wrist/finger surfaces on both sides of a handover.
	anatomy.remove_at(anatomy.size()-1)
	anatomy.remove_at(anatomy.size()-1)
	for side in ["Left","Right"]:
		var suffix := "_l" if side=="Left" else "_r"
		var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
		var scale := hand.basis.x.length()
		var handed := -1.0 if side=="Left" else 1.0
		for row in [[.090,.030,.020],[.105,.024,.018]]:
			anatomy.append([hand*Vector3(-row[1],row[0],.002),hand*Vector3(row[1],row[0],.002),row[2]*scale+.005])
		anatomy.append([hand*Vector3(.048*handed,.045,.004),hand*Vector3(.048*handed,.105,.004),.016*scale+.005])
		# The thenar web is skinned between palm and rotating thumb bones;
		# neither the narrow palm rim nor a thumb-bone capsule covers it.
		anatomy.append([hand*Vector3(.060*handed,.040,.013),hand*Vector3(.060*handed,.085,.013),.013*scale+.005])
		anatomy.append([hand*Vector3(-.017*handed,-.012,.004),hand*Vector3(-.021*handed,.015,.004),.018*scale+.005])
		for digit in [["Index","index"],["Middle","middle"],["Ring","ring"],["Little","pinky"]]:
			anatomy.append([actor.bone_pose_boat(side+digit[0]+"Distal").origin,actor.bone_pose_boat(digit[1]+"_04_leaf"+suffix).origin,.013])
		anatomy.append([actor.bone_pose_boat(side+"MiddleProximal").origin,actor.bone_pose_boat(side+"MiddleIntermediate").origin,.016])
		for pair in [["Metacarpal","Proximal",.030 if side=="Left" else .022],["Proximal","Distal",.014]]:
			anatomy.append([actor.bone_pose_boat(side+"Thumb"+pair[0]).origin,actor.bone_pose_boat(side+"Thumb"+pair[1]).origin,pair[2]])
		anatomy.append([actor.bone_pose_boat(side+"ThumbDistal").origin,actor.bone_pose_boat("thumb_04_leaf"+suffix).origin,.012])

func contact_prefix(held: PackedVector3Array,actor: Node3D) -> PackedVector3Array:
	_prepare_anatomy(actor)
	var result := held.duplicate()
	var player: Node=actor.sheet_control.regrip
	var helper: bool=player.time>=.8 and player.time<2.0
	var channel: PackedVector3Array=player.helper_channel() if helper else actor.sheet_channel_boat()
	var tangent := (channel[-1]-channel[-2]).normalized()
	var down: Vector3=actor.sheet_study.gravity_boat()
	var bend := .025 if helper else .050
	var start := held[-1]
	var finish: Vector3=start+tangent*bend+down*.012+actor.sheet_study._outlet_turn_offset(start,tangent,down,bend)
	var first := start+tangent*.018
	var second := finish-down*.012
	var supports := []
	for support in anatomy: supports.append([support[0],support[1],support[2]+.0021])
	var previous := start
	for index in range(1,3):
		var u := _outlet_fraction(index)
		var v := 1-u
		var point := start*v*v*v+first*3*v*v*u+second*3*v*u*u+finish*u*u*u
		var length := previous.distance_to(point)
		previous=point
		result.append(player._supported_tail_link(result[-1],point,length,supports))
	return result

func build(prefix: PackedVector3Array,ground: Vector3,actor: Node3D,hull: MeshInstance3D,rig_path: PackedVector3Array=PackedVector3Array(),expanded_contacts := false) -> PackedVector3Array:
	segment_rest.clear()
	fan_paths.clear()
	material_total=_length(full_history)+(cockpit_length-previous_cockpit) if not full_history.is_empty() else 0.0
	candidate_dt=clampf(actor.sheet_study.manual_delta,0,.067)
	var count: int=actor.sheet_study.MANUAL_HELD_SEGMENTS+1
	var physical_prefix := contact_prefix(prefix.slice(0,count),actor)
	physical_prefix.append_array(prefix.slice(count+2))
	return super.build(physical_prefix,ground,actor,hull,rig_path,expanded_contacts)

func _contacts(curve: PackedVector3Array,fixed: PackedVector3Array,fixed_groups: Array,remaining: PackedFloat32Array,supports: Array,_support_bounds: Array,hull: MeshInstance3D) -> void:
	var geometry := anatomy.duplicate()
	geometry.append_array(supports.slice(original_support_count))
	var bounds := []
	for support in geometry: bounds.append(_bounds(support[0],support[1]).grow(support[2]+.004))
	if segment_rest.size()!=curve.size()-1:
		segment_rest.clear()
		var current := _length(curve)
		var maximum := material_total-_length(fixed)+FREE_MATERIAL_SPEED*candidate_dt
		var scale := minf(1.0,maximum/maxf(current,.000001)) if material_total>0 else 1.0
		for index in curve.size()-1: segment_rest.append(curve[index].distance_to(curve[index+1])*scale)
	super._contacts(curve,fixed,fixed_groups,remaining,geometry,bounds,hull)
	for iteration in _length_iterations():
		for offset in segment_rest.size():
			var index := offset if iteration%2==0 else segment_rest.size()-1-offset
			var delta := curve[index+1]-curve[index]
			var length := delta.length()
			if length<.000001: continue
			var first := 0.0 if index==0 else 1.0
			var last := 0.0 if index+1==curve.size()-1 else 1.0
			var correction := delta*(length-segment_rest[index])/(length*(first+last))
			curve[index]+=correction*first
			curve[index+1]-=correction*last
	super._contacts(curve,fixed,fixed_groups,remaining,geometry,bounds,hull)
	var nearby := []
	for first in range(0,curve.size()-1,8):
		var group_bounds := _group_bounds(curve,first,mini(first+8,curve.size()-1)).grow(.15)
		var indices := PackedInt32Array()
		for support_index in geometry.size():
			if group_bounds.intersects(bounds[support_index]): indices.append(support_index)
		nearby.append(indices)
	for sweep in _surface_iterations():
		var changed := 0.0
		for index in curve.size()-1:
			var before_a := curve[index]
			var before_b := curve[index+1]
			var search := _bounds(before_a,before_b).grow(.03)
			for support_index in nearby[index/8]:
				if not search.intersects(bounds[support_index]): continue
				var support: Array=geometry[support_index]
				_project_link(curve,index,support[0],support[1],support[2]+.003)
			changed=maxf(changed,maxf(before_a.distance_squared_to(curve[index]),before_b.distance_squared_to(curve[index+1])))
		if changed<1e-10: break

func _clear_finger_traps(curve: PackedVector3Array,supports: Array,support_bounds: Array) -> void:
	var before := curve.duplicate()
	super._clear_finger_traps(curve,supports,support_bounds)
	fan_paths.append({"before":before,"after":curve.duplicate()})
