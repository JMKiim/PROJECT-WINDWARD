extends CanvasLayer

const MPS_TO_KNOTS := 1.943844

@export var boat_path: NodePath

@onready var boat: WindwardBoat = get_node(boat_path)
@onready var telemetry_label: Label = $Margin/Panel/Padding/Rows/Telemetry
@onready var camera_label: Label = $Margin/Panel/Padding/Rows/CameraMode
var graphics_panel: CanvasLayer

func _ready() -> void:
	graphics_panel=preload("res://src/ui/graphics_panel.gd").new()
	graphics_panel.scene=get_parent()
	add_child(graphics_panel)


func _process(_delta: float) -> void:
	var state := boat.get_sailing_state()
	var telemetry := (
		"대수속도  %.1f kn\n지상속도  %.1f kn\n진풍  %.1f kn\n상대풍  %.1f kn\n풍각  %.0f°\n조류  %.1f kn\n시트  %d%%\n붐  %+.0f°"
		% [
			state.speed_mps * MPS_TO_KNOTS,
			state.ground_speed_mps() * MPS_TO_KNOTS,
			state.true_wind_velocity.length() * MPS_TO_KNOTS,
			state.apparent_wind_speed_mps() * MPS_TO_KNOTS,
			state.wind_angle_degrees(),
			state.water_current_velocity.length() * MPS_TO_KNOTS,
			roundi(state.sheet_position * 100.0),
			state.boom_angle_degrees()
		]
	)
	var camera_rig: WindwardCameraRig = boat.get_node("../CameraRig")
	var camera_text := "카메라  %s" % ("1인칭" if camera_rig.first_person_enabled else "탑다운")
	if boat.seated_controls!=null:
		camera_text += "\n"+boat.seated_controls.status_text()
	# Do not dirty text shaping/layout with an intermediate camera-only label
	# or rewrite a rounded readout that has not actually changed.
	if telemetry_label.text!=telemetry: telemetry_label.text=telemetry
	if camera_label.text!=camera_text: camera_label.text=camera_text
