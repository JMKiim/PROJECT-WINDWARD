extends RefCounted
const STOPPER := preload("res://src/boat/mainsheet_stopper.gd")
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const FREE_END := preload("res://src/preview/land_drill_sheet_end.gd")
const GRAVITY_PATH := preload("res://src/preview/land_drill_sheet_drape.gd")
const LAYOUT := preload("res://src/preview/land_drill_sheet_layout.gd")
const RADIUS := .004
var hull: MeshInstance3D
var actor: Node3D
var ground := PackedVector3Array()
var arc := PackedFloat64Array()
var end_shape := PackedVector3Array()
var end_path := PackedVector3Array()
var last_result := {}
var last_signature := []
var geometry_signature := []
var routed_prefix := PackedVector3Array()
var fall_profile := PackedVector3Array()
func _caps(specs: Array) -> Array:
	var result := []
	for cap in specs:
		result.append([actor.bone_pose_boat(cap[0]).origin,actor.bone_pose_boat(cap[1]).origin,cap[2],cap[0]])
	return result
func setup(value: MeshInstance3D) -> void:
	hull=value
	last_signature.clear()
	geometry_signature.clear()
	ground.clear()
	arc.clear()
	ground=LAYOUT.generate(hull)
	for index in ground.size():
		arc.append(0 if index==0 else arc[-1]+ground[index-1].distance_to(ground[index]))
	end_shape=STOPPER.grounded_points()
	end_path=FREE_END.place(ground[0],hull)
func _at(length: float) -> Dictionary:
	var low := 0
	var high := arc.size()-1
	while high-low>1:
		var middle := (low+high)/2
		if arc[middle]<length: low=middle
		else: high=middle
	var u := clampf((length-arc[low])/maxf(.000001,arc[high]-arc[low]),0,1)
	return {"index":low,"point":ground[low].lerp(ground[high],u)}
func _surface_line(a: Vector3,b: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var count := maxi(2,int(ceil(a.distance_to(b)/.008)))
	for index in count+1:
		var point := a.lerp(b,index/float(count))
		point.y=maxf(point.y,hull.cockpit_floor_y_at(point.x,point.z)+RADIUS+.002)
		result.append(point)
	return result
func _surface_distance(a: Vector3,b: Vector3) -> float:
	return STOPPER.length_of(_surface_line(a,b))
func _prefix() -> PackedVector3Array:
	var player: Node=actor.sheet_control.regrip
	var sheet: PackedVector3Array=actor.sheet_channel_boat().slice(1,4)
	var helper: PackedVector3Array=CONTACT.helper_channel(actor.bone_pose_boat(actor.tiller_hand()+"Hand"))
	var sheet_weight := 1.0
	var helper_weight := 0.0
	if player.active_weight>0:
		if player.time<0: helper_weight=0
		elif player.time<1:
			helper_weight=1-smoothstep(.15,.25,player.time) if player.time<.5 else 0
		else:
			helper_weight=smoothstep(1,1.1,player.time)
			var progress: float=player.time-1
			sheet_weight=1-smoothstep(.12,.25,progress) if progress<.5 else smoothstep(.85,.9,progress)
	var active := smoothstep(0,1,player.active_weight)
	helper_weight*=active
	sheet_weight=lerpf(1,sheet_weight,active)
	var path := PackedVector3Array([actor.sheet_study.block_anchor])
	for point in sheet:
		var settled := Geometry3D.get_closest_point_to_segment(point,path[0],helper[0])
		path.append(settled.lerp(point,sheet_weight))
	for point in helper: path.append(sheet[-1].lerp(point,helper_weight))
	return path
func _route_prefix(path: PackedVector3Array,caps: Array) -> PackedVector3Array:
	var points := PackedVector3Array([path[0]])
	for segment in path.size()-1:
		for sample in range(1,17): points.append(path[segment].lerp(path[segment+1],sample/16.0))
	var away: Vector3=actor.from_port(Vector3.RIGHT)
	for iteration in 4:
		for index in range(1,points.size()-1):
			if index%16==0: continue
			for cap in caps:
				var nearest := Geometry3D.get_closest_point_to_segment(points[index],cap[0],cap[1])
				var distance := points[index].distance_to(nearest)
				var influence := 1-smoothstep(float(cap[2])+.006,float(cap[2])+.04,distance)
				if influence<=0: continue
				var support: float=maxf(cap[0].dot(away),cap[1].dot(away))+float(cap[2])+.018
				points[index]+=away*maxf(0,support-points[index].dot(away))*influence
	return points
func build(cockpit_metres: float) -> Dictionary:
	if actor==null or hull==null or not is_finite(cockpit_metres) or cockpit_metres<0: return {"valid":false,"reason":"missing grasp/floor or invalid amount"}
	# One finalized grasp path. Display geometry never drives the ledger.
	var prefix := _prefix()
	if prefix.size()<2: return {"valid":false,"reason":"grasp outlet missing"}
	var outlet := prefix[-1]
	var x := clampf(outlet.x,-.55,.55)
	var z := .31
	var touch := Vector3(x,hull.cockpit_floor_y_at(x,z)+RADIUS+.002,z)
	var contact_caps := _caps([["Hips","UpperChest",.164],["LeftUpperLeg","LeftLowerLeg",.104],["RightUpperLeg","RightLowerLeg",.104],["LeftLowerLeg","LeftFoot",.080],["RightLowerLeg","RightFoot",.080],["LeftFoot","LeftToes",.066],["RightFoot","RightToes",.066]])
	var route_caps := _caps([["Hips","UpperChest",.1569],["LeftUpperLeg","LeftLowerLeg",.0969],["RightUpperLeg","RightLowerLeg",.0969],["LeftLowerLeg","LeftFoot",.078],["RightLowerLeg","RightFoot",.078],["LeftFoot","LeftToes",.065],["RightFoot","RightToes",.065]])
	var signature := [prefix,cockpit_metres,actor.seat_side,contact_caps]
	if signature==last_signature and not last_result.is_empty(): return last_result
	var geometry := [prefix,actor.seat_side,contact_caps]
	if geometry!=geometry_signature:
		routed_prefix=_route_prefix(prefix,route_caps)
		fall_profile=GRAVITY_PATH.fall(outlet,touch,contact_caps,hull,actor.from_port(Vector3.RIGHT))
		geometry_signature=geometry.duplicate(true)
	prefix=routed_prefix
	var fall := fall_profile
	var routing := []
	touch=fall[-1]
	var held_length := STOPPER.length_of(prefix)
	var suspended := STOPPER.length_of(fall)
	var straight_floor := _surface_line(touch,ground[0])
	var grounded: bool=cockpit_metres-held_length>=suspended+STOPPER.length_of(straight_floor)
	if not grounded:
		var free_path := fall.duplicate()
		free_path.append_array(straight_floor.slice(1))
		free_path=FREE_END.cut(free_path,cockpit_metres-held_length)
		var result := prefix.duplicate()
		result.append_array(free_path.slice(1))
		var ending := FREE_END.place(result[-1],hull,actor)
		last_result={"valid":true,"path":result,"end_path":ending,"fall_path":free_path,"held_metres":held_length,"suspended_metres":minf(suspended,STOPPER.length_of(free_path)),"floor_metres":maxf(0,STOPPER.length_of(free_path)-suspended),"logical_cockpit_metres":cockpit_metres,"display_error_m":STOPPER.length_of(result)-cockpit_metres,"floor_points":0,"outlet":outlet,"touch":result[-1],"routing":routing,"grounded":false}
		last_result.dynamic_path=result
		last_result.pile_points=0
		last_signature=signature.duplicate(true)
		return last_result
	var available := maxf(0,cockpit_metres-held_length-suspended)
	var low := 0.0
	var high: float=minf(arc[-1],available)
	for iteration in 20:
		var middle := (low+high)*.5
		var sample := _at(middle)
		var needed: float=middle+_surface_distance(touch,sample.point)
		if needed<available: low=middle
		else: high=middle
	var sample := _at((low+high)*.5)
	var floor_path := _surface_line(touch,sample.point)
	var dynamic := prefix.duplicate()
	dynamic.append_array(fall.slice(1))
	dynamic.append_array(floor_path.slice(1))
	dynamic.append(ground[sample.index])
	for index in range(sample.index,-1,-1): floor_path.append(ground[index])
	var result := prefix.duplicate()
	result.append_array(fall.slice(1))
	result.append_array(floor_path.slice(1))
	last_result={"valid":true,"path":result,"end_path":end_path,"fall_path":fall,"held_metres":held_length,"suspended_metres":suspended,"floor_metres":STOPPER.length_of(floor_path),"logical_cockpit_metres":cockpit_metres,"display_error_m":STOPPER.length_of(result)-cockpit_metres,"floor_points":floor_path.size(),"outlet":outlet,"touch":touch,"routing":routing,"grounded":true}
	last_result.dynamic_path=dynamic
	last_result.pile_points=sample.index+1
	last_signature=signature.duplicate(true)
	return last_result
