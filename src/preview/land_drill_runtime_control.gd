extends "res://src/boat/animation/sheet_control_player.gd"
const PLAYER := preload("res://src/preview/land_drill_runtime_player.gd")
func setup(value: Node3D) -> void:
	actor=value
	regrip=PLAYER.new()
	add_child(regrip)
	regrip.setup(actor)
	regrip.prepare()
	continuous_relay=true

func use_continuous_relay() -> void:
	assert(continuous_relay)
