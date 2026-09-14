extends "res://src/boat/ilca_hardware_part.gd"

## Shared round grooved construction, with an explicit sheave-centre datum.
## The linked traveller uses two independently oriented blocks.
var sheave_radius := .020

func rope_anchor_local(anchor_name: StringName = &"sheave") -> Vector3:
	if anchor_name==&"attachment": return Vector3(0,sheave_radius*1.60+.003,0)
	if anchor_name==&"becket" and has_becket: return Vector3(0,-sheave_radius*1.544,0)
	return Vector3.ZERO

func _ready() -> void:
	mesh = null
	_build_block(sheave_radius,false)
