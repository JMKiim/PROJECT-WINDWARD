extends RefCounted

## Distance-driven use of the authored arm layers. Transition-only movement
## never feeds the rig; controlled easing may slide through the low hand.
const PROFILE := preload("res://src/boat/animation/sheet_feed_profile.gd")
const SOURCE := preload("res://src/boat/animation/sheet_regrip_source.gd")
const MAX_WORK_RATE := 1.25
const FULL_PACE_RATE := .60
var profile: Resource
var bridge_time := -1.0
var completed_handovers := 0
var settling := false
var last_feed := 0.0
var last_section := "work"
var contact_slip := 0.0
var release_speed := 1.0
var release_finish_speed := -1.0
var transition_pace_limit := 1.0
var pace := 1.0

func configure_supported_transitions() -> void:
	release_speed = .40
	release_finish_speed = .65
	transition_pace_limit = 3.0

func configure(value: Resource) -> bool:
	if not value is PROFILE or not value.valid(): return false
	profile = value
	reset()
	return true

func reset() -> void:
	bridge_time = -1.0
	completed_handovers = 0
	settling = false
	last_feed = 0.0
	last_section = "work"
	contact_slip = 0.0
	pace = 1.0

func finish_without_feed() -> void:
	settling = true

func advance(input: RefCounted, delta: float, steering: float) -> void:
	last_feed = 0.0
	input.since_input = minf(10.0,input.since_input+delta)
	# Frame-quantized wheel events must not leave a sustained high-frequency
	# request permanently slower than the incoming stream. Catch up only to
	# the accepted distance, within the same maximum feed speed.
	input.rate = maxf(input.rate,clampf(absf(input.target_metres-input.metres)/.10,input.MIN_RATE,input.MAX_RATE))
	# Preserve every authored contact; cadence changes the bounded motion clock,
	# never the accepted distance or the ordinary idle return speed.
	# Catch-up rate includes queued travel; it is not a wheel cadence signal.
	# Reach the fast authored clock at 30 full notches/s, without increasing
	# millimetres per notch. Fine or isolated input keeps the slow work clock.
	var cadence: float = clampf((input.cadence_rate-input.MIN_RATE)/(FULL_PACE_RATE-input.MIN_RATE),0.0,1.0)
	var desired_pace: float = lerpf(1.0,3.0,cadence)
	pace = move_toward(pace, desired_pace, delta * 10.0)
	if bridge_time>=0:
		_advance_bridge(input,delta,steering)
		return
	settling = false
	last_section = "work"
	var pending: float = input.target_metres-input.metres
	if absf(pending)>.0000001:
		if pending<0 and input.work<=.0000001:
			# A controlled friction release, not a stationary closed-hand haul.
			last_feed = _transfer(input,maxf(pending,-input.rate*delta))
			last_section = "controlled_ease"
			input.state = "EASE THROUGH"
			input.slip = move_toward(input.slip,1.0,delta*8.0)
			input.regrip_required = false
			return
		var requested := clampf(pending,-input.rate*delta,input.rate*delta)
		var next_work: float = profile.advance_distance("work",steering,input.work,requested)
		next_work = move_toward(input.work,next_work,MAX_WORK_RATE*pace*delta)
		var distance: float = profile.length_at("work",steering,next_work)-profile.length_at("work",steering,input.work)
		last_feed = _transfer(input,clampf(distance,minf(0,requested),maxf(0,requested)))
		input.work = profile.advance_distance("work",steering,input.work,last_feed)
		if input.work>1.0-.000002: input.work = 1.0
		if input.work<.000002: input.work = 0.0
		input.state = "HAUL" if pending>0 else "EASE"
		input.slip = move_toward(input.slip,1.0 if pending<0 else 0.0,delta*8.0)
		if input.work==1.0 and input.target_metres>input.metres+.0000001:
			bridge_time = 0.0
			input.regrip_required = true
			input.state = "HAUL / HANDOVER" if last_feed>0 else "HANDOVER"
	else:
		input.regrip_required = false
		if input.since_input>=input.IDLE_SECONDS:
			input.work = move_toward(input.work,.5,input.RETURN_RATE*delta)
			input.state = "REST" if is_equal_approx(input.work,.5) else "RETURN"
		else: input.state = "HOLD"
		input.slip = move_toward(input.slip,1.0 if input.state=="RETURN" else 0.0,delta*8.0)

func _advance_bridge(input: RefCounted, delta: float, steering: float) -> void:
	var pending: float = input.target_metres-input.metres
	var previous_slip: float = input.slip
	if pending<-.0000001:
		# A reversal may ease through the current load-bearing hand while the
		# authored exchange returns. Do not wait for the whole bridge to finish.
		settling = true
		last_feed = _transfer(input,maxf(pending,-input.rate*delta))
	var section := ""
	var start := 0.0
	var finish := 1.0
	if bridge_time>=SOURCE.HELPER_START and bridge_time<SOURCE.HELPER_FINISH:
		section = "helper"
		start = SOURCE.HELPER_START
		finish = SOURCE.HELPER_FINISH
	elif bridge_time>=2.2:
		section = "recovery"
		start = 2.2
		finish = SOURCE.DURATION
	if section.is_empty():
		var boundary := SOURCE.HELPER_START if bridge_time<SOURCE.HELPER_START else (2.0 if bridge_time<2.0 else 2.2)
		# Approach/pinch may accelerate; final transfer retains its verified
		# clock. Opening now overlaps the distance-driven helper section below.
		var speed := minf(transition_pace_limit, pace)
		if bridge_time>=2.0: speed = 1.0
		elif bridge_time>=1.75: speed = minf(speed,2.0)
		bridge_time = minf(bridge_time+delta*speed,boundary)
		input.state = "HANDOVER"
		input.slip = 0.0
	elif pending>.0000001 and not settling:
		var progress := (bridge_time-start)/(finish-start)
		var requested := minf(pending,input.rate*delta)
		var next: float = profile.advance_distance(section,steering,progress,requested)
		# The pin starts pulling while the sheet fingers release. Keep that
		# loaded-to-free transition bounded independently of the reaching arm.
		var speed := minf(pace,_release_pace()) if bridge_time<1.0 else pace
		next = minf(next,progress+speed*delta/(finish-start))
		if bridge_time<1.0: next = minf(next,(1.0-start)/(finish-start))
		var distance: float = profile.length_at(section,steering,next)-profile.length_at(section,steering,progress)
		last_feed = _transfer(input,minf(distance,requested))
		last_section = section
		var advanced: float = profile.advance_distance(section,steering,progress,last_feed)
		bridge_time = start+(finish-start)*advanced
		# The inverse table can land a few ulps below the internal opening
		# boundary. Snap the clock, not the accepted metres, so the next input
		# is not forever clamped back onto the same point.
		if absf(1.0-bridge_time)<.000002: bridge_time = 1.0
		if finish-bridge_time<.000002: bridge_time = finish
		input.state = "HELPER HAUL" if section=="helper" else "HAUL / REGRIP"
		input.slip = 0.0
	elif settling or input.since_input>=input.IDLE_SECONDS:
		# Return has an explicit sliding contact role; requested trim is fixed.
		settling = true
		var speed := minf(1.0,_release_pace()) if bridge_time<1.0 else 1.0
		var boundary := minf(1.0,finish) if bridge_time<1.0 else finish
		bridge_time = minf(boundary,bridge_time+delta*speed)
		input.state = "HANDOVER RETURN"
		input.slip = 1.0
	else:
		input.state = "HANDOVER HOLD"
		input.slip = 0.0
	if last_feed<0.0:
		input.state = "EASE / HANDOVER"
		input.slip = move_toward(previous_slip,1.0,delta*8.0)
	if bridge_time>=SOURCE.DURATION:
		bridge_time = -1.0
		input.work = .5
		input.regrip_required = false
		completed_handovers += 1
		settling = false

func _release_pace() -> float:
	# First clear the folded span beside the opening fingers. Once it has
	# left that corner, the same release can finish more quickly. Keep the
	# standalone clip clock unchanged; this gate is for the full supported line.
	if release_finish_speed<0: return release_speed
	return lerpf(release_speed,release_finish_speed,smoothstep(.90,.94,bridge_time))

func _transfer(input: RefCounted, requested: float) -> float:
	var accepted := requested
	if input.length_budget!=null: accepted = input.length_budget.transfer(requested)
	input.metres += accepted
	return accepted

func contact_state() -> Dictionary:
	var sheet_holds := bridge_time<0 or SOURCE.sheet_holds(bridge_time)
	var helper_holds := bridge_time>=0 and SOURCE.helper_holds(bridge_time)
	var held_role := "friction" if contact_slip>.01 else "grip"
	return {"sheet_holds":sheet_holds,"helper_holds":helper_holds,
		"sheet_contact":held_role if sheet_holds else "open",
		"helper_contact":held_role if helper_holds else "open",
		"phase":"WORK" if bridge_time<0 else SOURCE.phase(bridge_time)}
