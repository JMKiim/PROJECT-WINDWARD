extends RefCounted

## A wheel is a stream of distance impulses, not a held key. Estimate its
## cadence from recent distance, independent of packet count within a frame.
const MEMORY_SECONDS := .12
const SMOOTH_SECONDS := .045
const RESET_SECONDS := .30
const PRECISE_RESET_SECONDS := .10
const PRECISE_SECONDS := .18
const SUSTAINED_SECONDS := .24
const MIN_RATE := .16
const MAX_RATE := 2.40
const FULL_PACE_RATE := .30
const GAIN_START_RATE := .20
const GAIN_FULL_RATE := .40
const MAX_GAIN := 8.0
var direction := 0.0
var idle := 1.0
var density := 0.0
var filtered := 0.0
var rate := MIN_RATE
var interval := 0.0
var duration := 0.0
var physical_distance := 0.0
var observed_distance := 0.0
var frame_seconds := 0.0
var frame_filtered := 0.0
var packet_distance := 0.0
var packet_requested := 0.0
var packet_gain := 1.0
var resume_duration := 0.0
var resume_distance := 0.0
var resume_observed := 0.0
var resume_filtered := 0.0
var last_event_seconds := NAN
var event_density := 0.0
var event_filtered := 0.0

func trim_gain() -> float:
	# Slow detents and the start of a gesture stay precise. Only sustained
	# rotation gains distance; the gain never creates travel while idle.
	var sustained := smoothstep(PRECISE_SECONDS,SUSTAINED_SECONDS,duration)
	sustained *= smoothstep(.10,.16,observed_distance)
	return lerpf(1.0,MAX_GAIN,sustained*smoothstep(GAIN_START_RATE,GAIN_FULL_RATE,filtered))

func reset() -> void:
	direction = 0.0
	idle = 1.0
	density = 0.0
	filtered = 0.0
	rate = MIN_RATE
	interval = 0.0
	duration = 0.0
	physical_distance = 0.0
	observed_distance = 0.0
	frame_seconds = 0.0
	frame_filtered = 0.0
	packet_distance = 0.0
	packet_requested = 0.0
	packet_gain = 1.0
	resume_duration = 0.0
	resume_distance = 0.0
	resume_observed = 0.0
	resume_filtered = 0.0
	last_event_seconds = NAN
	event_density=0.0
	event_filtered=0.0

func note_frame(delta: float) -> void:
	frame_seconds=maxf(0,delta) if is_finite(delta) else 0.0
	frame_filtered=filtered

func request_distance(distance: float,event_seconds := NAN) -> float:
	if not is_finite(distance) or is_zero_approx(distance): return 0.0
	push(distance,event_seconds)
	# Apply one gain to the total physical distance in this delivery frame.
	# This also keeps split high-resolution wheel packets equivalent when a
	# delayed stream is recognized only after its second full detent arrives.
	packet_gain=maxf(packet_gain,trim_gain())
	var requested := signf(distance)*packet_distance*packet_gain
	var impulse := requested-packet_requested
	packet_requested=requested
	return impulse

func push(distance: float,event_seconds := NAN) -> void:
	if not is_finite(distance) or is_zero_approx(distance): return
	var frame_idle := idle
	var delivery_skew := false
	if is_finite(event_seconds) and is_finite(last_event_seconds):
		idle=maxf(0,event_seconds-last_event_seconds)
		# Input delivery and the engine's elapsed frame can be one phase apart.
		# Reconstruct the filter at this event's timestamp instead of counting
		# the delayed render interval a second time as wheel inactivity.
		var fast := exp(-idle/SMOOTH_SECONDS)
		var slow := exp(-idle/MEMORY_SECONDS)
		filtered=event_filtered*fast+event_density*MEMORY_SECONDS/(MEMORY_SECONDS-SMOOTH_SECONDS)*(slow-fast)
		density=event_density*slow
		delivery_skew=idle>=PRECISE_RESET_SECONDS and idle<RESET_SECONDS and frame_idle<PRECISE_RESET_SECONDS
	if idle>=PRECISE_RESET_SECONDS-.000001:
		# A long render frame can batch a continuing wheel stream. Retain a
		# candidate, but a single/fractional resumed detent remains precise.
		if ((frame_seconds>=.075 and idle<=frame_seconds+.04) or delivery_skew) and idle<RESET_SECONDS and direction*distance>0 and duration>=SUSTAINED_SECONDS and observed_distance>=.16:
			resume_duration=duration
			resume_distance=physical_distance
			resume_observed=observed_distance
			resume_filtered=frame_filtered
		duration = 0.0
		physical_distance = 0.0
		observed_distance = 0.0
	if idle>=RESET_SECONDS or direction*distance<0.0: reset()
	elif idle>.0000001:
		# Multiple packets in the same frame describe one physical sample.
		interval = idle if interval<=0 else lerpf(interval,idle,.5)
	direction = signf(distance)
	last_event_seconds=event_seconds
	idle = 0.0
	# Integrate metres, not the number of operating-system packets. Four
	# quarter-notch packets and one full notch have the same response.
	density += absf(distance)/MEMORY_SECONDS
	physical_distance += absf(distance)
	packet_distance += absf(distance)
	if resume_duration>0 and packet_distance>=.040-.0000001:
		duration=resume_duration
		physical_distance+=resume_distance
		observed_distance=resume_observed
		filtered=maxf(filtered,resume_filtered)
		resume_duration=0
		resume_distance=0
		resume_observed=0
		resume_filtered=0
	event_density=density
	event_filtered=filtered

func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0.0: return
	packet_distance=0.0
	packet_requested=0.0
	packet_gain=1.0
	resume_duration=0.0
	resume_distance=0.0
	resume_observed=0.0
	resume_filtered=0.0
	# Publish after a simulation step so packets split within one frame
	# receive the same distance gain as the equivalent whole wheel sample.
	observed_distance = physical_distance
	duration += minf(delta,maxf(0.0,PRECISE_RESET_SECONDS-idle))
	idle = minf(10.0,idle+delta)
	# Exact cascade of two first-order filters; frame-rate independent even
	# when the wheel is idle. Do not manufacture additional requested travel.
	var fast := exp(-delta/SMOOTH_SECONDS)
	var slow := exp(-delta/MEMORY_SECONDS)
	filtered = filtered*fast+density*MEMORY_SECONDS/(MEMORY_SECONDS-SMOOTH_SECONDS)*(slow-fast)
	density *= slow
	rate = clampf(filtered,MIN_RATE,MAX_RATE)
