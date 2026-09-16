extends RefCounted

## A wheel is a stream of distance impulses, not a held key. Estimate its
## cadence from recent distance, independent of packet count within a frame.
const MEMORY_SECONDS := .12
const SMOOTH_SECONDS := .045
const RESET_SECONDS := .30
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

func trim_gain() -> float:
	# Slow detents and the start of a gesture stay precise. Only sustained
	# rotation gains distance; the gain never creates travel while idle.
	return lerpf(1.0,MAX_GAIN,smoothstep(GAIN_START_RATE,GAIN_FULL_RATE,filtered))

func reset() -> void:
	direction = 0.0
	idle = 1.0
	density = 0.0
	filtered = 0.0
	rate = MIN_RATE

func push(distance: float) -> void:
	if not is_finite(distance) or is_zero_approx(distance): return
	if idle>=RESET_SECONDS or direction*distance<0.0: reset()
	direction = signf(distance)
	idle = 0.0
	# Integrate metres, not the number of operating-system packets. Four
	# quarter-notch packets and one full notch have the same response.
	density += absf(distance)/MEMORY_SECONDS

func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0.0: return
	idle = minf(10.0,idle+delta)
	# Exact cascade of two first-order filters; frame-rate independent even
	# when the wheel is idle. Do not manufacture additional requested travel.
	var fast := exp(-delta/SMOOTH_SECONDS)
	var slow := exp(-delta/MEMORY_SECONDS)
	filtered = filtered*fast+density*MEMORY_SECONDS/(MEMORY_SECONDS-SMOOTH_SECONDS)*(slow-fast)
	density *= slow
	rate = clampf(filtered,MIN_RATE,MAX_RATE)
