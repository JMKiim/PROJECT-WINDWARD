extends Node

const SOURCE := preload("res://src/boat/animation/sheet_stroke_source.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
const TAIL_BANK := preload("res://src/boat/animation/sheet_tail_bank.tres")
const HELD_SEGMENTS := 40
const MANUAL_HELD_SEGMENTS := 128
const TAIL_BEND_SEGMENTS := 8
const TAIL_DROP_SEGMENTS := 24
const ROPE_SEGMENTS := HELD_SEGMENTS + TAIL_BEND_SEGMENTS + TAIL_DROP_SEGMENTS
const CONTACT_CLEARANCE := 0.010
var actor: Node3D
var players: Array[AnimationPlayer] = []
var enabled := false
var playing := false
var time := 0.0
var use_baked_tail := true
var block_anchor := SOURCE.BLOCK
var manual_trim := -1.0
var manual_tail_length := 0.0
var manual_cache_key := PackedVector3Array()
var manual_cache_trim := -1.0
var manual_cache := PackedVector3Array()
var floor_surface: Callable
var deck_fitting: MeshInstance3D
var manual_delta := 1.0/60.0
var manual_revision := 0
var manual_cache_revision := -1

func setup(owner_actor: Node3D) -> void:
	actor = owner_actor
	for layer in ["left_arm", "right_arm"]:
		var player := AnimationPlayer.new()
		player.name = "Sheet_" + layer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		add_child(player)
		player.root_node = player.get_path_to(actor)
		var library := AnimationLibrary.new()
		library.add_animation(&"stroke", load("res://src/boat/animation/sheet_stroke_" + layer + ".tres") as Animation)
		player.add_animation_library(&"sheet", library)
		player.play("sheet/stroke")
		players.append(player)

func enter() -> void:
	# Explicit study cut; do not imply a sailing maneuver or simultaneous trim.
	if actor.seat_side != -1 or not is_zero_approx(actor.hike) or not is_zero_approx(actor.amount): return
	enabled = true
	playing = false
	time = 0.0
	actor.set_amount(0.0)

func leave() -> void:
	enabled = false
	playing = false
	actor.set_amount(0.0)

func seek(value: float) -> void:
	if not enabled or not is_finite(value): return
	time = clampf(value, 0.0, SOURCE.DURATION)
	actor.set_amount(0.0)

func advance(delta: float) -> void:
	if not enabled or not playing or not is_finite(delta) or delta < 0: return
	seek(time + delta)
	if time >= SOURCE.DURATION: playing = false

func sample() -> void:
	for player in players:
		player.seek(time, true, true)

func helper_boat() -> Vector3:
	return actor.role_pose_boat("RightHand") * SOURCE.ASSIST_LOCAL

func helper_channel() -> PackedVector3Array:
	var hand: Transform3D = actor.role_pose_boat("RightHand")
	var radial := SOURCE.ASSIST_LOCAL - GRIP.TILLER_OFFSET
	radial -= GRIP.TILLER_AXIS * radial.dot(GRIP.TILLER_AXIS)
	var tangent := (hand.basis * GRIP.TILLER_AXIS.cross(radial).normalized()).normalized()
	var center := helper_boat()
	if tangent.dot(center - block_anchor) < 0: tangent = -tangent
	return PackedVector3Array([center - tangent * 0.035, center, center + tangent * 0.035])

func rope_points(previous_tail: PackedVector3Array = PackedVector3Array(), relaxation_steps: int = 96) -> PackedVector3Array:
	var hand: PackedVector3Array = actor.sheet_channel_boat()
	var pin := helper_channel()
	var normal := _loaded_lead(block_anchor, hand[0])
	for index in range(1, hand.size()): normal.append(hand[index])
	var supported := _loaded_lead(block_anchor, pin[0])
	supported.append(pin[1])
	supported.append(pin[2])
	var catch_path := supported.duplicate()
	catch_path.append_array(hand)
	var regrip_path := normal.duplicate()
	regrip_path.append_array(pin)
	var first := normal
	var second := normal
	var weight := 0.0
	var release_path := PackedVector3Array()
	if time < 2.25:
		# Only a nearby physical hand can deflect the incoming sheet. The free
		# tail stays attached to the sheet hand; no airborne offer endpoint.
		var separation := _distance_to_path(pin[1], normal)
		weight = 1.0 - smoothstep(0.002, 0.020, separation)
		second = catch_path
	elif time < 2.5:
		first = catch_path
		second = supported
		weight = SOURCE.blend(time, 2.25, 2.5)
		var clear_catch := _clear_shaft(catch_path)
		var held_length := _path_length(_clear_shaft(supported))
		release_path = _truncate_path(clear_catch, lerpf(_path_length(clear_catch), held_length, weight))
	elif time < 3.35:
		first = supported
		second = supported
	elif time < 3.65:
		first = supported
		second = regrip_path
		weight = SOURCE.blend(time, 3.35, 3.65)
	elif time < 3.9:
		first = regrip_path
		second = normal
		weight = SOURCE.blend(time, 3.65, 3.9)
		var clear_regrip := _clear_shaft(regrip_path)
		var held_length := _path_length(_clear_shaft(normal))
		release_path = _truncate_path(clear_regrip, lerpf(_path_length(clear_regrip), held_length, weight))
	var result := PackedVector3Array()
	for index in HELD_SEGMENTS + 1:
		var u := float(index) / HELD_SEGMENTS
		result.append(_along(first, u).lerp(_along(second, u), weight) if release_path.is_empty() else _along(release_path, u))
	if release_path.is_empty() and first[-1].distance_to(second[-1]) > 0.000001:
		# The released outlet falls around the solid shaft, never through it.
		var outlet := _clear_shaft(PackedVector3Array([first[-1], second[-1]]))
		result[-1] = _along(outlet, weight)
	# Blending two clear routes can cut through their shared thigh support.
	# Keep the interpolated loaded span on that same physical contact envelope.
	var hip: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftUpperLeg")).origin
	var knee: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftLowerLeg")).origin
	var contact_radius := 0.092 + GRIP.SHEET_RADIUS + CONTACT_CLEARANCE
	for index in range(1, result.size() - 1):
		var support := Geometry3D.get_closest_point_to_segment(result[index], hip, knee)
		var contact_offset := result[index] - support
		if contact_offset.length() < contact_radius and not contact_offset.is_zero_approx():
			result[index] = support + contact_offset.normalized() * contact_radius
	if release_path.is_empty():
		var clear := _clear_shaft(result)
		for index in result.size(): result[index] = _along(clear, float(index) / HELD_SEGMENTS)
	else:
		# A released branch slides past the fingers before it hangs freely.
		# Shaft-only wrapping is insufficient at that moving outlet.
		var fingers := _finger_supports("Right" if time >= 3.65 else "Left", .011)
		var joint: Vector3 = actor.joint_boat()
		var shaft_end: Vector3 = joint + (actor.palm_boat() - joint).normalized() * actor.extension_span
		fingers.append([joint, shaft_end, .014 + GRIP.SHEET_RADIUS + .0018])
		for index in range(1, result.size()):
			for contact_pass in 3:
				for support in fingers:
					var near := Geometry3D.get_closest_point_to_segment(result[index], support[0], support[1])
					var offset := result[index] - near
					if offset.length() < support[2] and not offset.is_zero_approx():
						result[index] = near + offset.normalized() * support[2]
	_append_free_tail(result, previous_tail, relaxation_steps)
	return result

func manual_points(trim: float) -> PackedVector3Array:
	# A separate material-length budget survives hand return and steering.
	# The full mainsheet purchase and cockpit remainder are a later assembly.
	var hand: PackedVector3Array = actor.sheet_channel_boat()
	var key := hand.duplicate()
	key.append(actor.palm_boat())
	key.append(actor.joint_boat())
	key.append(actor.bone_pose_boat(actor.role_bone("LeftLowerArm")).origin)
	key.append(actor.bone_pose_boat("Hips").origin)
	key.append(Vector3(actor.sheet_control.slip, actor.hike, actor.seat_side))
	if key == manual_cache_key and is_equal_approx(trim, manual_cache_trim) and manual_cache_revision == manual_revision: return manual_cache
	var result := manual_held_points()
	manual_trim = trim
	# 1.15m is a lab budget, not a measured total rig length.
	manual_tail_length = maxf(0.12, 1.15 + trim - _path_length(result))
	_append_manual_tail(result)
	manual_trim = -1.0
	manual_cache_key = key
	manual_cache_trim = trim
	manual_cache = result
	manual_cache_revision = manual_revision
	return result

func manual_held_points() -> PackedVector3Array:
	var hand: PackedVector3Array = actor.sheet_channel_boat()
	var path := _work_loaded_lead(block_anchor, hand[0])
	for index in range(1, hand.size()): path.append(hand[index])
	path = _clear_shaft(path)
	var result := PackedVector3Array()
	for index in MANUAL_HELD_SEGMENTS + 1: result.append(_along(path, float(index) / MANUAL_HELD_SEGMENTS))
	var hip: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftUpperLeg")).origin
	var knee: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftLowerLeg")).origin
	for index in range(1, result.size()-1):
		var near := Geometry3D.get_closest_point_to_segment(result[index],hip,knee)
		var offset := result[index]-near
		if offset.length() < .092 + GRIP.SHEET_RADIUS + .012:
			result[index] = near + offset.normalized() * (.092 + GRIP.SHEET_RADIUS + .012)
	return result

func _append_manual_tail(result: PackedVector3Array, outlet_direction: Vector3 = Vector3.ZERO, bend_length: float = .050) -> void:
	var supports := _tail_supports()
	var remaining := manual_tail_length
	var down := gravity_boat()
	# Small authored outlet turn, then the lowest reachable clear point of
	# each inextensible segment. No frame-time relaxation or pose search.
	var start := result[-1]
	var tangent := (start-result[-2]).normalized()
	if not outlet_direction.is_zero_approx(): tangent = outlet_direction.normalized()
	# First clear the little-finger edge in the real channel direction. A
	# world-fixed sideways bend turns back into the fist in a low work pose.
	var finish := start + tangent*bend_length + down*.012 + _outlet_turn_offset(start,tangent,down,bend_length)
	var control1 := start + tangent*.018
	var control2 := finish - down*.012
	var curve_previous := start
	for index in range(1, TAIL_BEND_SEGMENTS+1):
		var u := float(index)/TAIL_BEND_SEGMENTS
		var v := 1.0-u
		var point := start*v*v*v+control1*3*v*v*u+control2*3*v*u*u+finish*u*u*u
		var length := curve_previous.distance_to(point)
		curve_previous = point
		point = result[-1]+(point-result[-1]).normalized()*length
		point = _clear_tail_segment(result[-1],point,length,supports)
		remaining -= result[-1].distance_to(point)
		result.append(point)
	var close_length := minf(.10,remaining*.4)
	for index in 64:
		var length := close_length/12.0 if index < 12 else (remaining-close_length)/52.0
		var previous := result[-1]
		var direction := down
		if manual_cache.size() == MANUAL_HELD_SEGMENTS+TAIL_BEND_SEGMENTS+65:
			var offset := MANUAL_HELD_SEGMENTS+TAIL_BEND_SEGMENTS+index
			var retained := (manual_cache[offset+1]-manual_cache[offset]).normalized()
			direction = retained.lerp(down,1.0-exp(-12.0*clampf(manual_delta,0,.067))).normalized()
		result.append(_clear_tail_segment(previous,previous+direction*length,length,supports))

func _outlet_turn_offset(_start: Vector3,tangent: Vector3,down: Vector3,_bend_length: float = .050) -> Vector3:
	# An upward outlet must turn beside its loaded leg, not return down the
	# same centreline. This small finite-radius bend is outside the grip.
	var outward := Vector3(float(actor.seat_side),0,0)
	outward = (outward-down*outward.dot(down)).normalized()
	return outward*.012*smoothstep(-1,1,-tangent.dot(down))

func _clear_tail_segment(previous: Vector3, point: Vector3, length: float, supports: Array) -> Vector3:
	if length < .000001: return previous
	var nearby := []
	for support in supports:
		var near := Geometry3D.get_closest_point_to_segment(previous,support[0],support[1])
		if previous.distance_to(near) <= support[2]+length+.003: nearby.append(support)
	for contact_pass in 16:
		var changed := false
		for support in nearby:
			var center := Geometry3D.get_closest_point_to_segment(point,support[0],support[1])
			var radius: float = support[2]+.001
			if point.distance_to(center) >= radius: continue
			changed = true
			var offset := center-previous
			var distance := offset.length()
			if distance < .000001: continue
			var normal := offset/distance
			var cosine := clampf((length*length-radius*radius+distance*distance)/(2*length*distance),-1,1)
			var direction := (point-previous).normalized()
			var tangent := direction-normal*direction.dot(normal)
			if tangent.length() < .00001:
				var guide: Vector3 = actor.from_port(Vector3(-.22,0,-.20))
				tangent = guide-normal*guide.dot(normal)
			point = previous+(normal*cosine+tangent.normalized()*sqrt(maxf(0,1-cosine*cosine)))*length
		if floor_surface.is_valid():
			var supported := _floor_segment(previous,point,length)
			changed = changed or supported.distance_to(point) > .000001
			point = supported
		if not changed: break
	return point

func _distance_to_path(point: Vector3, path: PackedVector3Array) -> float:
	var nearest := INF
	for index in path.size() - 1:
		nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, path[index], path[index + 1])))
	return nearest

func _path_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for index in path.size() - 1: length += path[index].distance_to(path[index + 1])
	return length

func _truncate_path(path: PackedVector3Array, length: float) -> PackedVector3Array:
	var result := PackedVector3Array([path[0]])
	for index in range(1, path.size()):
		var segment := path[index - 1].distance_to(path[index])
		if length <= segment:
			result.append(path[index - 1].move_toward(path[index], length))
			return result
		result.append(path[index])
		length -= segment
	return result

func _clear_shaft(path: PackedVector3Array) -> PackedVector3Array:
	var joint: Vector3 = actor.joint_boat()
	var axis: Vector3 = (actor.palm_boat() - joint).normalized()
	var end: Vector3 = joint + axis * actor.extension_span
	var radius := 0.014 + GRIP.SHEET_RADIUS + 0.0018
	var clear := PackedVector3Array([path[0]])
	var index := 0
	while index < path.size() - 1:
		var near := Geometry3D.get_closest_points_between_segments(path[index], path[index + 1], joint, end)
		if near[0].distance_to(near[1]) >= radius:
			clear.append(path[index + 1])
			index += 1
			continue
		var last := index + 1
		while last < path.size() - 1 and path[last].distance_to(Geometry3D.get_closest_point_to_segment(path[last], joint, end)) <= radius:
			last += 1
		clear.append_array(_shaft_wrap(path[index], path[last], joint, axis, radius).slice(1))
		index = last
	return clear

func _shaft_wrap(start: Vector3, finish: Vector3, joint: Vector3, axis: Vector3, radius: float) -> PackedVector3Array:
	var axial0 := (start - joint).dot(axis)
	var axial1 := (finish - joint).dot(axis)
	var v0 := start - joint - axis * axial0
	var v1 := finish - joint - axis * axial1
	if minf(v0.length(), v1.length()) < radius: return PackedVector3Array([start, finish])
	var preferred := helper_boat() - joint
	preferred -= axis * preferred.dot(axis)
	# Keep the contact frame attached to the thumb side of the shaft. A frame
	# derived from the crossing chord flips when that chord passes the axis.
	var normal := preferred.normalized()
	var tangent: Vector3 = axis.cross(normal).normalized()*-actor.seat_side
	var angle0 := atan2(v0.dot(normal), v0.dot(tangent))
	var angle1 := atan2(v1.dot(normal), v1.dot(tangent))
	var offset0 := acos(clampf(radius / v0.length(), -1, 1))
	var offset1 := acos(clampf(radius / v1.length(), -1, 1))
	angle0 += offset0 if sin(angle0 + offset0) > sin(angle0 - offset0) else -offset0
	angle1 += offset1 if sin(angle1 + offset1) > sin(angle1 - offset1) else -offset1
	var sweep := angle_difference(angle0, angle1)
	var lead := sqrt(maxf(0, v0.length_squared() - radius * radius))
	var arc := absf(sweep) * radius
	var total := lead + arc + sqrt(maxf(0, v1.length_squared() - radius * radius))
	var route := PackedVector3Array([start])
	for index in 9:
		var u := index / 8.0
		var angle := angle0 + sweep * u
		var axial := lerpf(axial0, axial1, (lead + arc * u) / maxf(total, .000001))
		route.append(joint + axis * axial + (tangent * cos(angle) + normal * sin(angle)) * radius)
	route.append(finish)
	return route

func _work_loaded_lead(start: Vector3, finish: Vector3) -> PackedVector3Array:
	return _loaded_lead(start,finish,true)

func _loaded_lead(start: Vector3, finish: Vector3, continuous_margin: bool = false) -> PackedVector3Array:
	# A taut incoming span may touch the seated thigh after the real block is
	# lowered. Use cylinder tangencies and a short supported arc, not a floating
	# guide point or a change to the authored hand/body pose.
	var a: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftUpperLeg")).origin
	var b: Vector3 = actor.bone_pose_boat(actor.role_bone("LeftLowerLeg")).origin
	var radius := 0.092 + GRIP.SHEET_RADIUS + CONTACT_CLEARANCE
	var near := Geometry3D.get_closest_points_between_segments(start, finish, a, b)
	if near[0].distance_to(near[1]) >= radius: return PackedVector3Array([start, finish])
	var axis := (b - a).normalized()
	var axial0 := (start - a).dot(axis)
	var axial1 := (finish - a).dot(axis)
	var v0 := start - a - axis * axial0
	var v1 := finish - a - axis * axial1
	var tangent := (v1 - v0).normalized()
	var normal := (v0 - tangent * v0.dot(tangent)).normalized()
	if minf(v0.length(), v1.length()) <= radius or normal.is_zero_approx():
		return PackedVector3Array([start, finish])
	var angle0 := atan2(v0.dot(normal), v0.dot(tangent))
	var angle1 := atan2(v1.dot(normal), v1.dot(tangent))
	var offset0 := acos(clampf(radius / v0.length(), -1, 1))
	var offset1 := acos(clampf(radius / v1.length(), -1, 1))
	angle0 += offset0 if sin(angle0 + offset0) > sin(angle0 - offset0) else -offset0
	angle1 += offset1 if sin(angle1 + offset1) > sin(angle1 - offset1) else -offset1
	var sweep := angle_difference(angle0, angle1)
	var lead := sqrt(maxf(0, v0.length_squared() - radius * radius))
	var trail := sqrt(maxf(0, v1.length_squared() - radius * radius))
	var arc := absf(sweep) * radius
	var length := lead + arc + trail
	var path := PackedVector3Array([start])
	for index in 7:
		var u := float(index) / 6.0
		var angle := angle0 + sweep * u
		var axial := lerpf(axial0, axial1, (lead + arc * u) / maxf(length, 0.000001))
		var point := a + axis * axial + (tangent * cos(angle) + normal * sin(angle)) * radius
		# Continue onto the rounded knee/hip cap instead of extending an
		# imaginary cylinder beyond the actual thigh support.
		var support := Geometry3D.get_closest_point_to_segment(point, a, b)
		point = support + (point - support).normalized() * radius
		path.append(point)
	path.append(finish)
	if continuous_margin:
		# The generous finger-channel inlet can be inside the extra thigh
		# margin, while the actual hand stays clear. Do not abruptly introduce
		# a long guide arc when that artificial inlet exits the margin. Blend
		# the construction guide continuously; final capsule contact projection
		# remains unchanged and is checked independently of this guide.
		var blend := smoothstep(radius,radius+.030,minf(v0.length(),v1.length()))
		var stable := PackedVector3Array()
		for index in 33:
			var u := index/32.0
			stable.append(start.lerp(finish,u).lerp(_along(path,u),blend))
		return stable
	return path

func gravity_boat() -> Vector3:
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	if not gravity.is_finite() or gravity.is_zero_approx(): gravity = Vector3.DOWN
	return (actor.global_basis.inverse() * gravity).normalized()

func _displayed_tail_length() -> float:
	if manual_trim >= 0.0: return manual_tail_length
	# Retain the previous displayed arc length, not its stiff airborne shape.
	# This remains an inspection budget, not full sheet length conservation.
	var tail := 0.18 + SOURCE.pulled_metres(time)
	var control := Vector3(0.14, 0.025, -0.22)
	var finish := Vector3(0.25, -tail, -0.38)
	var previous := Vector3.ZERO
	var length := 0.0
	for index in range(1, 13):
		var u := float(index) / 12.0
		var point := control * 2 * (1 - u) * u + finish * u * u
		length += previous.distance_to(point)
		previous = point
	return length

func _append_free_tail(result: PackedVector3Array, previous_tail: PackedVector3Array, relaxation_steps: int) -> void:
	var down := gravity_boat()
	var supports := _tail_supports()
	var exit_lane := Vector3(-0.22, 0.0, -0.20).normalized()
	var forward := exit_lane - down * exit_lane.dot(down)
	if forward.is_zero_approx(): forward = Vector3.RIGHT - down * Vector3.RIGHT.dot(down)
	forward = forward.normalized()
	var start := result[-1]
	var tangent := (start - result[-2]).normalized()
	# A small turn just outside the hand, then gravity. Keep this local bend
	# separate from the loaded line and the route around the assisting thumb.
	var control1 := start + tangent * 0.018
	var finish := start + forward * 0.033 + down * 0.025
	var control2 := finish - down * 0.018
	var remaining := _displayed_tail_length()
	for index in range(1, TAIL_BEND_SEGMENTS + 1):
		var u := float(index) / TAIL_BEND_SEGMENTS
		var v := 1.0 - u
		var point := start * v * v * v + control1 * 3 * v * v * u + control2 * 3 * v * u * u + finish * u * u * u
		# The short outlet bend can itself touch the thigh during the handover.
		# Keep its attachment outside the same surface used by the hanging span.
		for support in supports:
			var near := Geometry3D.get_closest_point_to_segment(point, support[0], support[1])
			if point.distance_to(near) < support[2]:
				point = near + (point - near).normalized() * support[2]
		remaining -= result[-1].distance_to(point)
		result.append(point)
	finish = result[-1]
	if manual_trim < 0.0 and use_baked_tail and down.distance_to(Vector3.DOWN) < 0.00001:
		var coordinate := time * TAIL_BANK.sample_rate
		var frame := mini(int(coordinate), TAIL_BANK.points.size() / TAIL_DROP_SEGMENTS - 2)
		var weight := coordinate - frame
		for index in TAIL_DROP_SEGMENTS:
			result.append(TAIL_BANK.points[frame * TAIL_DROP_SEGMENTS + index].lerp(TAIL_BANK.points[(frame + 1) * TAIL_DROP_SEGMENTS + index], weight))
		return
	var path := PackedVector3Array([finish])
	var segment_length := remaining / TAIL_DROP_SEGMENTS
	var seed := down
	for index in range(1, TAIL_DROP_SEGMENTS + 1):
		path.append(finish + seed * segment_length * index)
	if previous_tail.size() == path.size():
		var attachment_step := finish - previous_tail[0]
		for index in range(1, path.size()): path[index] = previous_tail[index] + attachment_step
	# Fixed-step authoring and the tilted-frame preview fallback only. Normal
	# neutral playback uses the bank above, with no iterative runtime solve.
	# Keep the approved pose untouched; this is not sail-force simulation.
	for iteration in relaxation_steps:
		var gravity_step := 0.008 * (1.0 - float(iteration) / relaxation_steps)
		for index in range(1, path.size()):
			var previous := path[index - 1]
			var point := path[index] + down * gravity_step
			point = previous + (point - previous).normalized() * segment_length
			for contact_pass in 8:
				var adjusted := false
				for support in supports:
					var near := Geometry3D.get_closest_point_to_segment(point, support[0], support[1])
					if point.distance_to(near) < support[2]:
						point = near + (point - near).normalized() * (support[2] + 0.00001)
						adjusted = true
					point = previous + (point - previous).normalized() * segment_length
				if manual_trim >= 0.0 and floor_surface.is_valid():
					point = _floor_segment(previous, point, segment_length)
				if not adjusted: break
			path[index] = point
	if relaxation_steps >= 96:
		# A settled, unobstructed free tip has an exact gravity solution. Finish
		# the cold-start/tilted fallback without retaining solver seed curvature.
		var settled_tip := path[-2] + down * segment_length
		var free_tip := true
		for support in supports:
			var near := Geometry3D.get_closest_points_between_segments(path[-2], settled_tip, support[0], support[1])
			if near[0].distance_to(near[1]) < support[2]:
				free_tip = false
				break
		if manual_trim >= 0.0 and floor_surface.is_valid():
			free_tip = free_tip and settled_tip.y >= float(floor_surface.call(settled_tip.x, settled_tip.z)) + GRIP.SHEET_RADIUS + .002
		if free_tip: path[-1] = settled_tip
	for index in range(1, path.size()): result.append(path[index])

func _floor_segment(previous: Vector3, point: Vector3, length: float) -> Vector3:
	var height: float = floor_surface.call(point.x, point.z)
	if point.y >= height + GRIP.SHEET_RADIUS + .002: return point
	# A fixed aft lay direction gives the small lab remainder a stable
	# floor lane. Solve the final segment on the actual dished surface.
	var low := -PI * .5
	var high := PI * .5
	for iteration in 16:
		var angle := (low + high) * .5
		var candidate := previous + Vector3(0, sin(angle), cos(angle)) * length
		var ground: float = floor_surface.call(candidate.x, candidate.z)
		if candidate.y < ground + GRIP.SHEET_RADIUS + .002: low = angle
		else: high = angle
	return previous + Vector3(0, sin(high), cos(high)) * length

func _tail_supports() -> Array:
	var supports: Array = [[actor.bone_pose_boat("Hips").origin, actor.bone_pose_boat("UpperChest").origin, 0.152 + GRIP.SHEET_RADIUS + CONTACT_CLEARANCE]]
	for prefix in [actor.sheet_hand(),actor.tiller_hand()]:
		var knee: Vector3 = actor.bone_pose_boat(prefix + "LowerLeg").origin
		supports.append([actor.bone_pose_boat(prefix + "UpperLeg").origin, knee, 0.092 + GRIP.SHEET_RADIUS + CONTACT_CLEARANCE])
		supports.append([knee, actor.bone_pose_boat(prefix + "Foot").origin, 0.060 + GRIP.SHEET_RADIUS + CONTACT_CLEARANCE])
		# During release the outlet passes beside the moving fingers. Their
		# actual bone segments support the loose line, never an airborne guide.
		supports.append_array(_finger_supports(prefix))
	var joint: Vector3 = actor.joint_boat()
	var shaft_end: Vector3 = joint + (actor.palm_boat() - joint).normalized() * actor.extension_span
	supports.append([joint, shaft_end, 0.014 + GRIP.SHEET_RADIUS + 0.0015])
	return supports

func _finger_supports(prefix: String, radius: float = .015) -> Array:
	var supports := []
	for digit in ["Index", "Middle", "Ring", "Little"]:
		var base: Vector3 = actor.bone_pose_boat(prefix + digit + "Proximal").origin
		var middle: Vector3 = actor.bone_pose_boat(prefix + digit + "Intermediate").origin
		var tip: Vector3 = actor.bone_pose_boat(prefix + digit + "Distal").origin
		# Coarser hanging segments need more point clearance than the dense
		# released branch so their chords also clear the finger surface.
		supports.append([base, middle, radius])
		supports.append([middle, tip, radius])
	return supports

func _along(path: PackedVector3Array, u: float) -> Vector3:
	var length := 0.0
	for index in path.size() - 1: length += path[index].distance_to(path[index + 1])
	var distance := length * u
	for index in path.size() - 1:
		var segment := path[index].distance_to(path[index + 1])
		if distance <= segment and segment > 0.000001:
			return path[index].lerp(path[index + 1], distance / segment)
		distance -= segment
	return path[-1]
