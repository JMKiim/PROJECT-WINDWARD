extends RefCounted

## Read-only display inverse. The material ledger and finalized human pose
## are inputs, never targets for this model to rewrite.
const RIG := preload("res://src/preview/land_drill_rig.gd")
const JOIN := preload("res://src/boat/mainsheet_deck_join.gd")
const ARC := preload("res://src/boat/mainsheet_stopper.gd")
var rig: Node3D
var lab: Node3D
var samples := PackedVector2Array()
var signature := []
var valid := false
var error_m := INF
var cropped_metres := 0.0
var end_difference_metres := 0.0
var cockpit_difference_metres := 0.0
var fixed_length := 0.0
var update_ms := 0.0
var refinements := 0
var fitted_yaw := 0.0
var previous_target := INF
var active_side := 1

func setup(value: Node3D) -> bool:
	lab=value
	rig=RIG.new()
	rig.name="VisibleTrainingRig"
	lab.add_child(rig)
	rig.setup(lab.get_node("Hull"),lab.ratchet)
	fixed_length=ARC.length_of(rig.local_fixed_end)
	rig.set_cockpit_lead(lab.review_options.model.last_result.dynamic_path)
	for index in 37:
		var yaw: float=lerpf(rig.minimum_yaw,deg_to_rad(120),index/36.0)
		rig.set_angles(yaw,rig.minimum_pitch,false)
		if not rig.geometry_valid: return false
		samples.append(Vector2(rig.length_metres(),yaw))
	return update()

func update() -> bool:
	if samples.size()<2 or lab.review_options.model.last_result.is_empty(): return false
	var started := Time.get_ticks_usec()
	var path: PackedVector3Array=lab.review_options.model.last_result.dynamic_path
	var remote := JOIN.remote(path,lab.to_local(lab.ratchet.rope_anchor_global()))
	if remote.size()<2: return false
	# The cockpit visual originally starts at the block centre. Its first
	# 100mm belongs to the complete wrap now, so remove that exact arc once
	# and add it to the rig target. No double counting or ledger transfer.
	cropped_metres=ARC.length_of(path)-ARC.length_of(remote)
	var result: Dictionary=lab.review_options.model.last_result
	var ledger: RefCounted=lab.complete_sheet.ledger
	# Ground seating of the free stopper slightly changes its displayed arc.
	# Account for the measured end/drape difference in the read-only inverse,
	# instead of stretching the rope, moving a hand or editing the ledger.
	end_difference_metres=ledger.fixed_end_metres-fixed_length+ledger.free_end_metres-ARC.length_of(result.end_path)
	cockpit_difference_metres=-result.display_error_m
	var target: float=ledger.rig_metres+cropped_metres+end_difference_metres+cockpit_difference_metres
	var direction: int=-lab.actor.seat_side
	var key := [target,lab.actor.rudder_angle(),remote,direction]
	if key==signature: return valid
	signature=key.duplicate(true)
	if direction!=active_side:
		active_side=direction
		previous_target=INF
		rig.pin_geometry.seed=Vector2.ZERO
	rig.tiller_angle=lab.actor.rudder_angle()
	rig.cockpit_lead=remote
	var row := samples[0]
	var slope := 1.0
	for index in samples.size()-1:
		var a := samples[index]
		var b := samples[index+1]
		if target>b.x and index<samples.size()-2: continue
		slope=(b.x-a.x)/(b.y-a.y)
		row=a.lerp(b,clampf((target-a.x)/(b.x-a.x),0,1))
		break
	var yaw: float=row.y if not is_finite(previous_target) else absf(fitted_yaw)+(target-previous_target)/slope
	valid=false
	refinements=0
	for iteration in 6:
		yaw=clampf(yaw,samples[0].y,samples[-1].y)
		rig.set_angles(yaw*direction,rig.minimum_pitch,false)
		refinements+=1
		if not rig.geometry_valid: break
		error_m=rig.length_metres()-target
		if absf(error_m)<=.00005:
			valid=true
			break
		yaw-=error_m/maxf(.1,slope)
	if valid:
		fitted_yaw=yaw*direction
		previous_target=target
		rig.show_geometry()
	update_ms=(Time.get_ticks_usec()-started)/1000.0
	return valid
