extends Node

const SOURCE := preload("res://src/boat/animation/sheet_stroke_source.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
var actor: Node3D
var players: Array[AnimationPlayer] = []
var enabled := false
var playing := false
var time := 0.0

func setup(owner_actor: Node3D) -> void:
	actor = owner_actor
	for layer in ["left_arm", "right_arm"]:
		var player := AnimationPlayer.new()
		player.name = "Sheet_" + layer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		add_child(player)
		player.root_node = player.get_path_to(actor)
		var library := AnimationLibrary.new()
		library.add_animation(&"stroke", load("res://src/boat/animation/sheet_stroke_" + layer + ".tres") as Animation)
		player.add_animation_library(&"sheet", library)
		player.play("sheet/stroke")
		players.append(player)

func enter() -> void:
	# Explicit study cut; do not imply a sailing maneuver or simultaneous trim.
	if actor.seat_side != -1 or not is_zero_approx(actor.hike) or not is_zero_approx(actor.amount): return
	enabled = true
	playing = false
	time = 0.0
	actor.set_amount(0.0)

func leave() -> void:
	enabled = false
	playing = false
	actor.set_amount(0.0)

func seek(value: float) -> void:
	if not enabled or not is_finite(value): return
	time = clampf(value, 0.0, SOURCE.DURATION)
	actor.set_amount(0.0)

func advance(delta: float) -> void:
	if not enabled or not playing or not is_finite(delta) or delta < 0: return
	seek(time + delta)
	if time >= SOURCE.DURATION: playing = false

func sample() -> void:
	for player in players:
		player.seek(time, true, true)

func helper_boat() -> Vector3:
	return actor.bone_pose_boat("RightHand") * SOURCE.ASSIST_LOCAL

func helper_channel() -> PackedVector3Array:
	var hand: Transform3D = actor.bone_pose_boat("RightHand")
	var radial := SOURCE.ASSIST_LOCAL - GRIP.TILLER_OFFSET
	radial -= GRIP.TILLER_AXIS * radial.dot(GRIP.TILLER_AXIS)
	var tangent := (hand.basis * GRIP.TILLER_AXIS.cross(radial).normalized()).normalized()
	var center := helper_boat()
	if tangent.dot(center - SOURCE.BLOCK) < 0: tangent = -tangent
	return PackedVector3Array([center - tangent * 0.035, center, center + tangent * 0.035])

func rope_points() -> PackedVector3Array:
	var hand: PackedVector3Array = actor.sheet_channel_boat()
	var helper := helper_boat()
	var present := SOURCE.blend(time, 1.1, 2.0) * (1.0 - SOURCE.blend(time, 3.65, 3.9))
	var free := SOURCE.sheet_open(time)
	var pin := helper_channel()
	var helper_in := pin[0]
	var helper_out := pin[2]
	var radial := SOURCE.ASSIST_LOCAL - GRIP.TILLER_OFFSET
	radial -= GRIP.TILLER_AXIS * radial.dot(GRIP.TILLER_AXIS)
	var normal: Vector3 = (actor.bone_pose_boat("RightHand").basis * radial).normalized()
	# Lay the free span around the near side of the shaft before the thumb
	# closes. A straight interpolation would cut across the rigid extension.
	var lay_over := normal * 0.08 * sin(present * PI)
	var end := hand[-1].lerp(helper_out, present) + lay_over
	var held_path := PackedVector3Array([SOURCE.BLOCK])
	for point in hand: held_path.append(point)
	held_path.append(hand[-1].lerp(helper_in, present) + lay_over)
	held_path.append(hand[-1].lerp(helper, present) + lay_over)
	held_path.append(end)
	var supported := PackedVector3Array([SOURCE.BLOCK, helper_in, helper, helper_out])
	var result := PackedVector3Array()
	# Fixed samples allow a continuous line route during opening and closing.
	# The open hand is absent from the supported route: the rope stays at the
	# right-hand pin while the left hand reaches forward.
	for index in 41:
		var u := float(index) / 40.0
		result.append(_along(held_path, u).lerp(_along(supported, u), free))
	var start := result[-1]
	var tail := 0.18 + SOURCE.pulled_metres(time)
	var control := start + Vector3(0.14, 0.025, -0.22)
	var finish := start + Vector3(0.25, -tail, -0.38)
	for index in range(1, 13):
		var u := float(index) / 12.0
		result.append(start * (1 - u) * (1 - u) + control * 2 * (1 - u) * u + finish * u * u)
	return result

func _along(path: PackedVector3Array, u: float) -> Vector3:
	var length := 0.0
	for index in path.size() - 1: length += path[index].distance_to(path[index + 1])
	var distance := length * u
	for index in path.size() - 1:
		var segment := path[index].distance_to(path[index + 1])
		if distance <= segment and segment > 0.000001:
			return path[index].lerp(path[index + 1], distance / segment)
		distance -= segment
	return path[-1]
