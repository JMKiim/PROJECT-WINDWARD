extends Resource

## Seated neutral stroke: fixed-step gravity/contact samples in boat space.
@export var sample_rate := 200.0
@export var points_per_frame := 24
@export var points := PackedVector3Array()
@export var source_signatures: Dictionary = {}
