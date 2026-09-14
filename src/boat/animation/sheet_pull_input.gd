extends RefCounted

## Requested trim and hand travel are independent. No unrequested feed on return.
const LENGTH_BUDGET := preload("res://src/boat/animation/mainsheet_length_budget.gd")
const REPEAT_MOTION := preload("res://src/boat/animation/sheet_repeat_motion.gd")
const METRES_PER_NOTCH := 0.020
const STROKE_METRES := 0.160
# The legacy inspection window is not the length of the complete mainsheet.
const REACH_METRES := STROKE_METRES
const MIN_RATE := 0.16
const MAX_RATE := 2.40
const IDLE_SECONDS := 0.45
const RETURN_RATE := 0.80
var active := true
var metres := 0.0
var target_metres := 0.0
var rate := MIN_RATE
var cadence_rate := MIN_RATE
var since_input := 1.0
var work := 0.5
var state := "REST"
var slip := 0.0
var minimum_metres := 0.0
var maximum_metres := REACH_METRES
var initial_metres := 0.0
var regrip_required := false
var length_budget: RefCounted
var motion: RefCounted

func bind_motion_profile(profile: Resource) -> bool:
	var candidate := REPEAT_MOTION.new()
	if not candidate.configure(profile): return false
	motion = candidate
	return true

func set_trim_bounds(minimum: float, maximum: float, initial: float) -> bool:
	if not is_finite(minimum) or not is_finite(maximum) or not is_finite(initial): return false
	if minimum >= maximum or initial < minimum or initial > maximum: return false
	length_budget = null
	minimum_metres = minimum
	maximum_metres = maximum
	initial_metres = initial
	reset()
	return true

func bind_length_budget(value: RefCounted) -> bool:
	if value == null or not value is LENGTH_BUDGET or not value.configured:
		return false
	var travel: float = value.available_haul() + value.available_ease()
	if travel <= 0.0: return false
	set_trim_bounds(0.0, travel, value.available_ease())
	length_budget = value
	return true

func _refresh_bounds() -> void:
	if length_budget == null: return
	minimum_metres = metres - length_budget.available_ease()
	maximum_metres = metres + length_budget.available_haul()
	target_metres = clampf(target_metres, minimum_metres, maximum_metres)

func complete_regrip(new_work: float) -> bool:
	# Called only after a contact-verified authored handover. It must not reset
	# applied trim, consume pending input or restart the input timeout.
	if not regrip_required or not is_finite(new_work) or new_work < 0.0 or new_work > 1.0: return false
	var direction := signf(target_metres - metres)
	if direction > 0.0 and new_work >= work: return false
	if direction < 0.0 and new_work <= work: return false
	work = new_work
	regrip_required = false
	return true

func request_pull(notches: float) -> float:
	if not active or not is_finite(notches) or is_zero_approx(notches): return 0.0
	_refresh_bounds()
	var requested := clampf(notches, -8.0, 8.0) * METRES_PER_NOTCH
	rate = clampf(absf(requested) / clampf(since_input, 0.008, 0.25), MIN_RATE, MAX_RATE)
	cadence_rate = rate
	since_input = 0.0
	# A reversal supersedes pending opposite travel, not the applied setting.
	if (target_metres - metres) * requested < 0.0: target_metres = metres
	var previous := target_metres
	target_metres = clampf(target_metres + requested, minimum_metres, maximum_metres)
	if motion!=null:
		# Bound pending travel while the hands are occupied by an exchange.
		# Return the accepted amount; never silently queue many future strokes.
		target_metres = clampf(target_metres,maxf(minimum_metres,metres-.16),minf(maximum_metres,metres+.16))
	# Reversing away from a hand-travel boundary needs no phantom regrip.
	if (target_metres - metres) * (work - 0.5) <= 0.0: regrip_required = false
	return target_metres - previous

func advance(delta: float, steering: float = 0.0) -> void:
	if not active or not is_finite(delta) or delta <= 0.0: return
	_refresh_bounds()
	if motion!=null:
		if not is_finite(steering): return
		var remaining := minf(delta,.1)
		since_input = minf(10.0,since_input+maxf(0,delta-remaining))
		var total_feed := 0.0
		while remaining>.0000001:
			var step := minf(remaining,.005)
			motion.advance(self,step,steering)
			total_feed += motion.last_feed
			remaining -= step
		motion.last_feed = total_feed
		motion.contact_slip = slip
		regrip_required = motion.bridge_time>=0.0
		if absf(total_feed)>.0000001 and state in ["HANDOVER","HANDOVER HOLD","HANDOVER RETURN","RETURN","REST"]:
			state = "HAUL / HANDOVER" if total_feed>0 else "EASE"
		return
	var previous := metres
	var requested := move_toward(metres, target_metres, rate * delta) - metres
	var permitted := clampf(requested, -work * 2.0 * STROKE_METRES, (1.0-work) * 2.0 * STROKE_METRES)
	if regrip_required: permitted = 0.0
	if length_budget != null: permitted = length_budget.transfer(permitted)
	metres += permitted
	var travel := metres - previous
	work = clampf(work + travel / (2.0 * STROKE_METRES), 0.0, 1.0)
	if work < 0.0000001: work = 0.0
	if work > 1.0-0.0000001: work = 1.0
	regrip_required = moving() and ((target_metres > metres and work >= 1.0-0.0000001) or (target_metres < metres and work <= 0.0000001))
	var previous_idle := since_input
	since_input = minf(10.0, since_input + delta)
	if absf(travel) > 0.0000001:
		state = "HAUL" if travel > 0.0 else "EASE"
	elif regrip_required:
		state = "REGRIP REQUIRED"
	elif since_input >= IDLE_SECONDS:
		var return_step := minf(delta, maxf(0.0, since_input - maxf(previous_idle, IDLE_SECONDS)))
		work = move_toward(work, 0.5, RETURN_RATE * return_step)
		state = "REST" if is_equal_approx(work, 0.5) else "RETURN"
	else:
		state = "HOLD"
	slip = move_toward(slip, 1.0 if state in ["EASE", "RETURN"] else 0.0, delta * 8.0)

func pause() -> void:
	target_metres = metres
	regrip_required = false
	if motion!=null: motion.finish_without_feed()

func reset() -> void:
	if motion!=null: motion.reset()
	if length_budget != null:
		metres += length_budget.transfer(initial_metres - metres)
	else:
		metres = initial_metres
	target_metres = metres
	work = 0.5
	rate = MIN_RATE
	cadence_rate = MIN_RATE
	since_input = 1.0
	state = "REST"
	slip = 0.0
	regrip_required = false

func moving() -> bool:
	return absf(target_metres - metres) > 0.0000001
