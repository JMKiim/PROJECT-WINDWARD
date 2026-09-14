extends Node

const SOURCE := preload("res://src/boat/animation/sheet_regrip_source.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
const THUMB := preload("res://src/boat/animation/helper_thumb_contact.gd")
const HELD_SEGMENTS := 128
var actor: Node3D
var time := 0.0
var trees: Array[AnimationTree] = []
var bones := PackedInt32Array()
var rope_cache := PackedVector3Array()
var rope_key := PackedVector3Array()
var rope_revision := -1
var rope_time := -1.0
var rope_trim := -1.0
var wrap_direction := {}
var wrap_sweep := {}
var contact_angles := {}
var raw_debug := PackedVector3Array()
var contact_debug := {}
var contact_frames := []
var contact_shaft_start := Vector3.ZERO
var contact_shaft_end := Vector3.ZERO

func setup(value: Node3D) -> void:
	actor = value

func prepare() -> void:
	# Load before accepting live wheel input, not on the first hand exchange.
	# Preparing twice must not add extra mixers or change the current pose.
	if trees.is_empty(): _load_clips()

func _load_clips() -> void:
	for layer in ["left_arm","right_arm"]:
		var player := AnimationPlayer.new()
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		add_child(player)
		player.root_node = player.get_path_to(actor)
		var library := AnimationLibrary.new()
		for index in SOURCE.STEERING_SAMPLES:
			library.add_animation(str(index),load(SOURCE.path(index,layer)) as Animation)
		player.add_animation_library("regrip",library)
		player.play("regrip/8")
		var tree := AnimationTree.new()
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var graph := AnimationNodeBlendTree.new()
		for branch in ["lo","hi"]:
			graph.add_node(branch,AnimationNodeAnimation.new())
			graph.add_node(branch+"_seek",AnimationNodeTimeSeek.new())
			graph.connect_node(branch+"_seek",0,branch)
		graph.add_node("mix",AnimationNodeBlend2.new())
		graph.connect_node("mix",0,"lo_seek")
		graph.connect_node("mix",1,"hi_seek")
		graph.connect_node("output",0,"mix")
		tree.tree_root = graph
		add_child(tree)
		tree.anim_player = tree.get_path_to(player)
		tree.active = true
		trees.append(tree)
		var clip: Animation = library.get_animation("8")
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			if path.get_subname_count()==0: continue
			var bone: int = actor.skeleton.find_bone(path.get_subname(0))
			if bone>=0 and bone not in bones: bones.append(bone)

func sample(value: float, weight: float) -> void:
	time = clampf(value,0,SOURCE.DURATION)
	if weight<=0: return
	if actor.hiking_sheet_grid!=null:
		if not actor.hiking_sheet_grid.sample(1.0,time,weight): push_error("Authored hiking sheet grid is unavailable for this posture")
		return
	prepare()
	var previous: Dictionary = actor.pose_mirror.capture(bones,actor.seat_side)
	var coordinate: float = (actor.amount+1)*.5*(SOURCE.STEERING_SAMPLES-1)
	var low := mini(int(coordinate),SOURCE.STEERING_SAMPLES-2)
	for tree in trees:
		var graph := tree.tree_root as AnimationNodeBlendTree
		(graph.get_node("lo") as AnimationNodeAnimation).animation = "regrip/"+str(low)
		(graph.get_node("hi") as AnimationNodeAnimation).animation = "regrip/"+str(low+1)
		tree.set("parameters/lo_seek/seek_request",time)
		tree.set("parameters/hi_seek/seek_request",time)
		tree.set("parameters/mix/blend_amount",coordinate-low)
		tree.advance(0.0)
	actor.pose_mirror.apply_sample(bones,previous,actor.seat_side,weight)

func helper_channel() -> PackedVector3Array:
	return SOURCE.helper_channel(actor.role_pose_boat("RightHand"))

func held_points() -> PackedVector3Array:
	contact_frames = THUMB.frames(actor)
	var geometry: Node = actor.sheet_study
	var hand: PackedVector3Array = actor.sheet_channel_boat()
	var pin := helper_channel()
	var normal: PackedVector3Array = geometry._work_loaded_lead(geometry.block_anchor,hand[0])
	for index in range(1,hand.size()): normal.append(hand[index])
	var supported: PackedVector3Array = geometry._work_loaded_lead(geometry.block_anchor,pin[0])
	supported.append(pin[1])
	supported.append(pin[2])
	var catch_path := _insert_grip(hand,pin,1.0)
	var regrip_path := _insert_grip(pin,hand,1.0)
	var first := normal
	var release := PackedVector3Array()
	if time < .8:
		# A real approaching hand may deflect the loaded leg, but the free
		# outlet remains on the sheet hand until the helper carries the load.
		var contact: float = 1.0-smoothstep(.002,.020,geometry._distance_to_path(pin[1],normal))
		first = _insert_grip(hand,pin,contact)
	elif time < 1.0:
		var clear := _clear_shaft(catch_path)
		var length: float = geometry._path_length(_clear_shaft(supported,"support"))
		release = geometry._truncate_path(clear,lerpf(geometry._path_length(clear),length,smoothstep(.8,1.0,time)))
	elif time < 1.75:
		first = supported
	elif time < 2.0:
		first = _insert_grip(pin,hand,smoothstep(1.75,2.0,time))
	elif time < 2.2:
		var clear := _clear_shaft(regrip_path)
		var length: float = geometry._path_length(_clear_shaft(normal,"support"))
		release = geometry._truncate_path(clear,lerpf(geometry._path_length(clear),length,smoothstep(2.0,2.2,time)))
	var result := PackedVector3Array()
	if not release.is_empty():
		result = release
	else:
		result = first.duplicate()
	raw_debug = result.duplicate()
	var hip: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftUpperLeg")).origin
	var knee: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftLowerLeg")).origin
	for index in range(1,result.size()-1):
		var near := Geometry3D.get_closest_point_to_segment(result[index],hip,knee)
		var offset := result[index]-near
		var radius := .092+GRIP.SHEET_RADIUS+.012
		if offset.length()<radius and not offset.is_zero_approx(): result[index] = near+offset.normalized()*radius
	if release.is_empty():
		var clear := _clear_shaft(result)
		result = _sample_loaded(clear)
	else:
		result = _sample_loaded(result)
		var fingers: Array = geometry._finger_supports("Left",.016)+geometry._finger_supports("Right",.016)
		var joint: Vector3 = actor.joint_boat()
		var end: Vector3 = joint+(actor.palm_boat()-joint).normalized()*actor.extension_span
		fingers.append([joint,end,.014+GRIP.SHEET_RADIUS+.0018])
		for index in range(1,result.size()):
			for contact_pass in 3:
				for support in fingers:
					var near := Geometry3D.get_closest_point_to_segment(result[index],support[0],support[1])
					var offset := result[index]-near
					if offset.length()<support[2] and not offset.is_zero_approx(): result[index]=near+offset.normalized()*support[2]
	var shaft_start: Vector3 = actor.joint_boat()
	var shaft_end: Vector3 = shaft_start+(actor.palm_boat()-shaft_start).normalized()*actor.extension_span
	contact_shaft_start = shaft_start
	contact_shaft_end = shaft_end
	for curve_pass in 4:
		if curve_pass>0: result = _sample_loaded(result)
		for index in range(1,result.size()):
			for contact_pass in 6:
				var before := result[index]
				result[index] = THUMB.project_once(result[index],contact_frames,shaft_start,shaft_end,.0198)
				var near := Geometry3D.get_closest_point_to_segment(result[index],shaft_start,shaft_end)
				var radial := result[index]-near
				if radial.length()<.0198 and not radial.is_zero_approx(): result[index] = near+radial.normalized()*.0198
				if before.distance_squared_to(result[index])<.0000000001: break
	if time>=.6 and time<=2.0:
		var closest_index := 1
		for index in range(2,result.size()-1):
			if result[index].distance_squared_to(pin[1])<result[closest_index].distance_squared_to(pin[1]): closest_index = index
		result[closest_index] = pin[1]
	return result

func _clear_shaft(path: PackedVector3Array, kind: String = "final") -> PackedVector3Array:
	var joint: Vector3 = actor.joint_boat()
	var axis: Vector3 = (actor.palm_boat()-joint).normalized()
	var end: Vector3 = joint+axis*actor.extension_span
	var normal: Vector3 = helper_channel()[1]-joint
	normal = (normal-axis*normal.dot(axis)).normalized()
	var tangent: Vector3 = axis.cross(normal).normalized()*-actor.seat_side
	var radius := .014+GRIP.SHEET_RADIUS+.0018
	var result := PackedVector3Array([path[0]])
	var index := 0
	while index<path.size()-1:
		var near := Geometry3D.get_closest_points_between_segments(path[index],path[index+1],joint,end)
		if near[0].distance_to(near[1])>=radius and not (kind=="final" and wrap_sweep.has(index)):
			result.append(path[index+1])
			index += 1
			continue
		var last := index+1
		while last<path.size()-1 and path[last].distance_to(Geometry3D.get_closest_point_to_segment(path[last],joint,end))<=radius: last += 1
		var start := path[index]
		var finish := path[last]
		var axial0 := (start-joint).dot(axis)
		var axial1 := (finish-joint).dot(axis)
		var v0 := start-joint-axis*axial0
		var v1 := finish-joint-axis*axial1
		if minf(v0.length(),v1.length())<radius:
			result.append(finish)
			index = last
			continue
		var theta0 := atan2(v0.dot(normal),v0.dot(tangent))
		var theta1 := atan2(v1.dot(normal),v1.dot(tangent))
		var offset0 := acos(clampf(radius/v0.length(),-1,1))
		var offset1 := acos(clampf(radius/v1.length(),-1,1))
		# Pick a tangent PAIR on the thumb side, never each endpoint alone.
		# Independently flipping one tangent produces an abrupt cross-shaft loop.
		var candidates := []
		for direction in [-1.0,1.0]:
			var angle: float = theta0+direction*offset0
			var finish_angle: float = theta1-direction*offset1
			var sweep: float = fposmod((finish_angle-angle)*direction,TAU)*direction
			candidates.append({"angle":angle,"sweep":sweep,"direction":direction})
		var history: PackedVector3Array = actor.sheet_study.manual_cache.slice(0,HELD_SEGMENTS+1)
		for candidate in candidates:
			candidate.cost = absf(candidate.sweep)*radius if history.is_empty() else 0.0
			if history.is_empty(): continue
			var candidate_arc: float = absf(candidate.sweep)*radius
			var candidate_lead := sqrt(maxf(0,v0.length_squared()-radius*radius))
			var candidate_length: float = candidate_lead+candidate_arc+sqrt(maxf(0,v1.length_squared()-radius*radius))
			for probe in 5:
				var u := probe/4.0
				var angle: float = candidate.angle+candidate.sweep*u
				var candidate_axial := lerpf(axial0,axial1,(candidate_lead+candidate_arc*u)/maxf(candidate_length,.000001))
				var test_point := joint+axis*candidate_axial+(tangent*cos(angle)+normal*sin(angle))*radius
				candidate.cost += actor.sheet_study._distance_to_path(test_point,history)
		var chosen: Dictionary = candidates[0] if candidates[0].cost<candidates[1].cost else candidates[1]
		if wrap_direction.has(index): chosen = candidates[0] if wrap_direction[index]<0 else candidates[1]
		if kind=="final":
			wrap_direction[index] = chosen.direction
			if wrap_sweep.has(index): chosen.sweep = wrap_sweep[index]+angle_difference(wrap_sweep[index],chosen.sweep)
			if chosen.sweep*chosen.direction<=0:
				wrap_direction.erase(index)
				wrap_sweep.erase(index)
				result.append(finish)
				index = last
				continue
			wrap_sweep[index] = chosen.sweep
		var arc: float = absf(chosen.sweep)*radius
		var lead := sqrt(maxf(0,v0.length_squared()-radius*radius))
		var total := lead+arc+sqrt(maxf(0,v1.length_squared()-radius*radius))
		for piece in 13:
			var u := piece/12.0
			var angle: float = chosen.angle+chosen.sweep*u
			var axial := lerpf(axial0,axial1,(lead+arc*u)/maxf(total,.000001))
			result.append(joint+axis*axial+(tangent*cos(angle)+normal*sin(angle))*radius)
		result.append(finish)
		index = last
	if kind=="final":
		for key in wrap_sweep.keys():
			if key>=path.size()-1:
				wrap_sweep.erase(key)
				wrap_direction.erase(key)
	return result

func _insert_grip(holder: PackedVector3Array, incoming: PackedVector3Array, weight: float) -> PackedVector3Array:
	var geometry: Node = actor.sheet_study
	var lead: PackedVector3Array = geometry._work_loaded_lead(geometry.block_anchor,holder[0])
	if weight<=0.0:
		lead.append_array(holder.slice(1))
		return lead
	# The approaching pinch starts from the already supported line, not from
	# a chord inside the shaft. Only use this guide to locate contact points;
	# the final path is wrapped once below, never wrapped a second time.
	lead = _clear_shaft(lead,"guide")
	var contact := PackedVector3Array()
	for contact_index in incoming.size():
		var point := incoming[contact_index]
		var nearest := lead[0]
		var distance := INF
		for index in lead.size()-1:
			var candidate := Geometry3D.get_closest_point_to_segment(point,lead[index],lead[index+1])
			if candidate.distance_squared_to(point)<distance:
				distance = candidate.distance_squared_to(point)
				nearest = candidate
		var joint: Vector3 = actor.joint_boat()
		var axis: Vector3 = (actor.palm_boat()-joint).normalized()
		var axial0 := (nearest-joint).dot(axis)
		var axial1 := (point-joint).dot(axis)
		var radial0 := nearest-joint-axis*axial0
		var radial1 := point-joint-axis*axial1
		var angle_key := str(incoming.size())+":"+str(contact_index)
		var angle := radial0.signed_angle_to(radial1,axis)
		if contact_angles.has(angle_key): angle = contact_angles[angle_key]+angle_difference(contact_angles[angle_key],angle)
		contact_angles[angle_key] = angle
		var radial := radial0.normalized().rotated(axis,angle*weight)
		contact.append(joint+axis*lerpf(axial0,axial1,weight)+radial*maxf(.0198,lerpf(radial0.length(),radial1.length(),weight)))
	# Insert local contact nodes; blending two entire polylines shifts their
	# unrelated arc-length coordinates and can suddenly wrap the shaft.
	var result: PackedVector3Array = geometry._work_loaded_lead(geometry.block_anchor,contact[0])
	result.append_array(contact.slice(1))
	result.append_array(holder)
	contact_debug = {"lead":str(lead),"incoming":str(incoming),"contact":str(contact),"weight":weight,"angles":str(contact_angles)}
	return result

func _sample_loaded(path: PackedVector3Array) -> PackedVector3Array:
	# Walk the polyline once. Repeated full path scans made contact sampling
	# quadratic despite the small fixed visual point count.
	var result := PackedVector3Array()
	var total: float = actor.sheet_study._path_length(path)
	var cursor := 0
	var consumed := 0.0
	var segment := path[0].distance_to(path[1])
	for index in HELD_SEGMENTS+1:
		var distance := total*index/HELD_SEGMENTS
		while cursor<path.size()-2 and consumed+segment<distance:
			consumed += segment
			cursor += 1
			segment = path[cursor].distance_to(path[cursor+1])
		result.append(path[cursor].lerp(path[cursor+1],clampf((distance-consumed)/maxf(segment,.000001),0,1)))
	return result

func _outlet_direction() -> Vector3:
	var hand: PackedVector3Array = actor.sheet_channel_boat()
	var pin := helper_channel()
	var a := (hand[-1]-hand[-2]).normalized()
	var b := (pin[-1]-pin[-2]).normalized()
	var w := smoothstep(.8,1.0,time)*(1.0-smoothstep(2.0,2.2,time))
	# The releasing outlet rolls around the side of the hand. This authored
	# turn avoids deriving its direction from a disappearing path corner.
	return (a*(1.0-w)+b*w+actor.from_port(Vector3(-.4,0,-.8))*sin(PI*w)).normalized()

func _append_tail(result: PackedVector3Array, bend_length: float) -> void:
	var geometry: Node = actor.sheet_study
	var supports: Array = geometry._tail_supports()
	var history: PackedVector3Array = geometry.manual_cache
	var dt: float = clampf(geometry.manual_delta,.0001,.02)
	var remaining: float = geometry.manual_tail_length
	var down: Vector3 = geometry.gravity_boat()
	var start := result[-1]
	var tangent := _outlet_direction()
	var turn: Vector3 = geometry._outlet_turn_offset(start,tangent,down,bend_length)
	# The low regrasp comes back up with a forward-facing channel. Route its
	# descending leg beside that channel, then roll back to the ordinary
	# outlet lane as the authored hand returns to the chest.
	var recovery_turn := smoothstep(2.2,2.35,time)*(1.0-smoothstep(2.5,2.9,time))
	var beside: Vector3 = tangent.cross(down)*-actor.seat_side
	if beside.length_squared()>.000001:
		turn = turn.lerp(beside.normalized()*.014,recovery_turn)
	var finish: Vector3 = start+tangent*bend_length+down*.012+turn
	var control1 := start+tangent*.018
	var control2 := finish-down*.012
	var curve_previous := start
	for index in range(1,9):
		var u := index/8.0
		var v := 1.0-u
		var point := start*v*v*v+control1*3*v*v*u+control2*3*v*u*u+finish*u*u*u
		var length := curve_previous.distance_to(point)
		curve_previous = point
		point = result[-1]+(point-result[-1]).normalized()*length
		point = _supported_tail_link(result[-1],point,length,supports)
		remaining -= result[-1].distance_to(point)
		result.append(point)
	var close_length := minf(.10,remaining*.4)
	var material: float = geometry._path_length(result)
	var total: float = material+remaining
	var history_length: float = geometry._path_length(history)
	var history_cursor := 0
	var history_distance := 0.0
	var outlet_speed := INF
	if history.size()==HELD_SEGMENTS+73: outlet_speed = history[HELD_SEGMENTS].distance_to(result[HELD_SEGMENTS])/dt
	var settle_angle := 3.0*dt*(1.0-smoothstep(.03,.10,outlet_speed))
	for index in 64:
		var length := close_length/12.0 if index<12 else (remaining-close_length)/52.0
		material += length
		var point := result[-1]+down*length
		if history.size()==HELD_SEGMENTS+73:
			var distance := history_length*material/total
			var segment := history[history_cursor].distance_to(history[history_cursor+1])
			while history_cursor<history.size()-2 and history_distance+segment<distance:
				history_distance += segment
				history_cursor += 1
				segment = history[history_cursor].distance_to(history[history_cursor+1])
			point = history[history_cursor].lerp(history[history_cursor+1],clampf((distance-history_distance)/maxf(segment,.000001),0,1))+down*.6*dt
		var direction := (point-result[-1]).normalized()
		if settle_angle>0:
			# A perfectly upward link is an unstable rest state, not a hanging
			# free end. Angular settling avoids normalizing it back upward.
			var angle := direction.angle_to(down)
			var axis := direction.cross(down)
			if axis.length_squared()<.00000001: axis = Vector3.RIGHT
			direction = direction.rotated(axis.normalized(),minf(angle,settle_angle))
		result.append(_supported_tail_link(result[-1],result[-1]+direction*length,length,supports))

func _supported_tail_link(start: Vector3, point: Vector3, length: float, supports: Array) -> Vector3:
	for iteration in 6:
		point = actor.sheet_study._clear_tail_segment(start,point,length,supports)
		var projected := THUMB.project_once(point,contact_frames,contact_shaft_start,contact_shaft_end,.0198)
		if projected.distance_squared_to(point)<.0000000001: break
		point = start+(projected-start).normalized()*length
	return point

func rope_points(trim: float) -> PackedVector3Array:
	var geometry: Node = actor.sheet_study
	var key: PackedVector3Array = actor.sheet_channel_boat()
	key.append_array(helper_channel())
	key.append(actor.joint_boat())
	key.append(actor.palm_boat())
	if key==rope_key and time==rope_time and trim==rope_trim and rope_revision==geometry.manual_revision: return rope_cache
	if time<rope_time or absf(time-rope_time)>.1:
		wrap_direction.clear()
		wrap_sweep.clear()
		contact_angles.clear()
	var result := held_points()
	geometry.manual_tail_length = maxf(.12,1.15+trim-geometry._path_length(result))
	var helper := smoothstep(.8,1.0,time)*(1.0-smoothstep(2.0,2.2,time))
	_append_tail(result,lerpf(.050,.025,helper))
	# Share the preceding material shape through entry/exit, not a pose clock.
	geometry.manual_cache = result
	geometry.manual_cache_key.clear()
	rope_key = key
	rope_time = time
	rope_trim = trim
	rope_revision = geometry.manual_revision
	rope_cache = result
	return result
