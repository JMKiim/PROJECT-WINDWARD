extends "res://src/preview/training_mainsheet.gd"
const DELIVERY := preload("res://src/preview/land_drill_runtime_config.gd")
const MOTION := preload("res://src/preview/land_drill/support/land_drill_relay_motion.gd")
func setup(value: Node3D) -> bool:
	lab=value
	motion_profile=load(DELIVERY.FEED)
	length_envelope=load(DELIVERY.ENVELOPE)
	if motion_profile==null or length_envelope==null: return false
	if motion_profile.get_meta("actual_authored_bank_path","")!=DELIVERY.BANK: return false
	if motion_profile.get_meta("actual_authored_bank_sha256","")!=FileAccess.get_sha256(DELIVERY.BANK): return false
	cockpit.setup(lab.actor,lab.get_node("Hull"))
	rig=RIG.new()
	rig.name="CompletePurchase"
	add_child(rig)
	# Full-rope geometry is not displayed or approved in this delivery.
	# Keep its steering state but do not build a hidden full rig on startup.
	var maximum: float=LEDGER.DEFAULT_TOTAL_METRES-length_envelope.fixed_end_metres-length_envelope.free_end_metres-length_envelope.minimum_cockpit_metres
	var initial: float=lerpf(length_envelope.minimum_rig_metres,maximum,.5)
	if not ledger.configure(length_envelope.minimum_rig_metres,initial,length_envelope.minimum_cockpit_metres,length_envelope.fixed_end_metres,length_envelope.free_end_metres): return false
	if not lab.session.wheel_pull.bind_length_budget(ledger): return false
	var motion := MOTION.new()
	if not motion.configure(motion_profile): return false
	motion.configure_supported_transitions()
	lab.session.wheel_pull.motion=motion
	lab.actor.sheet_control.weight=1
	lab.actor.sheet_control.work=lab.session.wheel_pull.work
	lab.actor.set_amount(lab.actor.amount)
	configured=true
	last_result={"valid":false,"reason":"Free rope has not passed independent contact validation"}
	return true

func update_geometry(_display := true) -> bool:
	# Do not claim a valid complete material path for a hands-only delivery.
	return false
