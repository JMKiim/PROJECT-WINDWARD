extends RefCounted

const STROKE := preload("res://src/boat/animation/sheet_stroke_source.gd")
const PULL_INPUT := preload("res://src/boat/animation/sheet_pull_input.gd")
const HIKING_FEED := preload("res://src/boat/animation/hiking_sheet_feed_profile.gd")
const SYSTEM_NAMES := ["1 Mainsheet", "2 Boom vang", "3 Cunningham", "4 Outhaul"]
# Authoring fixtures may seek the old clip; there is no live playback mode.
enum Mode { RUDDER, SHEET, DAGGERBOARD, SYSTEMS, BODY }
var actor: Node3D
var selected_system := 0
var mode := Mode.SHEET
var reference_fixture := false
var bilateral_sheet_enabled := false
var hiking_sheet_enabled := false
var requested_hike := 0.0
var requested_side := -1
var posture_pending := false
var notice := ""
var wheel_pull := PULL_INPUT.new()

func setup(value: Node3D) -> void:
	actor = value
	requested_hike = actor.hike_target
	requested_side = actor.seat_side

func select_system(value: int) -> void:
	if value < 0 or value >= SYSTEM_NAMES.size(): return
	if value == selected_system: return
	wheel_pull.pause()
	selected_system = value
	notice = ""

func input_sheet_wheel(notches: float, coarse := false) -> void:
	if not is_finite(notches) or is_zero_approx(notches): return
	notice = support_reason()
	if not notice.is_empty(): return
	var accepted := wheel_pull.request_wheel(notches,coarse)
	if is_zero_approx(accepted):
		if notches > 0 and wheel_pull.metres >= wheel_pull.maximum_metres-.000001:
			notice = "Maximum trim reached; wheel up eases immediately."
		elif notches < 0 and wheel_pull.metres <= wheel_pull.minimum_metres+.000001:
			notice = "Minimum trim reached; wheel down hauls immediately."
		else:
			notice = "Requested travel already queued; continuing current motion."

func sheet_pose_reason() -> String:
	if reference_fixture: return "Authoring fixture: not the interactive scene."
	if posture_pending: return "Finishing hand return before the requested posture. Trim is retained."
	if (actor.seat_side != -1 and not bilateral_sheet_enabled) or (not _hiking_sheet_ready() and (actor.hike > 0.000001 or actor.hike_target > 0.000001 or actor.grip_phase != "HOLD")):
		return "Sheet motion currently supports PORT / SEATED. Steering and view remain manual."
	return ""

func _hiking_sheet_ready() -> bool:
	return hiking_sheet_enabled and actor.hiking_sheet_grid!=null and wheel_pull.motion!=null and wheel_pull.motion.profile is HIKING_FEED

func support_reason() -> String:
	if selected_system != 0: return "This trim system has no hand motion yet; wheel does not change the mainsheet."
	return sheet_pose_reason()

func set_rudder(value: float) -> void:
	if not is_finite(value) or reference_fixture: return
	actor.set_amount(value)

func request_hike(value: float) -> void:
	if not is_finite(value) or reference_fixture: return
	requested_hike = clampf(value, 0.0, 1.0)
	requested_side = actor.seat_side
	if _hiking_sheet_ready():
		actor.request_hike(requested_hike)
		return
	posture_pending = not is_equal_approx(requested_hike, actor.hike_target)
	if posture_pending: wheel_pull.pause()

func request_side(value: int) -> void:
	if value not in [-1, 1] or reference_fixture: return
	requested_side = value
	requested_hike = actor.hike_target
	posture_pending = value != actor.seat_side
	if posture_pending: wheel_pull.pause()
	if posture_pending and actor.sheet_control.weight <= 0.0:
		actor.set_side(value)
		posture_pending = false

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or reference_fixture: return
	actor.sheet_study.manual_delta = delta
	actor.sheet_study.manual_revision += 1
	var live_hike := _hiking_sheet_ready()
	if live_hike:
		actor.advance_hike(delta)
		wheel_pull.motion.profile.hike = actor.hike
	wheel_pull.advance(delta,actor.amount)
	actor.sheet_control.work = wheel_pull.work
	actor.sheet_control.slip = wheel_pull.slip
	actor.sheet_control.regrip_time = wheel_pull.motion.bridge_time if wheel_pull.motion!=null else -1.0
	var target_weight := 1.0 if sheet_pose_reason().is_empty() else 0.0
	actor.sheet_control.weight = move_toward(actor.sheet_control.weight, target_weight, delta * 3.0)
	if posture_pending and actor.sheet_control.weight <= 0.0:
		if requested_side != actor.seat_side: actor.set_side(requested_side)
		actor.request_hike(requested_hike)
		posture_pending = false
	if not live_hike: actor.advance_hike(delta)
	actor.set_amount(actor.amount)

func reset_action() -> void:
	# Explicit reset only. Easing and idle return never call this.
	wheel_pull.reset()
	notice = ""

func reset_sheet_action() -> void:
	reset_action()

func reset_scenario() -> void:
	reference_fixture = false
	actor.sheet_control.weight = 0.0
	actor.sheet_study.leave()
	wheel_pull.reset()
	actor.set_side(-1)
	actor.set_hike(0.0)
	actor.set_amount(0.0)
	selected_system = 0
	mode = Mode.SHEET
	posture_pending = false
	requested_side = -1
	requested_hike = 0.0
	notice = ""

func load_sheet_reference() -> void:
	reset_scenario()
	reference_fixture = true
	actor.sheet_study.enter()

func prepare_sheet_control() -> void:
	reset_scenario()

func select_mode(value: int) -> void:
	# Test-fixture compatibility, not a numbered operation selector.
	mode = value

func seek_action(value: float) -> void:
	if reference_fixture: actor.sheet_study.seek(value)

func snapshot() -> Dictionary:
	var contacts: Dictionary = wheel_pull.motion.contact_state() if wheel_pull.motion!=null else {"sheet_holds":true,"helper_holds":false}
	return {
		"version":3, "selected_system":selected_system, "system_name":SYSTEM_NAMES[selected_system],
		"supported":support_reason().is_empty(), "reason":support_reason(), "notice":notice,
		"side":actor.seat_side, "hike":actor.hike, "hike_target":actor.hike_target,
		"hiking_sheet_supported":_hiking_sheet_ready(), "extension_span_metres":actor.extension_span,
		"requested_side":requested_side, "requested_hike":requested_hike, "posture_pending":posture_pending,
		"grip_phase":actor.grip_phase, "rudder":actor.amount,
		"sheet_enabled":actor.sheet_study.enabled, "sheet_time":actor.sheet_study.time,
		"sheet_phase":STROKE.phase(actor.sheet_study.time) if reference_fixture else wheel_pull.state,
		"wheel_pull_metres":wheel_pull.metres, "wheel_pull_target_metres":wheel_pull.target_metres,
		"wheel_pull_rate":wheel_pull.rate, "wheel_pull_limit_metres":wheel_pull.maximum_metres,
		"wheel_trim_gain":wheel_pull.wheel_gain, "wheel_cadence_rate":wheel_pull.cadence_rate,
		"wheel_pull_minimum_metres":wheel_pull.minimum_metres,
		"hand_stroke_metres":PULL_INPUT.STROKE_METRES, "regrip_required":wheel_pull.regrip_required,
		"sheet_nominal_total_metres":PULL_INPUT.LENGTH_BUDGET.DEFAULT_TOTAL_METRES,
		"sheet_length_allocation":wheel_pull.length_budget.snapshot() if wheel_pull.length_budget != null else {"configured":false},
		"wheel_easing_supported":true, "repeated_handover_supported":wheel_pull.motion!=null,
		"hand_work":wheel_pull.work, "hand_weight":actor.sheet_control.weight,
		"idle_seconds":PULL_INPUT.IDLE_SECONDS, "sheet_hand_holds":contacts.sheet_holds, "helper_holds":contacts.helper_holds,
		"handover_time":actor.sheet_control.regrip_time,
		"playing":false, "reference_fixture":reference_fixture
	}
