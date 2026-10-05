extends "res://src/boat/animation/sheet_relay_motion.gd"
const LAND_GESTURE := preload("res://src/preview/land_drill/support/land_drill_wheel_gesture.gd")
const LIMB_PATH_SPEED := 6.0
var previous_steering := 0.0
var steering_valid := false
var frame_steering := 0.0
var limb_paths := {}
var limb_probe_count := 10

func configure(value: Resource) -> bool:
	if not value.has_meta("limb_paths"): return false
	limb_paths=value.get_meta("limb_paths")
	limb_probe_count=value.get_meta("limb_probe_count",10)
	if limb_probe_count not in [10,51]: return false
	var count: int=value.steering_samples*value.phase_samples*limb_probe_count
	for section in ["work","helper","recovery"]:
		if not limb_paths.has(section) or limb_paths[section].size()!=count: return false
	return super.configure(value)

func reset() -> void:
	super.reset()
	steering_valid=false

func advance(input: RefCounted,delta: float,steering: float) -> void:
	if not input.wheel_gesture is LAND_GESTURE:
		var gesture := LAND_GESTURE.new()
		gesture.adopt(input.wheel_gesture)
		input.wheel_gesture=gesture
	frame_steering=previous_steering if steering_valid else steering
	var filtered_rate: float=input.wheel_gesture.rate
	input.wheel_gesture.rate=input.wheel_gesture.onset_rate()
	super.advance(input,delta,steering)
	input.wheel_gesture.rate=filtered_rate
	previous_steering=steering
	steering_valid=true

func _limbs(section: String,steering: float,progress: float) -> PackedVector3Array:
	var values: PackedVector3Array=limb_paths[section]
	var sx: float=clampf((steering+1)*.5,0,1)*(profile.steering_samples-1)
	var px: float=clampf(progress,0,1)*(profile.phase_samples-1)
	var s := mini(int(sx),profile.steering_samples-2)
	var p := mini(int(px),profile.phase_samples-2)
	var result := PackedVector3Array()
	for point in limb_probe_count:
		var a: int=(s*profile.phase_samples+p)*limb_probe_count+point
		var b: int=((s+1)*profile.phase_samples+p)*limb_probe_count+point
		result.append(values[a].lerp(values[a+limb_probe_count],px-p).lerp(values[b].lerp(values[b+limb_probe_count],px-p),sx-s))
	return result

func _limb_travel(a: PackedVector3Array,b: PackedVector3Array) -> float:
	var result := 0.0
	for index in a.size(): result=maxf(result,a[index].distance_to(b[index]))
	return result

func _bounded(section: String,steering: float,current: float,target: float,delta: float,held_speed: float,free_speed: float) -> float:
	# Old ten-point profiles still require the normalized release-time guard.
	# With 51 measured probes, finger release and the finite extension are
	# bounded in actual metres/second instead. Do not add a second arbitrary
	# progress-per-second wait on top of those real articulated distances.
	if limb_probe_count!=51: target=super._bounded(section,steering,current,target,delta,held_speed,free_speed)
	var held := "right" if section=="helper" else "left"
	var returning := "left" if held=="right" else "right"
	var held_start: Vector3=profile.palm_at(section,held,steering,current)
	var free_start: Vector3=profile.palm_at(section,returning,steering,current)
	var start := _limbs(section,frame_steering,current)
	var low := 0.0
	var high := 1.0
	for iteration in 11:
		var fraction := 1.0 if iteration==0 else (low+high)*.5
		var next := lerpf(current,target,fraction)
		var valid := _limb_travel(start,_limbs(section,steering,next))<=LIMB_PATH_SPEED*delta
		if limb_probe_count==51:
			valid=valid and held_start.distance_to(profile.palm_at(section,held,steering,next))<=held_speed*delta and free_start.distance_to(profile.palm_at(section,returning,steering,next))<=free_speed*delta
		if valid:
			if iteration==0: return target
			low=fraction
		else: high=fraction
	return lerpf(current,target,low)

func _continue_remaining(input: RefCounted,delta: float,steering: float,section: String,previous: float,current: float,rate: float) -> void:
	# A boundary consumes both palm and articulated-arm travel time. Palm
	# displacement alone underestimated a returning elbow's path length.
	var held := "right" if section=="helper" else "left"
	var returning := "left" if held=="right" else "right"
	var a: Vector3=profile.palm_at(section,held,steering,previous)
	var b: Vector3=profile.palm_at(section,returning,steering,previous)
	var elapsed := maxf(absf(last_feed)/rate,maxf(a.distance_to(profile.palm_at(section,held,steering,current))/MAX_HAND_SPEED,b.distance_to(profile.palm_at(section,returning,steering,current))/RETURN_PATH_SPEED))
	elapsed=maxf(elapsed,_limb_travel(_limbs(section,frame_steering,previous),_limbs(section,steering,current))/LIMB_PATH_SPEED)
	var remaining := delta-elapsed
	if remaining<=.0000001: return
	var consumed := last_feed
	input.since_input-=remaining
	previous_steering=steering
	steering_valid=true
	advance(input,remaining,steering)
	last_feed+=consumed
