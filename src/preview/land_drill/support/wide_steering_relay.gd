extends "res://src/boat/animation/sheet_relay_player.gd"
const CONFIG := preload("res://src/preview/land_drill/support/wide_steering_config.gd")
const TRACK_SAMPLER := preload("res://src/boat/animation/authored_track_sampler.gd")
var authored_bank: AnimationLibrary
var track_sampler := TRACK_SAMPLER.new()
var contact_sample_pass := 0
var route_channels := {}
var route_knots := PackedInt32Array()
var route_segments := PackedInt32Array()
var palm_contacts := []
var palm_bounds := []
var channel_knot_slots := {}

func held_points() -> PackedVector3Array:
	# Preserve route metadata on the same cache hit as the inherited route.
	# Clearing it before that early return lost the grip's protected knots.
	var key := [actor.sheet_study.manual_revision,time,clip_section,clip_time,actor.amount,actor.seat_side,actor.hike,actor.sheet_control.weight,actor.sheet_control.slip,actor.extension_span,actor.role_pose_boat("LeftHand"),actor.role_pose_boat("RightHand"),actor.bone_pose_boat(actor.role_bone("LeftUpperLeg")).origin,actor.bone_pose_boat(actor.role_bone("LeftLowerLeg")).origin]
	if key==held_cache_key and not held_cache.is_empty(): return held_cache.duplicate()
	contact_sample_pass=0
	route_channels.clear()
	route_knots.clear()
	route_segments.clear()
	channel_knot_slots.clear()
	palm_contacts=actor.sheet_study.palm_supports()
	palm_bounds.clear()
	for support in palm_contacts: palm_bounds.append(AABB(support[0],Vector3.ZERO).expand(support[1]).grow(support[2]))
	var result := super.held_points()
	_restore_holder_channel(result,"sheet" if time<.8 or time>=2 else "helper")
	held_cache=result.duplicate()
	return result

func _holder_channel_clear(channel: PackedVector3Array) -> bool:
	var caps := [["Hips","UpperChest",.152],["LeftUpperLeg","LeftLowerLeg",.092],["RightUpperLeg","RightLowerLeg",.092],["LeftLowerLeg","LeftFoot",.060],["RightLowerLeg","RightFoot",.060]]
	for index in channel.size()-1:
		for cap in caps:
			var pair := Geometry3D.get_closest_points_between_segments(channel[index],channel[index+1],actor.bone_pose_boat(actor.role_bone(cap[0])).origin,actor.bone_pose_boat(actor.role_bone(cap[1])).origin)
			# Retain the independent full-rope 5 mm BODY surface gap, plus
			# 0.5 mm reserve. The free-span 12 mm routing pad is not a hand
			# attachment and must not push a physically clear grip into skin.
			if pair[0].distance_to(pair[1])<cap[2]+GRIP.SHEET_RADIUS+.0055: return false
		var shaft := Geometry3D.get_closest_points_between_segments(channel[index],channel[index+1],contact_shaft_start,contact_shaft_end)
		if shaft[0].distance_to(shaft[1])<.0198: return false
	return true

func _restore_holder_channel(path: PackedVector3Array,role: String) -> void:
	if not channel_knot_slots.has(role) or not route_channels.has(role): return
	var channel: PackedVector3Array=route_channels[role]
	var slots: PackedInt32Array=channel_knot_slots[role]
	for index in channel.size()-1:
		# A real shaft detour or another hand's contact remains protected.
		# Only restore spans whose two original grip knots stayed adjacent.
		if slots[index]<0 or slots[index+1]!=slots[index]+1: continue
		if not _holder_channel_clear(channel.slice(index,index+2)): continue
		var first: int=route_knots[slots[index]]
		var last: int=route_knots[slots[index+1]]
		for knot in range(first,last+1): path[knot]=channel[index].lerp(channel[index+1],(knot-first)/float(last-first))

func helper_channel() -> PackedVector3Array:
	return actor.authored_grip.helper_channel(actor.role_pose_boat("RightHand"))

func _insert_grip(holder: PackedVector3Array,incoming: PackedVector3Array,weight: float,incoming_role: String,holder_role: String) -> PackedVector3Array:
	# A clock is not a contact. Both incoming hands must reach the strand.
	# The blend starts within one rope diameter of the authored channel;
	# the former 20 mm attraction bent the line before the grip reached it.
	# Physical skin/shaft projections remain active independently of grasp.
	var supported := _loaded_contact(holder,holder_role)
	var gap: float=actor.sheet_study._distance_to_path(incoming[2 if incoming_role=="sheet" else 1],supported)
	# Distance permits contact; it does not instantly apply a fully closed
	# incoming grip. Preserve the authored gradual handover as well. Replacing
	# its first near-zero weight with one shortened the loaded route at once.
	weight*=1.0-smoothstep(.002,2.0*GRIP.SHEET_RADIUS,gap)
	if weight<=0: return supported
	var geometry: Node=actor.sheet_study
	var joint: Vector3=actor.joint_boat()
	var axis: Vector3=(actor.palm_boat()-joint).normalized()
	var contacts := []
	for point in incoming:
		var nearest := _nearest_loaded(point,supported)
		var radial0: Vector3=nearest.point-joint-axis*(nearest.point-joint).dot(axis)
		var radial1 := point-joint-axis*(point-joint).dot(axis)
		var angle := radial0.signed_angle_to(radial1,axis)
		var axial: float=lerpf((nearest.point-joint).dot(axis),(point-joint).dot(axis),weight)
		var radial := radial0.normalized().rotated(axis,angle*weight)
		nearest.point=joint+axis*axial+radial*maxf(.0198,lerpf(radial0.length(),radial1.length(),weight))
		contacts.append(nearest)
	contacts.sort_custom(func(a,b): return a.arc<b.arc)
	# Split the already-supported strand at the incoming grip. Rebuilding a
	# block-to-hand chord and a direct hand-to-holder bridge cut the existing
	# thigh/shaft route even at a near-zero blend, changing material at contact.
	var result := supported.slice(0,contacts[0].segment+1)
	var channel := PackedVector3Array()
	for contact in contacts: channel.append(contact.point)
	result.append_array(channel)
	inserted_prefix_length=geometry._path_length(result)
	result.append_array(supported.slice(contacts[-1].segment+1))
	route_channels[incoming_role]=channel
	contact_debug={"weight":weight,"span_start":contacts[0].arc,"span_end":contacts[-1].arc,"contact":str(channel),"retained_supported_nodes":supported.size()}
	return result

func _nearest_loaded(point: Vector3,path: PackedVector3Array) -> Dictionary:
	var result := {"point":path[0],"segment":0,"arc":0.0}
	var best := INF
	var consumed := 0.0
	for index in path.size()-1:
		var nearest := Geometry3D.get_closest_point_to_segment(point,path[index],path[index+1])
		var distance := nearest.distance_squared_to(point)
		if distance<best:
			best=distance
			result={"point":nearest,"segment":index,"arc":consumed+path[index].distance_to(nearest)}
		consumed+=path[index].distance_to(path[index+1])
	return result

func _loaded_contact(channel: PackedVector3Array, role: String) -> PackedVector3Array:
	route_channels[role]=channel.duplicate()
	# Continuous guide on the finite thigh, including the rounded knee.
	# This avoids changing cylinder tangent branches beneath a moving hand.
	var start: Vector3=actor.sheet_study.block_anchor
	var hip: Vector3=actor.bone_pose_boat(actor.role_bone("LeftUpperLeg")).origin
	var knee: Vector3=actor.bone_pose_boat(actor.role_bone("LeftLowerLeg")).origin
	var radius := .092+GRIP.SHEET_RADIUS+.012
	var path := PackedVector3Array([start])
	for index in range(1,65):
		var point := start.lerp(channel[0],index/64.0)
		var near := Geometry3D.get_closest_point_to_segment(point,hip,knee)
		var radial := point-near
		if radial.length()<radius and not radial.is_zero_approx(): point=near+radial.normalized()*radius
		path.append(point)
	path.append_array(channel.slice(1))
	var topology := role+("_after" if role=="sheet" and time>=1.75 else "_before")
	return _clear_shaft(path,"load_"+topology)

func _sample_loaded(path: PackedVector3Array) -> PackedVector3Array:
	# Fingers do not enclose the palm. Retain the same loaded contact route,
	# but project its free vertices outside both physical palm supports too.
	for index in range(1,path.size()):
		for support_index in palm_contacts.size():
			if not (palm_bounds[support_index] as AABB).has_point(path[index]): continue
			var support: Array=palm_contacts[support_index]
			var near := Geometry3D.get_closest_point_to_segment(path[index],support[0],support[1])
			var offset := path[index]-near
			if offset.length()<support[2] and not offset.is_zero_approx(): path[index]=near+offset.normalized()*support[2]
	# Keep BOTH channels during a handover, including the interpolated
	# incoming contact. Resampling only the outgoing holder cut corners at
	# the other hand and made the measured length depend on sample spacing.
	if contact_sample_pass==0:
		route_knots=PackedInt32Array([0,path.size()-1])
		for channel: PackedVector3Array in route_channels.values():
			for point in channel:
				var closest := INF
				var at := -1
				for index in raw_debug.size():
					var distance := point.distance_squared_to(raw_debug[index])
					if distance<closest:
						closest=distance
						at=index
				# A channel point removed by a real shaft detour is not an
				# anchor: preserve that detour rather than restoring penetration.
				if closest<.0000000001 and at not in route_knots: route_knots.append(at)
		route_knots.sort()
		for role in route_channels:
			var slots := PackedInt32Array()
			for point: Vector3 in route_channels[role]:
				var best := -1
				for slot in route_knots.size():
					if point.distance_squared_to(raw_debug[route_knots[slot]])<.0000000001:
						best=slot
						break
				slots.append(best)
			channel_knot_slots[role]=slots
		var lengths := PackedFloat64Array()
		var total := 0.0
		for index in route_knots.size()-1:
			var length: float=actor.sheet_study._path_length(path.slice(route_knots[index],route_knots[index+1]+1))
			lengths.append(length)
			total+=length
		var remaining := HELD_SEGMENTS-lengths.size()
		var assigned := 0
		var remainders := PackedFloat64Array()
		for length in lengths:
			var quota := remaining*length/maxf(total,.000001)
			var count := 1+floori(quota)
			route_segments.append(count)
			assigned+=count
			remainders.append(quota-floor(quota))
		while assigned<HELD_SEGMENTS:
			var best := 0
			for index in remainders.size():
				if remainders[index]>remainders[best]: best=index
			route_segments[best]+=1
			remainders[best]=-1
			assigned+=1
	contact_sample_pass+=1
	var result := PackedVector3Array()
	var next_knots := PackedInt32Array([0])
	for index in route_segments.size():
		var span := _sample_span(path.slice(route_knots[index],route_knots[index+1]+1),route_segments[index])
		result.append_array(span if index==0 else span.slice(1))
		next_knots.append(result.size()-1)
	route_knots=next_knots
	return result

func _sample_span(path: PackedVector3Array,segments: int) -> PackedVector3Array:
	var total: float=actor.sheet_study._path_length(path)
	var cursor := 0
	var consumed := 0.0
	var length := path[0].distance_to(path[1])
	var result := PackedVector3Array()
	for index in segments+1:
		var distance := total*index/segments
		while cursor<path.size()-2 and consumed+length<distance:
			consumed+=length
			cursor+=1
			length=path[cursor].distance_to(path[cursor+1])
		result.append(path[cursor].lerp(path[cursor+1],clampf((distance-consumed)/maxf(length,.000001),0,1)))
	result[0]=path[0]
	result[-1]=path[-1]
	return result

func prepare() -> void:
	if not trees.is_empty(): return
	super.prepare()
	var bank := load(CONFIG.BANK) as AnimationLibrary
	authored_bank=bank
	track_sampler.configure(actor.skeleton)
	var player := get_child(0) as AnimationPlayer
	var library := AnimationLibrary.new()
	for section in ["entry","cycle"]:
		for index in CONFIG.STEERING_SAMPLES:
			library.add_animation(section+str(index),bank.get_animation(CONFIG.relay_name(section,index)))
	player.remove_animation_library("relay")
	player.add_animation_library("relay",library)
	player.play("relay/entry32")

func _sample(weight: float) -> void:
	if weight<=0: return
	prepare()
	var previous: Dictionary=actor.pose_mirror.capture(bones,actor.seat_side)
	var coordinate: float=(actor.amount+1)*.5*(CONFIG.STEERING_SAMPLES-1)
	var low := mini(int(coordinate),CONFIG.STEERING_SAMPLES-2)
	track_sampler.sample_pair(authored_bank.get_animation(CONFIG.relay_name(clip_section,low)),authored_bank.get_animation(CONFIG.relay_name(clip_section,low+1)),clip_time,coordinate-low)
	actor.pose_mirror.apply_sample(bones,previous,actor.seat_side,weight)
