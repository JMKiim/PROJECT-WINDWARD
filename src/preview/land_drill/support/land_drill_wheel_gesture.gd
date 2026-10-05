extends "res://src/boat/animation/sheet_wheel_gesture.gd"

## The first six physical detents retain their exact distance. Once further
## continuous rotation is confirmed, the existing bounded gain may respond
## immediately instead of waiting for the low-pass filter twice.
var first_sample_distance := 0.0
var start_event_seconds := NAN
var sample_span := 0.0

func adopt(previous: RefCounted) -> void:
	for property in previous.get_property_list():
		if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(property.name,previous.get(property.name))
	first_sample_distance=physical_distance
	start_event_seconds=last_event_seconds
	sample_span=0.0

func reset() -> void:
	super.reset()
	first_sample_distance=0.0
	start_event_seconds=NAN
	sample_span=0.0

func push(distance: float,event_seconds := NAN) -> void:
	if not is_finite(distance) or is_zero_approx(distance): return
	super.push(distance,event_seconds)
	if physical_distance<=absf(distance)+.0000001:
		first_sample_distance=absf(distance)
		start_event_seconds=event_seconds
		sample_span=0.0
	elif is_finite(event_seconds) and is_finite(start_event_seconds):
		if absf(event_seconds-start_event_seconds)<.0000001:
			first_sample_distance+=absf(distance)
		else: sample_span=maxf(0,event_seconds-start_event_seconds)
	elif duration<.0000001:
		first_sample_distance+=absf(distance)
	else: sample_span=duration

func trim_gain() -> float:
	# Count physical metres, including this event, never OS packet count.
	# request_distance applies one gain to the whole delivery-frame total,
	# keeping subdivided high-resolution packets equivalent.
	var confirmed := smoothstep(.12,.14,physical_distance)
	confirmed*=smoothstep(.16,.20,duration)
	return lerpf(1.0,MAX_GAIN,confirmed*smoothstep(GAIN_START_RATE,GAIN_FULL_RATE,filtered))

func onset_rate() -> float:
	# Timestamped distance divided by its actual observation span. Exclude
	# the initial sample: it preceded the interval being measured. This is
	# only an onset estimate, not extra requested rope or a higher speed cap.
	if duration>=SUSTAINED_SECONDS or idle>=.06 or sample_span<.025: return rate
	var measured := (physical_distance-first_sample_distance)/sample_span
	return maxf(rate,clampf(measured,MIN_RATE,MAX_RATE))
