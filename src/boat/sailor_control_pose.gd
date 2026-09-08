extends RefCounted

const ELBOW_CANDIDATES := 48
const CONTACT_ITERATIONS := 8
const REACH_MIN := 0.20
const REACH_MAX := 0.50
const ELBOW_FLEX_MAX := deg_to_rad(145.0)
const WRIST_BEND_MAX := deg_to_rad(45.0)
const FOREARM_RADIUS := 0.025
const FOREARM_MARGIN_MIN := 0.005
const CONTACT_RESIDUAL_MAX := 0.001
const GEOMETRY_EPSILON := 0.000001
const PREFLIGHT_POSITION_SLACK := 0.00001
const PREFLIGHT_ROTATION_SLACK := 0.001
const CACHE_ENTRY_LIMIT := 256

static var _solve_cache: Dictionary = {}
static var _solve_cache_entries := 0
static var _solve_cache_hits := 0
static var _solve_cache_misses := 0
static var _full_candidate_checks := 0
static var _deferred_candidate_checks := 0
static var _regular_candidate_rotations: Array[PackedFloat64Array] = _build_candidate_rotations(false)
static var _history_candidate_rotations: Array[PackedFloat64Array] = _build_candidate_rotations(true)


# Call before the first body/contact preview of each frame. Stored inputs are
# exact value snapshots; a hash match alone never permits reusing a pose.
static func clear_cache() -> void:
	_solve_cache.clear()
	_solve_cache_entries = 0
	_solve_cache_hits = 0
	_solve_cache_misses = 0
	_full_candidate_checks = 0
	_deferred_candidate_checks = 0


static func cache_stats() -> Dictionary:
	return {
		"entries": _solve_cache_entries, "hits": _solve_cache_hits, "misses": _solve_cache_misses,
		"full_candidate_checks": _full_candidate_checks, "deferred_candidate_checks": _deferred_candidate_checks,
	}


# All vectors and capsule endpoints must use one unscaled, metre-based frame.
# Angles in the result are radians. Only a result with safe=true may be applied.
static func solve(
	shoulder: Vector3,
	upper_length: float,
	lower_length: float,
	palm: Vector3,
	grip_axis: Vector3,
	palm_offset: Vector3,
	preferred_elbow: Vector3,
	body_capsules: Array,
	uses_tiller: bool,
	previous_hand: Dictionary = {},
	tiller_weight: float = 1.0,
	first_safe: bool = false
) -> Dictionary:
	if (
		not shoulder.is_finite() or not palm.is_finite()
		or not grip_axis.is_finite() or not palm_offset.is_finite()
		or not preferred_elbow.is_finite()
		or not is_finite(upper_length) or not is_finite(lower_length)
		or upper_length <= GEOMETRY_EPSILON or lower_length <= GEOMETRY_EPSILON
		or grip_axis.length_squared() <= GEOMETRY_EPSILON
		or palm_offset.length_squared() <= GEOMETRY_EPSILON
	):
		return _unsafe("invalid_geometry")
	var cache_axis := grip_axis
	if previous_hand.has("basis") and (not uses_tiller or tiller_weight <= 0.0):
		# A flexible palm transports the incoming hand axis. Without that history,
		# the supplied grip axis still seeds the initial hand and must stay keyed.
		cache_axis = Vector3.ZERO
	var cache_key: Array = [
		shoulder, upper_length, lower_length, palm, cache_axis, palm_offset,
		preferred_elbow, body_capsules.duplicate(true), uses_tiller,
		previous_hand.duplicate(true), tiller_weight, first_safe,
	]
	var key_hash := cache_key.hash()
	if _solve_cache.has(key_hash):
		var bucket: Array = _solve_cache[key_hash]
		for entry_variant in bucket:
			var entry: Array = entry_variant
			if entry[0] == cache_key:
				_solve_cache_hits += 1
				var cached_result: Dictionary = entry[1]
				return cached_result.duplicate(true)
	_solve_cache_misses += 1
	var result := _solve_uncached(
		shoulder, upper_length, lower_length, palm, grip_axis, palm_offset,
		preferred_elbow, body_capsules, uses_tiller, previous_hand, tiller_weight, first_safe
	)
	if not _cacheable_history(previous_hand) or String(result.get("reason", "")).begins_with("invalid_"):
		return result
	_store_cached_result(key_hash, cache_key, result)
	if bool(result.get("branch_held", false)):
		# This branch returns before first_safe is read, including its diagnostics.
		var alternate_key := cache_key.duplicate(true)
		alternate_key[alternate_key.size() - 1] = not first_safe
		_store_cached_result(alternate_key.hash(), alternate_key, result)
	return result


static func _cacheable_history(history: Dictionary) -> bool:
	for key in ["elbow", "wrist"]:
		if history.has(key):
			var point: Vector3 = history[key]
			if not point.is_finite():
				return false
	if history.has("basis"):
		var basis: Basis = history["basis"]
		if not basis.is_finite():
			return false
	for key in ["max_elbow_step_m", "max_wrist_step_m", "max_hand_rotation_rad"]:
		var limit := float(history.get(key, INF))
		if is_nan(limit) or limit < 0.0:
			return false
	return true


static func _store_cached_result(key_hash: int, key: Array, result: Dictionary) -> void:
	if _solve_cache_entries >= CACHE_ENTRY_LIMIT:
		# A bounded generation also limits memory if a caller omits its frame reset.
		_solve_cache.clear()
		_solve_cache_entries = 0
	var bucket: Array = _solve_cache.get(key_hash, [])
	bucket.append([key, result.duplicate(true)])
	_solve_cache[key_hash] = bucket
	_solve_cache_entries += 1


static func _build_candidate_rotations(with_history: bool) -> Array[PackedFloat64Array]:
	var rotations: Array[PackedFloat64Array] = [PackedFloat64Array([1.0, 0.0])]
	if with_history:
		for angle_degrees in [0.5, -0.5, 1.5, -1.5, 3.0, -3.0]:
			var angle := deg_to_rad(float(angle_degrees))
			rotations.append(PackedFloat64Array([cos(angle), sin(angle)]))
	for ring_index in range(1, ELBOW_CANDIDATES):
		var angle := TAU * float(ring_index) / float(ELBOW_CANDIDATES)
		rotations.append(PackedFloat64Array([cos(angle), sin(angle)]))
	return rotations


static func _solve_uncached(
	shoulder: Vector3,
	upper_length: float,
	lower_length: float,
	palm: Vector3,
	grip_axis: Vector3,
	palm_offset: Vector3,
	preferred_elbow: Vector3,
	body_capsules: Array,
	uses_tiller: bool,
	previous_hand: Dictionary,
	tiller_weight: float,
	first_safe: bool,
	lazy_rejections: bool = true
) -> Dictionary:
	var signed_grip_axis := grip_axis.normalized()
	var impossible_reason := _impossible_reason(
		shoulder, upper_length, lower_length, palm, signed_grip_axis,
		palm_offset, uses_tiller, previous_hand, tiller_weight
	)
	if not impossible_reason.is_empty():
		return _unsafe(impossible_reason)
	var palm_direction := (palm - shoulder).normalized()
	if palm_direction.length_squared() <= GEOMETRY_EPSILON:
		return _unsafe("palm_at_shoulder")
	var initial_basis := _hand_basis(
		signed_grip_axis, palm_direction, palm_offset, uses_tiller, Vector3.UP
	)
	if previous_hand.has("basis"):
		initial_basis = previous_hand["basis"]
	var initial_wrist := palm - initial_basis * palm_offset
	var initial_axis := (initial_wrist - shoulder).normalized()
	if not uses_tiller or tiller_weight <= 0.0:
		initial_axis = palm_direction
	var actual_previous_elbow: Vector3 = previous_hand.get("elbow", preferred_elbow)
	var has_actual_elbow := previous_hand.has("elbow")
	if not actual_previous_elbow.is_finite():
		return _unsafe("invalid_elbow_history")
	# Authored posture may change while the rendered elbow stays still. Keep its
	# continuity branch separate from the preferred working posture.
	var branch_elbow := actual_previous_elbow if has_actual_elbow else preferred_elbow
	var preferred_bend := _perpendicular(branch_elbow - shoulder, initial_axis)
	if preferred_bend.length_squared() <= GEOMETRY_EPSILON:
		preferred_bend = _stable_perpendicular(Vector3.DOWN, initial_axis)
	preferred_bend = preferred_bend.normalized()
	var circle_tangent := initial_axis.cross(preferred_bend).normalized()
	var outward := _outward_direction(shoulder, body_capsules)
	var best := _unsafe("no_safe_candidate")
	var best_score := INF
	var safe_count := 0
	var rejected: Dictionary = {}
	var rejection_cost := INF
	# Keep every candidate and its original order; only the invariant trigonometry
	# is shared. The common held-branch case no longer builds 54 angles per call.
	var candidate_rotations := _history_candidate_rotations if has_actual_elbow else _regular_candidate_rotations
	var previous_rotation := Quaternion.IDENTITY
	if previous_hand.has("basis"):
		var previous_basis: Basis = previous_hand["basis"]
		previous_rotation = previous_basis.orthonormalized().get_rotation_quaternion()
	for candidate_index in range(candidate_rotations.size()):
		var rotation: PackedFloat64Array = candidate_rotations[candidate_index]
		var branch := preferred_bend * rotation[0] + circle_tangent * rotation[1]
		var candidate := _solve_branch(
			shoulder, upper_length, lower_length, palm, signed_grip_axis,
			palm_offset, initial_wrist, branch, body_capsules, uses_tiller, initial_basis.x, tiller_weight, lazy_rejections
		)
		candidate["candidate_evaluations"] = candidate_index + 1
		_apply_continuity_guards(candidate, previous_hand, previous_rotation)
		if lazy_rejections and not bool(candidate["safe"]):
			# Every omitted term in rejection scoring is nonnegative. Once the
			# known terms cannot beat the current witness, geometry already proved
			# this branch unsafe and neither expensive check can change the result.
			var cost_lower_bound := _known_rejection_cost(candidate)
			if cost_lower_bound >= rejection_cost:
				_deferred_candidate_checks += 1
				continue
		if lazy_rejections:
			_complete_candidate_validation(
				candidate, palm, signed_grip_axis, palm_offset, body_capsules,
				uses_tiller, initial_basis.x, tiller_weight
			)
		if not bool(candidate.get("safe", false)):
			var cost := maxf(REACH_MIN - float(candidate["reach"]), 0.0) + maxf(float(candidate["reach"]) - REACH_MAX, 0.0)
			cost += maxf(FOREARM_MARGIN_MIN - float(candidate["margin"]), 0.0)
			cost += maxf(float(candidate["wrist_bend"]) - WRIST_BEND_MAX, 0.0) * 0.1
			cost += float(candidate["contact_residual"])
			cost += float(candidate.get("continuity_excess_m", 0.0))
			cost += float(candidate.get("continuity_excess_rad", 0.0)) * 0.1
			if cost < rejection_cost:
				rejection_cost = cost
				rejected = candidate
			continue
		safe_count += 1
		# Transport the rendered branch continuously while it remains fully safe.
		# Scoring another feasible branch would turn slow chest motion into
		# discrete elbow steps even when the palm contact has not changed.
		if candidate_index == 0 and has_actual_elbow:
			candidate["candidate_index"] = 0
			candidate["safe_candidate_count"] = 1
			candidate["branch_held"] = true
			return candidate
		if first_safe:
			return candidate
		var elbow: Vector3 = candidate["elbow"]
		var wrist: Vector3 = candidate["wrist"]
		var desired_height := minf(lerpf(wrist.y, shoulder.y, 0.18), shoulder.y - 0.04)
		var flare := (elbow - shoulder).dot(outward)
		var wrist_strain := maxf(float(candidate["wrist_bend"]) - deg_to_rad(20.0), 0.0)
		var desired_flare := 0.12 if uses_tiller else 0.025
		var continuity_cost := elbow.distance_squared_to(actual_previous_elbow) * 8.0
		var posture_cost := elbow.distance_squared_to(preferred_elbow) if has_actual_elbow else 0.0
		var score := (
			continuity_cost + posture_cost
			+ absf(elbow.y - desired_height) * 0.75
			+ absf(flare - desired_flare) * 1.2
			+ maxf(-flare - 0.02, 0.0) * 3.0
			+ maxf(elbow.y - shoulder.y + 0.04, 0.0) * 2.0
			+ float(candidate["wrist_bend"]) * 0.035
			+ wrist_strain * wrist_strain * 4.0
			+ maxf(0.055 - float(candidate["margin"]), 0.0) * 4.0
		)
		if score < best_score:
			best_score = score
			best = candidate
			best["score"] = score
			best["candidate_index"] = candidate_index
	best["safe_candidate_count"] = safe_count
	best["candidate_evaluations"] = candidate_rotations.size()
	if safe_count == 0:
		best["rejection"] = rejected
	return best


static func _known_rejection_cost(candidate: Dictionary) -> float:
	var cost := maxf(REACH_MIN - float(candidate["reach"]), 0.0) + maxf(float(candidate["reach"]) - REACH_MAX, 0.0)
	cost += maxf(float(candidate["wrist_bend"]) - WRIST_BEND_MAX, 0.0) * 0.1
	cost += float(candidate.get("continuity_excess_m", 0.0))
	cost += float(candidate.get("continuity_excess_rad", 0.0)) * 0.1
	return cost


static func _impossible_reason(
	shoulder: Vector3, upper_length: float, lower_length: float,
	palm: Vector3, grip_axis: Vector3, palm_offset: Vector3,
	uses_tiller: bool, history: Dictionary, tiller_weight: float
) -> String:
	var offset_length := palm_offset.length()
	var palm_distance := shoulder.distance_to(palm)
	# The wrist lies on a sphere around the palm, regardless of its orientation.
	if palm_distance > minf(REACH_MAX, upper_length + lower_length) + offset_length + PREFLIGHT_POSITION_SLACK:
		return "palm_reach_impossible"
	if palm_distance + offset_length + PREFLIGHT_POSITION_SLACK < REACH_MIN:
		return "palm_reach_impossible"
	if history.has("elbow"):
		var previous_elbow: Vector3 = history["elbow"]
		var elbow_limit := float(history.get("max_elbow_step_m", INF))
		# Reverse triangle inequality: no point inside the allowed elbow ball can
		# reach the new shoulder with an unchanged upper-arm length otherwise.
		if previous_elbow.is_finite() and is_finite(elbow_limit) and elbow_limit >= 0.0:
			if absf(shoulder.distance_to(previous_elbow) - upper_length) > elbow_limit + PREFLIGHT_POSITION_SLACK:
				return "elbow_step_impossible"
	if not history.has("basis"):
		return ""
	var previous_basis: Basis = history["basis"]
	if not previous_basis.is_finite():
		return "invalid_hand_history"
	var rotation_limit := float(history.get("max_hand_rotation_rad", INF))
	if not is_finite(rotation_limit) or rotation_limit < 0.0:
		return ""
	# A rigid grip fixes the hand's x axis. Rotating the full hand cannot cost
	# less than rotating that axis; flexible ownership does not have this bound.
	if uses_tiller and tiller_weight >= 1.0:
		if previous_basis.x.angle_to(grip_axis) > rotation_limit + PREFLIGHT_ROTATION_SLACK:
			return "rigid_axis_step_impossible"
	if history.has("wrist"):
		var previous_wrist: Vector3 = history["wrist"]
		var wrist_limit := float(history.get("max_wrist_step_m", INF))
		if previous_wrist.is_finite() and is_finite(wrist_limit) and wrist_limit >= 0.0:
			var previous_palm := previous_wrist + previous_basis * palm_offset
			# Rotating an offset through theta moves its endpoint by at most the
			# corresponding chord. Add the independent wrist translation budget.
			var rotation_chord := 2.0 * offset_length * sin(minf(rotation_limit + PREFLIGHT_ROTATION_SLACK, PI) * 0.5)
			if palm.distance_to(previous_palm) > wrist_limit + rotation_chord + PREFLIGHT_POSITION_SLACK:
				return "palm_step_impossible"
	return ""


static func _apply_continuity_guards(candidate: Dictionary, history: Dictionary, previous_rotation: Quaternion) -> void:
	var excess_m := 0.0
	var excess_rad := 0.0
	for key in ["elbow", "wrist"]:
		if not history.has(key):
			continue
		var previous: Vector3 = history[key]
		var current: Vector3 = candidate[key]
		var step := previous.distance_to(current)
		var limit := float(history.get("max_" + key + "_step_m", INF))
		candidate[key + "_step_m"] = step
		excess_m = maxf(excess_m, maxf(step - limit, 0.0))
		if not previous.is_finite() or is_nan(limit) or limit < 0.0:
			excess_m = INF
	if history.has("basis"):
		var previous_basis: Basis = history["basis"]
		var current_basis: Basis = candidate["hand_basis"]
		var rotation_step := previous_rotation.angle_to(
			current_basis.orthonormalized().get_rotation_quaternion()
		)
		var rotation_limit := float(history.get("max_hand_rotation_rad", INF))
		candidate["hand_rotation_rad"] = rotation_step
		excess_rad = maxf(rotation_step - rotation_limit, 0.0)
		if not previous_basis.is_finite() or is_nan(rotation_limit) or rotation_limit < 0.0:
			excess_rad = INF
	candidate["continuity_excess_m"] = excess_m
	candidate["continuity_excess_rad"] = excess_rad
	candidate["continuity_safe"] = excess_m <= 0.000001 and excess_rad <= 0.000001
	candidate["safe"] = bool(candidate["safe"]) and bool(candidate["continuity_safe"])


static func _solve_branch(
	shoulder: Vector3,
	upper_length: float,
	lower_length: float,
	palm: Vector3,
	grip_axis: Vector3,
	palm_offset: Vector3,
	initial_wrist: Vector3,
	initial_branch: Vector3,
	body_capsules: Array,
	uses_tiller: bool,
	initial_hand_x: Vector3,
	tiller_weight: float,
	defer_validation: bool = false
) -> Dictionary:
	var wrist := initial_wrist
	var branch := initial_branch
	var hand_basis := Basis.IDENTITY
	var hand_x := initial_hand_x
	var offset_angle := atan2(palm_offset.z, palm_offset.y)
	if not uses_tiller or tiller_weight <= 0.0:
		# With a flexible line the hand continues the forearm. Solve the extended
		# distal segment directly; an iterative wrist circle can change hemisphere
		# near a moving palm even though the exact three-point pose is continuous.
		var palm_circle := _elbow_on_branch(shoulder, palm, upper_length, lower_length + palm_offset.length(), branch)
		var elbow: Vector3 = palm_circle["elbow"]
		var forearm := (palm - elbow).normalized()
		wrist = elbow + forearm * lower_length
		branch = elbow - shoulder
		hand_basis = _hand_basis(grip_axis, forearm, palm_offset, false, hand_x, offset_angle)
	else:
		var upper_squared := upper_length * upper_length
		var lower_squared := lower_length * lower_length
		var minimum_distance := absf(upper_length - lower_length) + GEOMETRY_EPSILON
		var maximum_distance := upper_length + lower_length - GEOMETRY_EPSILON
		for _iteration in range(CONTACT_ITERATIONS):
			var previous_wrist := wrist
			var previous_branch := branch
			# The iterative circle has no observable result until its final check.
			# Keep the same arithmetic without allocating an intermediate dictionary
			# eight times for every candidate in a full handover search.
			var displacement := wrist - shoulder
			var distance := displacement.length()
			var direction := displacement.normalized() if distance > GEOMETRY_EPSILON else Vector3.DOWN
			var solved_distance := clampf(distance, minimum_distance, maximum_distance)
			var along := (solved_distance * solved_distance + upper_squared - lower_squared) / (2.0 * solved_distance)
			var radius := sqrt(maxf(upper_squared - along * along, 0.0))
			branch = _stable_perpendicular(branch, direction).normalized()
			var elbow := shoulder + direction * along + branch * radius
			hand_basis = _contact_basis(grip_axis, wrist - elbow, palm_offset, uses_tiller, hand_x, tiller_weight, offset_angle)
			wrist = palm - hand_basis * palm_offset
			# These are the complete inputs to the next iteration. A bit-identical
			# repeated state guarantees all remaining iterations repeat identically.
			if wrist == previous_wrist and branch == previous_branch:
				break
	var final_circle := _elbow_on_branch(shoulder, wrist, upper_length, lower_length, branch)
	var final_elbow: Vector3 = final_circle["elbow"]
	var upper_arm := final_elbow - shoulder
	var forearm := wrist - final_elbow
	var reach := shoulder.distance_to(wrist)
	var elbow_flex := upper_arm.angle_to(forearm)
	var wrist_bend := forearm.angle_to(palm - wrist)
	var safe := (
		bool(final_circle["reachable"])
		and wrist.is_finite() and final_elbow.is_finite() and hand_basis.is_finite()
		and reach >= REACH_MIN and reach <= REACH_MAX
		and elbow_flex <= ELBOW_FLEX_MAX and wrist_bend <= WRIST_BEND_MAX
		and final_elbow.y <= shoulder.y + 0.10
		and wrist.y <= shoulder.y + 0.20
	)
	var candidate := {
		"safe": safe,
		"wrist": wrist,
		"elbow": final_elbow,
		"hand_basis": hand_basis,
		"margin": INF,
		"reach": reach,
		"wrist_bend": wrist_bend,
		"elbow_flex": elbow_flex,
		"contact_residual": 0.0,
	}
	if not defer_validation:
		_complete_candidate_validation(candidate, palm, grip_axis, palm_offset, body_capsules, uses_tiller, initial_hand_x, tiller_weight)
	return candidate


static func _complete_candidate_validation(
	candidate: Dictionary, palm: Vector3, grip_axis: Vector3, palm_offset: Vector3,
	body_capsules: Array, uses_tiller: bool, initial_hand_x: Vector3, tiller_weight: float
) -> void:
	_full_candidate_checks += 1
	var wrist: Vector3 = candidate["wrist"]
	var elbow: Vector3 = candidate["elbow"]
	var margin := _forearm_margin(elbow, wrist, body_capsules)
	# Verify the same fixed-point function used above. Feeding the already
	# blended x-axis back into a partial grip applies ownership a second time.
	var converged_basis := _contact_basis(grip_axis, wrist - elbow, palm_offset, uses_tiller, initial_hand_x, tiller_weight)
	var residual := wrist.distance_to(palm - converged_basis * palm_offset)
	candidate["margin"] = margin
	candidate["contact_residual"] = residual
	candidate["safe"] = bool(candidate["safe"]) and margin >= FOREARM_MARGIN_MIN and residual <= CONTACT_RESIDUAL_MAX


static func _elbow_on_branch(
	shoulder: Vector3,
	wrist: Vector3,
	upper_length: float,
	lower_length: float,
	branch_hint: Vector3
) -> Dictionary:
	var displacement := wrist - shoulder
	var distance := displacement.length()
	var direction := displacement.normalized() if distance > GEOMETRY_EPSILON else Vector3.DOWN
	var minimum_distance := absf(upper_length - lower_length) + GEOMETRY_EPSILON
	var maximum_distance := upper_length + lower_length - GEOMETRY_EPSILON
	var solved_distance := clampf(distance, minimum_distance, maximum_distance)
	var along := (
		solved_distance * solved_distance + upper_length * upper_length - lower_length * lower_length
	) / (2.0 * solved_distance)
	var radius := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var bend := _stable_perpendicular(branch_hint, direction).normalized()
	return {
		"elbow": shoulder + direction * along + bend * radius,
		"bend": bend,
		"reachable": distance >= minimum_distance and distance <= maximum_distance,
	}


static func _contact_basis(axis: Vector3, forearm: Vector3, offset: Vector3, uses_tiller: bool, previous_x: Vector3, weight: float, offset_angle: float = NAN) -> Basis:
	if not uses_tiller or weight <= 0.0:
		return _hand_basis(axis, forearm, offset, false, previous_x, offset_angle)
	if weight >= 1.0:
		return _hand_basis(axis, forearm, offset, true, previous_x, offset_angle)
	var continuation := forearm.normalized()
	if continuation.length_squared() <= GEOMETRY_EPSILON:
		continuation = Vector3.DOWN
	var sheet_x := _stable_perpendicular(previous_x, continuation).normalized()
	var target_plane := _perpendicular(axis, continuation)
	if target_plane.length_squared() <= GEOMETRY_EPSILON:
		target_plane = sheet_x
	else:
		target_plane = target_plane.normalized()
	var blend := smoothstep(0.0, 1.0, weight)
	var azimuth := atan2(continuation.dot(sheet_x.cross(target_plane)), sheet_x.dot(target_plane))
	var plane := Quaternion(continuation, azimuth * blend) * sheet_x
	var axial := clampf(axis.dot(continuation) * blend, -1.0, 1.0)
	# Separate roll from bend. The resulting palm bend is asin(abs(axial)), so
	# partial ownership cannot overshoot the rigid endpoint's wrist angle.
	var hand_x := (plane * sqrt(maxf(1.0 - axial * axial, 0.0)) + continuation * axial).normalized()
	return _hand_basis(hand_x, continuation, offset, true, previous_x, offset_angle)


static func _hand_basis(
	grip_axis: Vector3,
	forearm: Vector3,
	palm_offset: Vector3,
	uses_tiller: bool,
	previous_x: Vector3,
	offset_angle: float = NAN
) -> Basis:
	var continuation := forearm.normalized()
	if continuation.length_squared() <= GEOMETRY_EPSILON:
		continuation = Vector3.DOWN
	var hand_x := grip_axis
	var palm_direction := continuation
	if uses_tiller:
		palm_direction = _stable_perpendicular(continuation, hand_x).normalized()
	else:
		# The sheet bends at the fingers. Transport the previous knuckle axis on
		# the forearm plane so a near-parallel rope cannot reverse the grip roll.
		hand_x = _stable_perpendicular(previous_x, continuation).normalized()
	if is_nan(offset_angle):
		offset_angle = atan2(palm_offset.z, palm_offset.y)
	var hand_y := (Quaternion(hand_x, -offset_angle) * palm_direction).normalized()
	var hand_z := hand_x.cross(hand_y).normalized()
	hand_y = hand_z.cross(hand_x).normalized()
	return Basis(hand_x, hand_y, hand_z).orthonormalized()


static func _forearm_margin(elbow: Vector3, wrist: Vector3, capsules: Array) -> float:
	var margin := INF
	for capsule_variant in capsules:
		var capsule: Dictionary = capsule_variant
		var label := String(capsule.get("label", ""))
		if label not in ["torso", "left_thigh", "right_thigh"]:
			continue
		var points := Geometry3D.get_closest_points_between_segments(
			elbow, wrist, capsule.get("from", Vector3.ZERO), capsule.get("to", Vector3.ZERO)
		)
		margin = minf(margin, points[0].distance_to(points[1])
			- float(capsule.get("clearance", 0.0)) - FOREARM_RADIUS
		)
	return margin


static func _outward_direction(shoulder: Vector3, capsules: Array) -> Vector3:
	for capsule_variant in capsules:
		var capsule: Dictionary = capsule_variant
		if String(capsule.get("label", "")) != "torso":
			continue
		var start: Vector3 = capsule.get("from", shoulder)
		var finish: Vector3 = capsule.get("to", shoulder)
		var outward := shoulder - start.lerp(finish, 0.80)
		outward.y = 0.0
		if outward.length_squared() > GEOMETRY_EPSILON:
			return outward.normalized()
	return Vector3.ZERO


static func _perpendicular(vector: Vector3, axis: Vector3) -> Vector3:
	return vector - axis * vector.dot(axis)


static func _stable_perpendicular(vector: Vector3, axis: Vector3) -> Vector3:
	var result := _perpendicular(vector, axis)
	if result.length_squared() > GEOMETRY_EPSILON:
		return result
	var reference := Vector3.UP if absf(axis.y) < 0.8 else Vector3.RIGHT
	return _perpendicular(reference, axis)


static func _unsafe(reason: String) -> Dictionary:
	return {
		"safe": false, "reason": reason,
		"candidate_evaluations": 0,
		"wrist": Vector3.ZERO, "elbow": Vector3.ZERO, "hand_basis": Basis.IDENTITY,
		"margin": -INF, "reach": INF, "wrist_bend": PI,
	}
