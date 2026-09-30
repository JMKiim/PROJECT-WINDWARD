extends "res://src/boat/animation/rudder_clip_actor.gd"

const CONFIG := preload("res://src/boat/animation/wide_steering_config.gd")
const RELAY_PLAYER := preload("res://src/boat/animation/wide_steering_relay.gd")
var wide_bank_ready := false

func _ready() -> void:
	super._ready()
	var bank := load(CONFIG.BANK) as AnimationLibrary
	if bank==null or extension_span<CONFIG.TUBE_METRES+CONFIG.JOINT_METRES-.000001:
		push_error("Wide steering requires its authored bank and matching extension")
		return
	for layer in LAYOUT.LAYERS:
		var player: AnimationPlayer=players[layer]
		var library := AnimationLibrary.new()
		for side in [-1,1]:
			for level in CONFIG.HIKE_LEVELS:
				library.add_animation(_clip_name(side,level),bank.get_animation(CONFIG.base_name(side,layer,level)))
		player.remove_animation_library("rudder")
		player.add_animation_library("rudder",library)
		player.play("rudder/"+LAYOUT.side_name(seat_side))
	wide_bank_ready=true
	var relay := RELAY_PLAYER.new()
	sheet_control.add_child(relay)
	relay.setup(self)
	relay.prepare()
	sheet_control.regrip.queue_free()
	sheet_control.regrip=relay
	sheet_control.continuous_relay=true
	set_amount(0)

func rudder_angle() -> float:
	return -float(seat_side)*amount*deg_to_rad(CONFIG.DEGREES)

func _hike_playback_levels() -> int:
	return CONFIG.HIKE_LEVELS if wide_bank_ready else HIKE.LEVELS
