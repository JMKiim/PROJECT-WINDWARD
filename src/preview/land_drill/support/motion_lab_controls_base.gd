extends RefCounted
## Shared interface for the training scene and its toolbar implementation.
var lab: Node3D
var system_select: OptionButton
var view_select: OptionButton
var follow_button: CheckButton
var support: Label
var input_hint: Label
var rig_column: VBoxContainer
var drawer: PanelContainer
var advanced_column: VBoxContainer
var drawer_scroll: ScrollContainer
var summary: Label
var toolbar: PanelContainer
var inspection_status: Label
var inspect_button: Button
var cancel_button: Button
var manual_button: Button
var diagnostic_bar: HBoxContainer
var zoom_buttons: Array[Button] = []
func build(_value: Node3D) -> void: pass
func refresh() -> void: pass
func pointer_over_ui(_point: Vector2) -> bool: return false
