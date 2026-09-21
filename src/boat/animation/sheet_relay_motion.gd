extends RefCounted

## Material-distance playback of two overlapping authored strokes. There
## is no separate approach, release or recovery wait between active hauls.
const PROFILE := preload("res://src/boat/animation/sheet_relay_profile.gd")
const SOURCE := preload("res://src/boat/animation/sheet_relay_source.gd")
const MAX_HAND_SPEED := 4.8
const MAX_RETURN_SPEED := 6.5
# Reserve room below the total-motion ceiling for simultaneous steering.
const RETURN_PATH_SPEED := MAX_RETURN_SPEED-.15
const MAX_FEED_SPEED := 4.8
const MAX_EASE_SPEED := 3.6
const WHEEL_ARRIVAL_SECONDS := .035
const FEED_ACCELERATION := 18.0
var profile: Resource
var bridge_time := -1.0
var completed_handovers := 0
var settling := false
var last_feed := 0.0
var last_section := "work"
var contact_slip := 0.0
var pace := 1.0
var feed_rate := 0.0
var feed_direction := 0.0

func configure(value: Resource) -> bool:
	if not value is PROFILE or not value.valid(): return false
	profile = value
	reset()
	return true

func configure_supported_transitions() -> void: pass

func reset() -> void:
	bridge_time = -1
	completed_handovers = 0
	settling = false
	last_feed = 0
	last_section = "work"
	contact_slip = 0
	pace = 1
	feed_rate = 0
	feed_direction = 0

func finish_without_feed() -> void:
	settling = true

func advance(input: RefCounted,delta: float,steering: float) -> void:
	last_feed = 0
	input.since_input = minf(10,input.since_input+delta)
	var pending: float = input.target_metres-input.metres
	var rate: float = input.rate
	var paced_wheel: bool = input.wheel_gesture_enabled
	if input.wheel_gesture_enabled:
		# Follow physical wheel cadence; draining each packet in 50 ms makes
		# a sustained slower gesture stop before its next detent arrives.
		rate = input.wheel_gesture.rate*input.wheel_gain
	if not paced_wheel:
		rate = maxf(rate,absf(pending)/.05)
	# A slipping line and returning hands both draw material from the floor.
	# Keep controlled easing below the separate fast-haul supply limit.
	rate = clampf(rate,input.MIN_RATE,MAX_EASE_SPEED if pending<0 else MAX_FEED_SPEED)
	var physical_stop: bool = input.length_budget!=null and (input.target_metres>=input.maximum_metres-.0000001 or input.target_metres<=input.minimum_metres+.0000001)
	# A real length stop is not an asymptotic virtual cursor target.
	if paced_wheel and absf(pending)>.000001 and not physical_stop:
		# Ease into the already requested endpoint instead of hitting it at
		# full speed between irregular packets. Strong gestures shorten this
		# small arrival window; no extra trim or delayed reversal is queued.
		var arrival := maxf(.006,WHEEL_ARRIVAL_SECONDS/maxf(1.0,input.wheel_gain))
		rate = minf(rate,absf(pending)*(1.0-exp(-delta/arrival))/delta)
	if signf(pending)!=feed_direction:
		feed_rate = 0
		feed_direction = signf(pending)
	if paced_wheel:
		# Bound the onset too: a tiny packet must not jump straight to the
		# maximum hand velocity. Reversal cancels old travel immediately.
		rate = minf(rate,feed_rate+FEED_ACCELERATION*maxf(1.0,input.wheel_gain)*delta)
	feed_rate = rate if absf(pending)>.0000001 else 0.0
	input.rate = rate
	if bridge_time<0:
		var previous: float = input.work
		_entry(input,delta,steering,pending,rate)
		if bridge_time>=0: _continue_remaining(input,delta,steering,"work",previous,1,rate)
		return
	var section := "helper" if bridge_time>=1 else "recovery"
	var progress := bridge_time-1 if bridge_time>=1 else bridge_time
	var right := bridge_time>=1
	if pending<-.0000001:
		settling = true
		last_feed = _transfer(input,maxf(pending,-rate*delta))
	elif pending>.0000001: settling = false
	var next := progress
	if pending>.0000001 and not settling:
		var requested := minf(pending,rate*delta)
		next = profile.advance_distance(section,steering,progress,requested)
		next = _bounded(section,steering,progress,next,delta,MAX_HAND_SPEED,RETURN_PATH_SPEED)
		var distance: float = profile.length_at(section,steering,next)-profile.length_at(section,steering,progress)
		last_feed = _transfer(input,clampf(distance,0,requested))
		next = profile.advance_distance(section,steering,progress,last_feed)
		input.state = "HELPER HAUL" if right else "HAUL / REGRIP"
		input.slip = move_toward(input.slip,0,8*delta)
	elif settling or input.since_input>=input.IDLE_SECONDS:
		settling = true
		# Regrasp more gently while the rope is already sliding through the
		# holding hand; these two material motions must not race each other.
		var returning_while_easing := last_feed<0
		next = _bounded(section,steering,progress,minf(1,progress+2*delta),delta,1.0 if returning_while_easing else 1.5,1.3 if returning_while_easing else 2.0)
		input.state = "EASE / HANDOVER" if last_feed<0 else "HANDOVER RETURN"
		input.slip = move_toward(input.slip,1,8*delta)
	else:
		input.state = "HANDOVER HOLD"
		input.slip = move_toward(input.slip,0,8*delta)
	last_section = section
	bridge_time = next+(1 if right else 0)
	if next>1-.000002:
		if right:
			bridge_time = 0
			completed_handovers += 1
		elif settling:
			bridge_time = -1
			input.work = 1
		else: bridge_time = 1
		if not settling and pending>0: _continue_remaining(input,delta,steering,section,progress,1,rate)

func _continue_remaining(input: RefCounted,delta: float,steering: float,section: String,previous: float,current: float,rate: float) -> void:
	# Reaching a clip boundary partway through a simulation step must not
	# discard its remaining time. Both boundary poses are authored identically.
	var held := "right" if section=="helper" else "left"
	var returning := "left" if held=="right" else "right"
	var a: Vector3 = profile.palm_at(section,held,steering,previous)
	var b: Vector3 = profile.palm_at(section,returning,steering,previous)
	var elapsed := maxf(absf(last_feed)/rate,maxf(a.distance_to(profile.palm_at(section,held,steering,current))/MAX_HAND_SPEED,b.distance_to(profile.palm_at(section,returning,steering,current))/RETURN_PATH_SPEED))
	var remaining := delta-elapsed
	if remaining<=.0000001: return
	var consumed := last_feed
	input.since_input -= remaining
	advance(input,remaining,steering)
	last_feed += consumed

func _entry(input: RefCounted,delta: float,steering: float,pending: float,rate: float) -> void:
	last_section = "work"
	settling = false
	if absf(pending)>.0000001:
		if pending<0 and input.work<=.0000001:
			last_feed = _transfer(input,maxf(pending,-rate*delta))
			input.state = "EASE THROUGH"
			input.slip = move_toward(input.slip,1,8*delta)
			return
		var requested := clampf(pending,-rate*delta,rate*delta)
		var next: float = profile.advance_distance("work",steering,input.work,requested)
		next = _bounded("work",steering,input.work,next,delta,MAX_HAND_SPEED,RETURN_PATH_SPEED)
		var distance: float = profile.length_at("work",steering,next)-profile.length_at("work",steering,input.work)
		last_feed = _transfer(input,clampf(distance,minf(0,requested),maxf(0,requested)))
		input.work = profile.advance_distance("work",steering,input.work,last_feed)
		if input.work>1-.000002: input.work = 1
		if input.work<.000002: input.work = 0
		input.state = "HAUL" if pending>0 else "EASE"
		input.slip = move_toward(input.slip,1 if pending<0 else 0,8*delta)
		if input.work==1 and input.target_metres>input.metres+.0000001: bridge_time = 1
	else:
		if input.since_input>=input.IDLE_SECONDS:
			var next: float = move_toward(input.work,.5,input.RETURN_RATE*delta)
			input.work = _bounded("work",steering,input.work,next,delta,1.5,2)
			input.state = "REST" if is_equal_approx(input.work,.5) else "RETURN"
		else: input.state = "HOLD"
		input.slip = move_toward(input.slip,1 if input.state=="RETURN" else 0,8*delta)

func _bounded(section: String,steering: float,current: float,target: float,delta: float,held_speed: float,free_speed: float) -> float:
	# Palm speed alone does not bound fingers opening around the released
	# line. Reserve real release time before the returning hand departs.
	if section=="helper" and current<.12 and target>current:
		target = minf(target,current+6.0*delta)
	var held := "right" if section=="helper" else "left"
	var returning := "left" if held=="right" else "right"
	var a: Vector3 = profile.palm_at(section,held,steering,current)
	var b: Vector3 = profile.palm_at(section,returning,steering,current)
	var low := 0.0
	var high := 1.0
	for iteration in 11:
		var amount := 1.0 if iteration==0 else (low+high)*.5
		var next := lerpf(current,target,amount)
		var valid := a.distance_to(profile.palm_at(section,held,steering,next))<=held_speed*delta and b.distance_to(profile.palm_at(section,returning,steering,next))<=free_speed*delta
		if valid:
			if iteration==0: return target
			low = amount
		else: high = amount
	return lerpf(current,target,low)

func _transfer(input: RefCounted,requested: float) -> float:
	var accepted := requested
	if input.length_budget!=null: accepted = input.length_budget.transfer(requested)
	input.metres += accepted
	return accepted

func contact_state() -> Dictionary:
	var sheet_holds := bridge_time<1 or bridge_time>=2
	var helper_holds := bridge_time>=1 or (bridge_time>=0 and bridge_time<=.15)
	var role := "friction" if contact_slip>.01 else "grip"
	var phase := "WORK"
	if bridge_time>=1:
		var p := bridge_time-1
		phase = "RELEASE" if p<.12 else ("LIFT / REACH" if p<.85 else "REGRIP")
	elif bridge_time>=0 and bridge_time<.15: phase = "TRANSFER"
	return {"sheet_holds":sheet_holds,"helper_holds":helper_holds,"sheet_contact":role if sheet_holds else "open","helper_contact":role if helper_holds else "open","phase":phase}
