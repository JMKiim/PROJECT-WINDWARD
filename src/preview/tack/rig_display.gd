extends "res://src/preview/land_drill_rig_display.gd"
var maneuver: RefCounted
func adopt(source: RefCounted,controller: RefCounted) -> void:
	lab=source.lab
	rig=source.rig
	samples=source.samples
	fixed_length=source.fixed_length
	valid=source.valid
	fitted_yaw=source.fitted_yaw
	maneuver=controller
func update() -> bool:
	if maneuver!=null and maneuver.phase=="CROSS": return maneuver.geometry_valid
	return super.update()
func fit_normal() -> bool: return super.update()
