class_name SailingMiniMap
extends Control

const TRAIL_SAMPLE_INTERVAL := 0.35
const MAX_TRAIL_POINTS := 180
const MAP_SCALE_PIXELS_PER_METER := 1.65

@export var boat_path: NodePath

@onready var boat: WindwardBoat = get_node(boat_path) as WindwardBoat

var _trail: PackedVector3Array = PackedVector3Array()
var _sample_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail.append(boat.global_position)
	queue_redraw()


func _process(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer >= TRAIL_SAMPLE_INTERVAL:
		_sample_timer = 0.0
		_trail.append(boat.global_position)
		if _trail.size() > MAX_TRAIL_POINTS:
			_trail.remove_at(0)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.018, 0.052, 0.075, 0.88), true)
	draw_rect(bounds.grow(-1.0), Color(0.35, 0.72, 0.84, 0.55), false, 1.5)

	var center := size * 0.5
	var radar_radius := minf(size.x, size.y) * 0.39
	draw_circle(center, radar_radius, Color(0.02, 0.13, 0.18, 0.62))
	draw_arc(center, radar_radius, 0.0, TAU, 64, Color(0.35, 0.68, 0.76, 0.36), 1.0)
	draw_arc(center, radar_radius * 0.5, 0.0, TAU, 64, Color(0.35, 0.68, 0.76, 0.19), 1.0)
	draw_line(center - Vector2(radar_radius, 0.0), center + Vector2(radar_radius, 0.0), Color(0.35, 0.68, 0.76, 0.15), 1.0)
	draw_line(center - Vector2(0.0, radar_radius), center + Vector2(0.0, radar_radius), Color(0.35, 0.68, 0.76, 0.15), 1.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - 5.0, center.y - radar_radius - 8.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.88, 0.96, 1.0))
	draw_string(font, Vector2(10.0, 19.0), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.62, 0.86, 0.94))

	_draw_trail(center, radar_radius)
	_draw_boat(center)

	var state := boat.get_sailing_state()
	var wind_from := -state.true_wind_velocity.normalized()
	var current := state.water_current_velocity.normalized()
	_draw_vector_indicator(Vector2(30.0, size.y - 21.0), _world_vector_to_map(wind_from), Color(0.55, 0.9, 1.0), "W")
	_draw_vector_indicator(Vector2(size.x - 56.0, size.y - 21.0), _world_vector_to_map(current), Color(0.42, 0.95, 0.68), "C")


func _draw_trail(center: Vector2, radar_radius: float) -> void:
	if _trail.size() < 2:
		return
	var points := PackedVector2Array()
	for world_point in _trail:
		var offset := world_point - boat.global_position
		var map_point := center + Vector2(offset.x, offset.z) * MAP_SCALE_PIXELS_PER_METER
		if map_point.distance_to(center) <= radar_radius:
			points.append(map_point)
	if points.size() >= 2:
		draw_polyline(points, Color(0.35, 0.82, 0.98, 0.7), 2.0, true)


func _draw_boat(center: Vector2) -> void:
	var forward := _world_vector_to_map(boat.get_sailing_state().forward_vector()).normalized()
	var side := Vector2(-forward.y, forward.x)
	var triangle := PackedVector2Array([
		center + forward * 11.0,
		center - forward * 7.0 + side * 5.5,
		center - forward * 7.0 - side * 5.5,
	])
	draw_colored_polygon(triangle, Color(1.0, 0.78, 0.2))
	draw_polyline(PackedVector2Array([triangle[0], triangle[1], triangle[2], triangle[0]]), Color(1.0, 0.95, 0.76), 1.0, true)


func _draw_vector_indicator(origin: Vector2, direction: Vector2, color: Color, label: String) -> void:
	if direction.length_squared() < 0.001:
		return
	direction = direction.normalized()
	var side := Vector2(-direction.y, direction.x)
	var tip := origin + direction * 24.0
	draw_line(origin, tip, color, 2.0, true)
	draw_line(tip, tip - direction * 7.0 + side * 4.0, color, 2.0, true)
	draw_line(tip, tip - direction * 7.0 - side * 4.0, color, 2.0, true)
	draw_string(ThemeDB.fallback_font, origin + Vector2(-13.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)


func _world_vector_to_map(vector: Vector3) -> Vector2:
	return Vector2(vector.x, vector.z)
