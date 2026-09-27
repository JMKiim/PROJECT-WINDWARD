extends Node3D

## One material ledger connects the complete purchase, authored hand travel,
## gravity-supported cockpit lead and both finite end knots.
const RIG := preload("res://src/boat/ilca_training_rig.gd")
const COCKPIT := preload("res://src/boat/mainsheet_cockpit.gd")
const LEDGER := preload("res://src/boat/animation/mainsheet_length_budget.gd")
const FEED := preload("res://src/boat/animation/sheet_remote_feed_profile.tres")
const ENVELOPE := preload("res://src/boat/animation/training_sheet_envelope.tres")
const VIEW := preload("res://src/boat/rope_view.gd")
const END_VIEW := preload("res://src/boat/rope_tube_view.gd")
const HIKING_FEED := preload("res://src/boat/animation/hiking_sheet_feed_profile.gd")
const RIG_CONSTRAINT := preload("res://src/boat/rig_sheet_constraint.gd")
var lab: Node3D
var rig: Node3D
var cockpit := COCKPIT.new()
var ledger := LEDGER.new()
var cockpit_view: Node3D
var free_knot_view: Node3D
var configured := false
var last_result := {}
var displayed := PackedVector3Array()
var geometry_key := []
var length_envelope: Resource = ENVELOPE
var motion_profile: Resource = FEED
var requested_rig_pitch := NAN
var rig_constraint: RefCounted
var free_rig_yaw := NAN
var free_rig_gravity := Vector3.DOWN

func setup(value: Node3D) -> bool:
	lab = value
	var expanded := lab.actor.hiking_sheet_grid!=null
	if lab.continuous_sheet_enabled:
		if expanded: return false
		var reserve_path := "res://src/boat/animation/sheet_relay_envelope.tres"
		if not ResourceLoader.exists(reserve_path): return false
		length_envelope = load(reserve_path)
		motion_profile = load("res://src/boat/animation/sheet_relay_feed.tres")
		lab.actor.sheet_control.use_continuous_relay()
		cockpit.supported_lead = load("res://src/boat/mainsheet_material_lead.gd").new()
	if expanded:
		var envelope_path := "res://src/boat/animation/hiking_sheet_envelope.tres"
		if not ResourceLoader.exists(envelope_path): return false
		length_envelope = load(envelope_path)
		var measured := HIKING_FEED.new()
		if not measured.load_levels(): return false
		motion_profile = measured
	cockpit.setup(lab.actor,lab.get_node("Hull"))
	if lab.irregular_floor_enabled and not cockpit.use_pile_bank(): return false
	cockpit.purchase_join = true
	cockpit.expanded_contact_support = expanded or lab.irregular_floor_enabled
	rig = RIG.new()
	rig.name = "CompletePurchase"
	add_child(rig)
	rig.setup(lab.get_node("Hull"),lab.ratchet)
	rig_constraint = RIG_CONSTRAINT.new(rig)
	cockpit_view = VIEW.new()
	cockpit_view.name = "CockpitSheet"
	add_child(cockpit_view)
	free_knot_view = END_VIEW.new()
	free_knot_view.name = "FreeStopper"
	cockpit_view.add_child(free_knot_view)
	var maximum_rig: float = LEDGER.DEFAULT_TOTAL_METRES-length_envelope.fixed_end_metres-length_envelope.free_end_metres-length_envelope.minimum_cockpit_metres
	var initial_rig: float = lerpf(length_envelope.minimum_rig_metres,maximum_rig,.5)
	configured = ledger.configure(length_envelope.minimum_rig_metres,initial_rig,length_envelope.minimum_cockpit_metres,length_envelope.fixed_end_metres,length_envelope.free_end_metres)
	if not configured: return false
	configured = lab.session.wheel_pull.bind_length_budget(ledger) and lab.session.wheel_pull.bind_motion_profile(motion_profile)
	if not configured: return false
	lab.actor.sheet_control.regrip.prepare()
	# This scene owns the full hanging span, not the short authoring tail.
	# Pace shedding beside the fingers separately from the clear free span.
	lab.session.wheel_pull.motion.configure_supported_transitions()
	lab.actor.sheet_control.weight = 1.0
	lab.actor.sheet_control.work = lab.session.wheel_pull.work
	lab.actor.set_amount(lab.actor.amount)
	var valid := update_geometry()
	if valid and expanded:
		lab.session.bilateral_sheet_enabled = true
		lab.session.hiking_sheet_enabled = true
	return valid

func update_geometry(display := true) -> bool:
	if not configured: return false
	var actor: Node3D = lab.actor
	var key := [actor.sheet_study.manual_revision,ledger.rig_metres,ledger.cockpit_metres,actor.amount,actor.seat_side,actor.hike,actor.sheet_control.work,actor.sheet_control.regrip_time,actor.sheet_control.weight,actor.sheet_control.slip,actor.sheet_study.gravity_boat(),actor.extension_span,actor.hiking_sheet_grid,cockpit.expanded_contact_support]
	key.append_array([actor.look_enabled,actor.look_pose.yaw,actor.look_pose.pitch])
	key.append(requested_rig_pitch if is_finite(requested_rig_pitch) else "legacy")
	key.append_array([free_rig_yaw if is_finite(free_rig_yaw) else "taut",free_rig_gravity])
	key.append(rig.traveller_override if rig.traveller_override.is_finite() else "fixed traveller")
	key.append(rig.traveller_pose_override if rig.traveller_pose_locked else "loaded block")
	if key==geometry_key and last_result.get("valid",false):
		if display:
			if is_finite(free_rig_yaw):
				rig.rope_view.show_static_path(rig.route,last_result.get("surface_arrays",[]))
				rig.fixed_view.show_path(rig.fixed_end)
			elif is_finite(requested_rig_pitch):
				var current: Vector2=rig_constraint.angles()
				rig.set_angles(current.x,current.y,true)
			else: rig.set_opening(rig.opening,true)
			_show_cockpit(cockpit.last_path)
		return true
	var lead: PackedVector3Array = actor.sheet_control.regrip.held_points() if actor.sheet_control.regrip_time>=0 else actor.sheet_study.manual_held_points()
	rig.set_cockpit_lead(lead)
	if is_finite(free_rig_yaw):
		# Hauling first consumes excess length at the unloaded equilibrium; once
		# taut, retain the same pitch and solve the exact length constraint.
		rig.set_angles(free_rig_yaw,requested_rig_pitch,false)
		if ledger.rig_metres>=rig.length_metres():
			last_result=rig_constraint.drape(ledger.rig_metres,free_rig_yaw,requested_rig_pitch,free_rig_gravity,display)
		else:
			last_result=rig_constraint.fit(ledger.rig_metres,requested_rig_pitch,display)
	else:
		last_result = rig_constraint.fit(ledger.rig_metres,requested_rig_pitch,display) if is_finite(requested_rig_pitch) else rig.fit_length(ledger.rig_metres,display)
	if not last_result.valid: return false
	cockpit.rig_clearance_path = rig.route
	var path := cockpit.build(ledger.cockpit_metres,ledger.free_end_metres)
	if path.is_empty():
		last_result = {"valid":false,"reason":"Insufficient supported cockpit path","ledger":ledger.snapshot()}
		return false
	var join_error: float = rig.route[-1].distance_to(path[0])
	displayed = rig.fixed_end.duplicate()
	displayed.reverse()
	displayed.append_array(rig.route.slice(1))
	displayed.append_array(path.slice(1))
	last_result["total_error_metres"] = rig.STOPPER.length_of(displayed)-ledger.total_metres
	last_result["join_error_metres"] = join_error
	last_result["partition"] = ledger.partition(cockpit.last_partition.held,cockpit.last_partition.suspended)
	last_result["valid"] = absf(last_result.total_error_metres)<=.001 and join_error<=.0001 and last_result.partition.valid
	geometry_key = key
	if display: _show_cockpit(path)
	return last_result.valid

func try_rig_pitch(pitch: float,display := true) -> Dictionary:
	# A geometry request never consumes either line or rewrites authored poses.
	# Roll back the request if the complete material path cannot be retained.
	if not is_finite(pitch): return {"valid":false,"reason":"nonfinite pitch request"}
	var previous := requested_rig_pitch
	var previous_yaw := free_rig_yaw
	free_rig_yaw=NAN
	requested_rig_pitch=pitch
	geometry_key.clear()
	if update_geometry(display): return last_result.duplicate(true)
	var failure := last_result.duplicate(true)
	requested_rig_pitch=previous
	free_rig_yaw=previous_yaw
	geometry_key.clear()
	if not update_geometry(display): failure["restore_failed"]=true
	return failure

func clear_rig_pitch(display := true) -> bool:
	requested_rig_pitch=NAN
	free_rig_yaw=NAN
	geometry_key.clear()
	return update_geometry(display)

func try_free_rig(yaw: float,pitch: float,gravity: Vector3,display := true) -> Dictionary:
	if not is_finite(yaw) or not is_finite(pitch) or not gravity.is_finite() or gravity.length()<.0001:
		return {"valid":false,"reason":"invalid free rig request"}
	var previous := [requested_rig_pitch,free_rig_yaw,free_rig_gravity]
	requested_rig_pitch=pitch
	free_rig_yaw=yaw
	free_rig_gravity=gravity
	geometry_key.clear()
	if update_geometry(display): return last_result.duplicate(true)
	var failure := last_result.duplicate(true)
	requested_rig_pitch=previous[0]
	free_rig_yaw=previous[1]
	free_rig_gravity=previous[2]
	geometry_key.clear()
	if not update_geometry(display): failure["restore_failed"]=true
	return failure

func _show_cockpit(path: PackedVector3Array) -> void:
	var begin := maxi(0,path.size()-cockpit.ground_end.size())
	cockpit_view.show_path(path.slice(0,begin+1))
	free_knot_view.show_path(path.slice(begin))
