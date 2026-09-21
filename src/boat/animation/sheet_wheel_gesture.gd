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

func push(distance: float) -> void:
	if not is_finite(distance) or is_zero_approx(distance): return
	if idle>=PRECISE_RESET_SECONDS-.000001:
		duration = 0.0
		physical_distance = 0.0
		observed_distance = 0.0
	if idle>=RESET_SECONDS or direction*distance<0.0: reset()
	elif idle>.0000001:
		# Multiple packets in the same frame describe one physical sample.
		interval = idle if interval<=0 else lerpf(interval,idle,.5)
	direction = signf(distance)
	idle = 0.0
	# Integrate metres, not the number of operating-system packets. Four
	# quarter-notch packets and one full notch have the same response.
	density += absf(distance)/MEMORY_SECONDS
	physical_distance += absf(distance)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0.0: return
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
