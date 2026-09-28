extends Node3D

## Independent static training rig. Public measurement datums are explicit;
## neither the production controller nor its fixed-angle trim is loaded.
const HARDWARE := preload("res://src/boat/ilca_hardware_part.gd")
const HULL := preload("res://src/boat/ilca_hull.gd")
const VIEW := preload("res://src/boat/rope_view.gd")
const END_VIEW := preload("res://src/boat/rope_tube_view.gd")
const BLOCK := preload("res://src/boat/training_sheave_block.gd")
const STOPPER := preload("res://src/boat/mainsheet_stopper.gd")
const JOIN := preload("res://src/boat/mainsheet_deck_join.gd")
const BOWLINE := preload("res://src/boat/rope_bowline.gd")
const CURVE := preload("res://src/boat/rope_path_curve.gd")
const ROPE_RADIUS := .004
const MAST_BASE_Y := .005
const LOWER_LENGTH := 2.865
const UPPER_LENGTH := 3.600
const UPPER_INSERTION := .305
const GOOSENECK_ABOVE_BASE := .945
const BOOM_LENGTH := 2.740
const AFT_BLOCK_FROM_END := .071
const FORWARD_BLOCK_FROM_END := 1.653
const GUIDE_FROM_END := 1.047
const TRAVELLER_FROM_TRANSOM := .2625
const TRAVELLER_HALF_SPAN := .500
const FAIRLEAD_ROUTE := preload("res://src/boat/fairlead_cable_route.gd")
const TRAVELLER_KNOT := preload("res://src/boat/traveller_bowline.gd")
const TRAVELLER_SUPPORT := preload("res://src/boat/traveller_supported_route.gd")
const LOADED_TRAVELLER_X := .455
# Separate mounting eye below the spar; its detailed height is provisional.
const BOOM_EYE_DROP := .016
# Fixed connector datums; provisional hardware dimensions, never elastic.
const TRAVELLER_LINK_SPAN := .012
const TRAVELLER_LINK_WIDTH := .006
var boom_pivot: Node3D
var boom: MeshInstance3D
var aft: MeshInstance3D
var forward_block: MeshInstance3D
var guide: MeshInstance3D
var traveller: MeshInstance3D
var traveller_lower: MeshInstance3D
var rope_view: Node3D
var traveller_view: Node3D
var deck: MeshInstance3D
var hull: MeshInstance3D
var opening := 0.0
var side := 1
var minimum_yaw := .0
var minimum_pitch := .0
var route := PackedVector3Array()
var fixed_end := PackedVector3Array()
var fixed_shape := STOPPER.points(.025,.020)
var fixed_roll := 0.0
var fixed_lean := PI/6.0
var fixed_splay := -PI/6.0
var cockpit_lead := PackedVector3Array()
var wraps := {}
var deck_rest := {}
var fixed_view: Node3D
var aft_winding := 0.0
var traveller_winding := 0.0
var becket_winding := 1.0
var gooseneck: MeshInstance3D
var tiller_angle := 0.0
var traveller_path := PackedVector3Array()
var traveller_link: Node3D
var traveller_control: Node3D
var traveller_control_path := PackedVector3Array()
var traveller_cleat: MeshInstance3D
var traveller_nipping := PackedVector3Array()
var traveller_fairlead_cache := {}
var traveller_fairlead_valid := false
var traveller_returning := PackedVector3Array()
var traveller_handle := PackedVector3Array()
var traveller_rope_key := Vector4(INF,INF,INF,INF)
var traveller_override := Vector3(NAN,NAN,NAN)
var traveller_rest := Vector3.ZERO
var traveller_upper_rest := Vector3.ZERO
var traveller_pose_override := Transform3D.IDENTITY
var traveller_pose_locked := false
var traveller_pose_boundary := Vector3.ZERO

func setup(floor_mesh: MeshInstance3D, deck_block: MeshInstance3D) -> void:
	hull = floor_mesh
	deck = deck_block
	# Tube diameters remain provisional visual dimensions, independent of the
	# verified longitudinal fitting datums and measured rope centerline.
	_tube("LowerMast",.03175,LOWER_LENGTH,Vector3(0,MAST_BASE_Y+LOWER_LENGTH*.5,HULL.MAST_CENTER_Z),self)
	_tube("UpperMast",.0254,UPPER_LENGTH,Vector3(0,MAST_BASE_Y+LOWER_LENGTH-UPPER_INSERTION+UPPER_LENGTH*.5,HULL.MAST_CENTER_Z),self)
	var goose := _part("Gooseneck",HARDWARE.PartKind.GOOSENECK,Vector3(0,MAST_BASE_Y+GOOSENECK_ABOVE_BASE,HULL.MAST_CENTER_Z),self)
	gooseneck = goose
	boom_pivot = Node3D.new()
	boom_pivot.name = "BoomPivot"
	boom_pivot.position = to_local(goose.rope_anchor_global())
	add_child(boom_pivot)
	boom = _tube("Boom",.0255,BOOM_LENGTH,Vector3(0,0,BOOM_LENGTH*.5),boom_pivot)
	boom.rotation.x = PI*.5
	var spigot := _tube("BoomSpigot",.006,.085,Vector3(0,0,.030),boom_pivot)
	spigot.rotation.x = PI*.5
	# The front plug is an annulus, so the spigot enters an actual opening.
	var plug := MeshInstance3D.new()
	plug.name = "BoomFrontPlug"
	var ring := TorusMesh.new()
	ring.inner_radius = .0063
	ring.outer_radius = .0255
	ring.rings = 32
	ring.ring_segments = 12
	plug.mesh = ring
	plug.rotation.x = PI*.5
	plug.position.z = .004
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color("22282b")
	plastic.roughness = .65
	plug.material_override = plastic
	boom_pivot.add_child(plug)
	# The block's neck already points up toward its attachment. Preserve the
	# sheave datum while placing the neck at the underside of the boom.
	forward_block = _boom_block("ForwardBoomBlock",Vector3(0,-.0605,BOOM_LENGTH-FORWARD_BLOCK_FROM_END))
	aft = _boom_block("AftBoomBlock",Vector3(0,-.0605,BOOM_LENGTH-AFT_BLOCK_FROM_END),true)
	guide = _part("BoomEyeStrap",HARDWARE.PartKind.EYE_STRAP,Vector3(0,-.018,BOOM_LENGTH-GUIDE_FROM_END),boom_pivot)
	guide.rotation.z = PI
	var traveller_z := HULL.HULL_LENGTH_METERS*.5-TRAVELLER_FROM_TRANSOM
	for sign: int in [-1,1]:
		var x := TRAVELLER_HALF_SPAN*sign
		var eye := _part("PortTravellerEye" if sign<0 else "StarboardTravellerEye",HARDWARE.PartKind.TRAVELLER_FAIRLEAD,Vector3(x,hull.deck_y_at(x,traveller_z),traveller_z),self)
		eye.rotation.y = 0
	traveller = BLOCK.new()
	traveller.name = "TravellerMainBlock"
	traveller.part_kind = HARDWARE.PartKind.BOOM_BLOCK
	traveller.sheave_radius = .020
	traveller.position = Vector3(LOADED_TRAVELLER_X,hull.deck_y_at(LOADED_TRAVELLER_X,traveller_z)+.10,traveller_z)
	add_child(traveller)
	traveller_lower = BLOCK.new()
	traveller_lower.name = "TravellerLineBlock"
	traveller_lower.part_kind = HARDWARE.PartKind.CONTROL_BLOCK
	traveller_lower.sheave_radius = .0125
	traveller_lower.position = traveller.position-Vector3.UP*.055
	add_child(traveller_lower)
	traveller_rest=traveller_lower.position
	traveller_upper_rest=traveller.position
	deck_rest = deck._swivel_parts.duplicate()
	rope_view = VIEW.new()
	add_child(rope_view)
	traveller_view = END_VIEW.new()
	traveller_view.radius = .003
	traveller_view.color = Color("253b49")
	add_child(traveller_view)
	traveller_link = END_VIEW.new()
	traveller_link.radius = .0018
	traveller_link.color = Color("aab1b5")
	add_child(traveller_link)
	traveller_control = END_VIEW.new()
	traveller_control.radius = .003
	traveller_control.color = Color("253b49")
	add_child(traveller_control)
	traveller_cleat = _part("TravellerCleat",HARDWARE.PartKind.TRAVELLER_CLEAT,Vector3(0,hull.deck_y_at(0,1.465),1.465),self)
	# A mirrored bowline joins the two return legs. Its full eye is the line
	# through both fairleads and the lower block, not a separate decorative ring.
	var tie := Vector3(0,0,1.660)
	var frame := Basis(Vector3.LEFT,Vector3.UP,Vector3.BACK)
	traveller_nipping=BOWLINE.placed(TRAVELLER_KNOT.nipping(),tie,frame)
	traveller_returning=BOWLINE.placed(TRAVELLER_KNOT.returning(),tie,frame)
	var joined := traveller_nipping.duplicate()
	joined.append_array(traveller_returning)
	var lift := _deck_lift(joined)
	for index in traveller_nipping.size(): traveller_nipping[index].y+=lift
	for index in traveller_returning.size(): traveller_returning[index].y+=lift
	# Lay the free handle on the aft side deck, outside the tiller's swept area.
	traveller_handle=BOWLINE.placed(BOWLINE.handle(),Vector3(.390,0,1.615),Basis.IDENTITY)
	lift=_deck_lift(traveller_handle)
	for index in traveller_handle.size(): traveller_handle[index].y+=lift
	fixed_view = END_VIEW.new()
	add_child(fixed_view)
	minimum_yaw = atan2(LOADED_TRAVELLER_X,traveller_z-HULL.MAST_CENTER_Z)
	# Find the first solid block approach, not an invented minimum sheet value.
	var low := 0.0
	var high := deg_to_rad(25)
	for iteration in 32:
		var pitch := (low+high)*.5
		boom_pivot.position = goose.position+Basis(Vector3.UP,minimum_yaw)*goose.rope_anchor_local()
		boom_pivot.basis = Basis(Vector3.UP,minimum_yaw)*Basis(Vector3.RIGHT,pitch)
		var gap := _anchor(aft).distance_to(_anchor(traveller))
		if gap>.075 and _anchor(aft).y>_anchor(traveller).y: low = pitch
		else: high = pitch
	minimum_pitch = low
	set_opening(.5)

func set_cockpit_lead(path: PackedVector3Array) -> void:
	cockpit_lead = JOIN.remote(path,to_local(deck.rope_anchor_global()))

func _part(part_name: String, kind: int, location: Vector3, parent: Node3D, becket := false) -> MeshInstance3D:
	var value := HARDWARE.new()
	value.name = part_name
	value.part_kind = kind
	value.has_becket = becket
	value.position = location
	parent.add_child(value)
	return value

func _boom_block(part_name: String,location: Vector3,becket := false) -> MeshInstance3D:
	var value := BLOCK.new()
	value.name = part_name
	value.part_kind = HARDWARE.PartKind.BOOM_BLOCK
	value.has_becket = becket
	value.sheave_radius = .020
	value.position = location
	boom_pivot.add_child(value)
	return value

func _tube(part_name: String, radius: float, length: float, location: Vector3, parent: Node3D) -> MeshInstance3D:
	var value := MeshInstance3D.new()
	value.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 32
	if part_name=="Boom":
		mesh.cap_top = false
		mesh.cap_bottom = false
	value.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("95999e")
	material.metallic = .75
	material.roughness = .35
	value.material_override = material
	value.position = location
	parent.add_child(value)
	return value

func _anchor(part: MeshInstance3D, kind: StringName = &"sheave") -> Vector3:
	return to_local(part.rope_anchor_global(kind))

func set_opening(value: float, display := true) -> void:
	opening = clampf(value,0,1)
	var yaw := lerpf(minimum_yaw,deg_to_rad(175),opening)*side
	var pitch := lerpf(minimum_pitch,deg_to_rad(-6),smoothstep(0,.30,opening))
	set_angles(yaw,pitch,display)
	# Retain the exact legacy control coordinate, not its round-trip inverse.
	opening = clampf(value,0,1)

func set_angles(yaw: float,pitch: float,display := true) -> void:
	# The independent-angle boundary uses exactly the same fitted hardware,
	# wraps and fixed end as the approved one-parameter inspection mode.
	if not is_finite(yaw) or not is_finite(pitch): return
	if traveller_pose_locked and Vector3(yaw,pitch,tiller_angle).distance_to(traveller_pose_boundary)>.000001:
		traveller_pose_locked=false
	side = -1 if yaw<0 else 1
	opening = clampf(inverse_lerp(minimum_yaw,deg_to_rad(175),absf(yaw)),0,1)
	# The unstayed mast turns with the boom. Yaw belongs at the mast centre;
	# pitch belongs at the gooseneck axle, not at the middle of the spar.
	gooseneck.rotation.y = yaw
	boom_pivot.position = gooseneck.position+Basis(Vector3.UP,yaw)*gooseneck.rope_anchor_local()
	boom_pivot.basis = Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)
	if traveller_override.is_finite():
		traveller_lower.position=traveller_override
		traveller.position=traveller_override+Vector3.UP*.055
	else:
		traveller_lower.position=Vector3(LOADED_TRAVELLER_X*side,traveller_rest.y,traveller_rest.z)
		traveller.position=Vector3(LOADED_TRAVELLER_X*side,traveller_upper_rest.y,traveller_upper_rest.z)
	_update_traveller(false)
	var upper_attachment := _anchor(traveller_lower,&"attachment")+Vector3.UP*TRAVELLER_LINK_SPAN
	if traveller_pose_locked: traveller.transform=traveller_pose_override
	var b := _anchor(traveller)
	var c := _anchor(aft)
	# The guide datum is the open aperture, not the metal bridge centre.
	var d := to_local(guide.to_global(Vector3(0,.027,0)))
	var e := _anchor(forward_block)
	var f := to_local(deck.rope_anchor_global())
	var remote := cockpit_lead
	if remote.is_empty(): remote = PackedVector3Array([f+Vector3(-.08,.06,0),f+Vector3(-.16,.12,0)])
	# Equal tension in the two legs orients each suspended block. Its neck
	# remains attached at the measured boom datum while the sheave swings.
	var aft_mount := to_local(boom_pivot.to_global(Vector3(0,-.0255-BOOM_EYE_DROP,BOOM_LENGTH-AFT_BLOCK_FROM_END)))
	var forward_mount := to_local(boom_pivot.to_global(Vector3(0,-.0255-BOOM_EYE_DROP,BOOM_LENGTH-FORWARD_BLOCK_FROM_END)))
	c = aft_mount-boom_pivot.basis.y*.035
	e = forward_mount-boom_pivot.basis.y*.035
	for iteration in 24:
		var prior_centers := [b,c,e]
		var aft_up := _suspension_up(b,d,c,boom_pivot.basis.y,.020,.035)
		var forward_up := _suspension_up(d,f,e,boom_pivot.basis.y,.020,.035)
		c = aft_mount-aft_up*.035
		e = forward_mount-forward_up*.035
		_align_block(aft,c,b,d,aft_up)
		_align_block(forward_block,e,d,f,forward_up)
		var becket := to_local(aft.to_global(aft.rope_anchor_local(&"becket")+Vector3.UP*.0065))
		if not traveller_pose_locked: _align_block(traveller,b,becket,c,Vector3.DOWN)
		# Solve the block position from its physical eye, not an unrelated
		# vertical sheave spacing followed by a stretched display connector.
		if not traveller_pose_locked: traveller.position+=upper_attachment-_anchor(traveller,&"attachment")
		b=_anchor(traveller)
		if b.distance_squared_to(prior_centers[0])<1e-16 and c.distance_squared_to(prior_centers[1])<1e-16 and e.distance_squared_to(prior_centers[2])<1e-16: break
	var a := to_local(aft.to_global(aft.rope_anchor_local(&"becket")+Vector3.UP*.0065))
	# The fixed end passes through the becket's open gap. Its knot is aft of
	# the opening; the loaded leg leaves forward around the transverse pin.
	var pin := _anchor(aft,&"becket")
	var traveller_entry := b
	var aft_entry := c
	var deck_entry := f
	var purchase_axis := global_basis.inverse()*aft.global_basis.x
	# Adjacent sheaves share a common tangent. A one-pass route aimed at the
	# next axle crosses the becket at block-to-block; converge the actual
	# contact endpoints, with the same finite set of circle tangencies.
	for iteration in 8:
		route = PackedVector3Array([a])
		wraps.clear()
		wraps["becket"] = _append_wrap(route,pin,.0062,a,traveller_entry,Vector4.ZERO,becket_winding,purchase_axis)
		wraps["traveller"] = _append_wrap(route,b,_groove_radius(.020),route[-1],aft_entry,Vector4.ZERO,traveller_winding,purchase_axis)
		wraps["aft"] = _append_wrap(route,c,_groove_radius(.020),route[-1],d,Vector4.ZERO,aft_winding,purchase_axis)
		route.append(d)
		wraps["forward"] = _append_wrap(route,e,_groove_radius(.020),route[-1],deck_entry)
		wraps["deck"] = _append_wrap(route,f,_groove_radius(.0285),route[-1],remote[0])
		traveller_entry = route[wraps.traveller.begin]
		aft_entry = route[wraps.aft.begin]
		deck_entry = route[wraps.deck.begin]
	# The stopper stands on the opposite side of the opening from the loaded
	# leg, sharing its tangent instead of choosing a world-axis knot direction.
	# The stopper bears against the becket opening, normal to its face.
	# The short loaded leg turns around the pin on the other side; using
	# that pin tangent as the knot axis tilts the knot into the return leg.
	var standing_back := global_basis.inverse()*aft.global_basis*Vector3(0,sin(fixed_lean),cos(fixed_lean))*becket_winding
	var knot_x := global_basis.inverse()*aft.global_basis.x
	var knot_y := standing_back.cross(knot_x).normalized()
	var knot_frame := Basis(knot_y.cross(standing_back),knot_y,standing_back)
	knot_frame = Basis(knot_y,fixed_splay)*knot_frame
	knot_frame *= Basis(Vector3.BACK,fixed_roll)
	fixed_end.clear()
	for point in fixed_shape: fixed_end.append(a+knot_frame*point)
	_align_axis(forward_block,e,wraps.forward.axle,global_basis.inverse()*forward_block.global_basis.y)
	_align_deck(wraps.deck.axle,remote[0]-f)
	# The short remote lead transition preserves its authored outgoing tangent.
	var tangent_start := route[-1]
	var incoming := (remote[0]-tangent_start).normalized()
	var outgoing := (remote[1]-remote[0]).normalized()
	var handle := tangent_start.distance_to(remote[0])/3.0
	for index in range(1,9):
		var t := index/8.0
		var u := 1.0-t
		route.append(tangent_start*u*u*u+(tangent_start+incoming*handle)*3*u*u*t+(remote[0]-outgoing*handle)*3*u*t*t+remote[0]*t*t*t)
	if display:
		rope_view.show_path(route)
		fixed_view.show_path(fixed_end)
	_update_traveller(display)

func lock_traveller_pose(pose: Transform3D) -> void:
	traveller_pose_override=pose
	traveller_pose_locked=true
	var axis := boom_pivot.basis.z
	traveller_pose_boundary=Vector3(atan2(axis.x,axis.z),atan2(-axis.y,Vector2(axis.x,axis.z).length()),tiller_angle)

func _update_traveller(display := false) -> void:
	# The lower sheave datum depends on steering/side, not the boom's trim.
	# Reuse its rope mesh through the repeated main-sheet length evaluations.
	var rope_key := Vector4(tiller_angle,traveller_lower.position.x,traveller_lower.position.y,traveller_lower.position.z)
	if rope_key==traveller_rope_key:
		if display: _draw_traveller()
		return
	traveller_rope_key=rope_key
	var small := _anchor(traveller_lower)
	var patches := traveller_fairlead_patches(small)
	traveller_fairlead_valid=not patches.is_empty()
	if not traveller_fairlead_valid: return
	var port_patch: PackedVector3Array=patches.port
	var starboard_patch: PackedVector3Array=patches.starboard
	var port_aft := port_patch[-1]
	var starboard_aft := starboard_patch[-1]
	var rear := TRAVELLER_SUPPORT.route({"port":port_aft,"starboard":starboard_aft,"tiller":traveller_tiller_frame(),"tiller_radius":.0161,"tiller_half_span":.490,"sheave_radius":.0125-minf(HARDWARE.BLOCK_GROOVE_DEPTH,.009*.43*.873)+.0033},small)
	if not rear.valid:
		traveller_fairlead_valid=false
		return
	# Tiller tangencies depend on the actual sheave entry/exit, not its
	# centre. Iterate those shared points together, including at full helm.
	_align_axis(traveller_lower,small,rear.frame.basis.x,rear.frame.basis.y)
	# One continuous material path between the two free tails: handle, cleat,
	# nipping turn, large traveller eye, returning strands, collar and short tail.
	var starboard_front := starboard_patch[0]
	var cleat_entry := traveller_cleat.position+Vector3(0,.020,.020)
	var cleat_exit := traveller_cleat.position+Vector3(0,.018,-.025)
	var cleat_approach := traveller_cleat.position+Vector3(0,.018,.060)
	traveller_path=traveller_handle.duplicate()
	traveller_path.reverse()
	traveller_path.append_array(PackedVector3Array([traveller_cleat.position+Vector3(.040,.013,-.080),traveller_cleat.position+Vector3(0,.018,-.070),cleat_exit,cleat_entry,cleat_approach]))
	traveller_path.append_array(traveller_nipping)
	traveller_path.append_array(_traveller_support(traveller_nipping[-1],starboard_front,true))
	# Round only the authored knot/cleat tail, never the finite contact patch.
	traveller_path=CURVE.round_corners(traveller_path,.012)
	traveller_path.append_array(starboard_patch)
	traveller_path.append_array(rear.path.slice(1))
	port_patch=port_patch.duplicate()
	port_patch.reverse()
	traveller_path.append_array(port_patch.slice(1))
	traveller_path.append_array(traveller_returning)
	traveller_control_path=PackedVector3Array()
	if display: _draw_traveller()

func traveller_fairlead_patches(small: Vector3) -> Dictionary:
	# The manual rig keeps its established lower datum. Resolve the fitting
	# geometry once for each loaded side, not during every steering/frame or
	# thousands of measured sheet-envelope samples. This is geometric manual
	# routing, not certification of frictionless fairlead reaction forces.
	if traveller_fairlead_cache.has(small): return traveller_fairlead_cache[small]
	var result := {}
	for side in ["port","starboard"]:
		var eye: Node3D=get_node("PortTravellerEye" if side=="port" else "StarboardTravellerEye")
		var front: Vector3=traveller_returning[0] if side=="port" else traveller_nipping[-1]
		var candidate := FAIRLEAD_ROUTE.settled(eye.transform,front,small,PackedVector3Array(),80)
		var patch := FAIRLEAD_ROUTE.contact_patch(candidate,eye.transform)
		if patch.is_empty(): return {}
		result[side]=patch
	traveller_fairlead_cache[small]=result
	return result

func _draw_traveller() -> void:
	traveller_view.show_path(traveller_path)
	traveller_control.show_path(traveller_control_path)
	var upper := _anchor(traveller,&"attachment")
	var lower := _anchor(traveller_lower,&"attachment")
	var center := (upper+lower)*.5
	var link := PackedVector3Array()
	var along := (upper-lower).normalized()
	var axis := (global_basis.inverse()*traveller.global_basis.x).normalized()
	axis=(axis-along*axis.dot(along)).normalized()
	if axis.is_zero_approx(): axis=along.cross(Vector3.FORWARD).normalized()
	for index in 33:
		var angle := TAU*index/32.0
		link.append(center+along*cos(angle)*TRAVELLER_LINK_SPAN*.5+axis*sin(angle)*TRAVELLER_LINK_WIDTH)
	traveller_link.show_path(link)

func _deck_lift(points: PackedVector3Array) -> float:
	# Rigid support keeps the knot's crossings intact instead of flattening its
	# centreline independently at each deck sample.
	var lift := -INF
	for point in points: lift=maxf(lift,hull.deck_y_at(point.x,point.z)+.0033-point.y)
	return lift

func _traveller_support(start: Vector3,finish: Vector3,below := false) -> PackedVector3Array:
	var result := PackedVector3Array()
	# Solve in the inclined tube's perpendicular plane. A world-Z slice is
	# not perpendicular to a steered tiller and cuts the tube at full steering.
	var frame := traveller_tiller_frame()
	var a := frame.affine_inverse()*start
	var b := frame.affine_inverse()*finish
	var radial_a := Vector2(a.x,a.y)
	var radial_b := Vector2(b.x,b.y)
	var radius := .0161 # 12.8 mm wear plate + 3 mm rope + surface allowance.
	if Geometry2D.get_closest_point_to_segment(Vector2.ZERO,radial_a,radial_b).length()>=radius: return result
	if minf(a.z,b.z)>.490 or maxf(a.z,b.z)<-.490: return result
	var side := -1.0 if below else 1.0
	var tangent_angles := []
	for radial: Vector2 in [radial_a,radial_b]:
		tangent_angles.append(radial.angle()+side*signf(radial.x)*acos(clampf(radius/radial.length(),-1,1)))
	var arc := absf(angle_difference(tangent_angles[0],tangent_angles[1]))*radius
	var lead := sqrt(maxf(0,radial_a.length_squared()-radius*radius))
	var exit_length := sqrt(maxf(0,radial_b.length_squared()-radius*radius))
	var total := lead+arc+exit_length
	for step in 9:
		var angle := lerp_angle(tangent_angles[0],tangent_angles[1],step/8.0)
		var z := lerpf(a.z,b.z,(lead+arc*step/8.0)/total)
		result.append(frame*Vector3(cos(angle)*radius,sin(angle)*radius,z))
	return result

func traveller_tiller_frame() -> Transform3D:
	var yaw := Basis(Vector3.UP,tiller_angle)
	return Transform3D(yaw*Basis(Vector3.RIGHT,deg_to_rad(2.512)),Vector3(0,0,2.171)+yaw*Vector3(0,.331476,-.489529))

func fit_length(target: float, display := true) -> Dictionary:
	# The hand-side join is fixed for this solve. Bracket a monotone geometric
	# length, then use safeguarded secants; no arm pose is searched or changed.
	if not is_finite(target): return {"valid":false}
	var previous_opening := opening
	set_opening(0.0,false)
	var lower_length := length_metres()
	set_opening(1.0,false)
	var upper_length := length_metres()
	if target<lower_length-.00005 or target>upper_length+.00005:
		set_opening(previous_opening,display)
		return {"valid":false,"minimum":lower_length,"maximum":upper_length,"target":target}
	var low := 0.0
	var high := 1.0
	var candidate := previous_opening
	var iterations := 0
	for index in 24:
		iterations = index+1
		set_opening(candidate,false)
		var measured := length_metres()
		if absf(measured-target)<.000025: break
		if measured<target:
			low = candidate
			lower_length = measured
		else:
			high = candidate
			upper_length = measured
		var next := lerpf(low,high,(target-lower_length)/maxf(.000001,upper_length-lower_length))
		candidate = clampf(next,low+(high-low)*.001,high-(high-low)*.001)
	if display: set_opening(opening,true)
	return {"valid":absf(length_metres()-target)<=.00005,"error_metres":length_metres()-target,"iterations":iterations,"opening":opening}

static func _groove_radius(radius: float) -> float:
	return radius-HARDWARE.BLOCK_GROOVE_DEPTH+ROPE_RADIUS+.0003

static func _suspension_up(incoming: Vector3,outgoing: Vector3,center: Vector3,boom_up: Vector3,radius: float,neck_length: float) -> Vector3:
	var axle := (incoming-center).cross(outgoing-center).normalized()
	var plane_up := boom_up-axle*boom_up.dot(axle)
	var projected_length := plane_up.length()
	plane_up = plane_up.normalized()
	var loaded := -((incoming-center).normalized()+(outgoing-center).normalized()).normalized()
	# The fixed attachment cannot let the finite sheave swing into the boom.
	# The angular contact stop follows the actual radii and neck length.
	# Clearance is the support of the oriented wheel, not its full radius
	# in every direction. A nearly horizontal sheave presents its thickness
	# to the spar; treating it as a sphere incorrectly locks its swivel.
	var half_width := HARDWARE.BLOCK_SHEAVE_WIDTH*.5+HARDWARE.BLOCK_CHEEK_CLEARANCE+HARDWARE.BLOCK_CHEEK_THICKNESS
	var wheel_support := radius*projected_length+half_width*absf(boom_up.dot(axle))
	var rope_support := _groove_radius(radius)*projected_length+ROPE_RADIUS
	var support := maxf(wheel_support,rope_support)+.0005
	var cosine := clampf((support-BOOM_EYE_DROP)/(neck_length*maxf(projected_length,.0001)),-1,1)
	var limit := acos(cosine)
	var angle := plane_up.signed_angle_to(loaded,axle)
	return plane_up.rotated(axle,clampf(angle,-limit,limit))

func _align_block(part: MeshInstance3D,center: Vector3,incoming: Vector3,outgoing: Vector3,up: Vector3) -> void:
	var x := (incoming-center).cross(outgoing-center).normalized()
	if x.is_zero_approx(): x = Vector3.RIGHT
	_align_axis(part,center,x,up)

func _align_axis(part: MeshInstance3D,center: Vector3,x: Vector3,up: Vector3) -> void:
	# A plane has two normals. Keep the same hemisphere so a nearly
	# collinear pair of loaded legs does not flip the fixed knot by 180°.
	var reference := boom_pivot.basis.x if part.get_parent()==boom_pivot else Vector3.RIGHT
	if x.dot(reference)<0: x = -x
	var y := (up-x*up.dot(x)).normalized()
	if y.is_zero_approx(): y = x.cross(Vector3.FORWARD).normalized()
	var frame := Basis(x,y,x.cross(y))
	var parent := part.get_parent() as Node3D
	var world := Transform3D(global_basis*frame,to_global(center)-global_basis*frame*part.rope_anchor_local())
	part.transform = parent.global_transform.affine_inverse()*world

func _align_deck(axle: Vector3,outgoing: Vector3) -> void:
	var x := deck.global_basis.inverse()*global_basis*axle
	var y := (Vector3.UP-x*Vector3.UP.dot(x)).normalized()
	if y.is_zero_approx(): y = x.cross(outgoing).normalized()
	var turn := Basis(x,y,x.cross(y))
	var center: Vector3 = deck.rope_anchor_local()
	for part: Node3D in deck_rest:
		var rest: Transform3D = deck_rest[part]
		part.transform = Transform3D(turn*rest.basis,center+turn*(rest.origin-center))
	deck._swivel_yaw = INF

static func _append_wrap(result: PackedVector3Array, center: Vector3, radius: float, incoming: Vector3, outgoing: Vector3,obstacle := Vector4.ZERO,winding := 0.0,frame_axis := Vector3.ZERO) -> Dictionary:
	# Exact entry/exit tangencies in the plane defined by the two loaded legs.
	var first := incoming-center
	var last := outgoing-center
	var axle := first.cross(last).normalized()
	if axle.is_zero_approx(): axle = Vector3.RIGHT
	# Connected purchase legs share the physical sheave plane. Recomputing
	# that plane from the preceding pass's contact points amplifies tiny
	# out-of-plane errors when the two legs are nearly parallel.
	if not frame_axis.is_zero_approx(): axle = frame_axis.normalized()
	var best := PackedVector3Array()
	var best_cost := INF
	var best_sweep := 0.0
	var begin := result.size()
	for entry_sign: float in [-1.0,1.0]:
		for exit_sign: float in [-1.0,1.0]:
			var radial_a := first.normalized()*radius/first.length()+axle.cross(first.normalized())*sqrt(maxf(0,1-radius*radius/first.length_squared()))*entry_sign
			var radial_b := last.normalized()*radius/last.length()+axle.cross(last.normalized())*sqrt(maxf(0,1-radius*radius/last.length_squared()))*exit_sign
			for direction: float in [-1.0,1.0]:
				if winding!=0 and direction!=winding: continue
				var sweep := fposmod(atan2(axle.dot(radial_a.cross(radial_b)),radial_a.dot(radial_b))*direction,TAU)*direction
				var entry := center+radial_a*radius
				var exit_point := center+radial_b*radius
				var alignment := (entry-incoming).normalized().dot(axle.cross(radial_a)*direction)+(outgoing-exit_point).normalized().dot(axle.cross(radial_b)*direction)
				if alignment<1.999: continue
				var cost := (2-alignment)*100+absf(sweep)*radius+incoming.distance_to(entry)+exit_point.distance_to(outgoing)
				# A shorter wrap may cross its own loaded legs. Those are
				# separate portions of the same finite-diameter rope.
				var pair := Geometry3D.get_closest_points_between_segments(incoming,entry,exit_point,outgoing)
				var material_gap := pair[0].distance_to(entry)+absf(sweep)*radius+pair[1].distance_to(exit_point)
				if material_gap>.030 and pair[0].distance_to(pair[1])<ROPE_RADIUS*2: cost += 1000
				if obstacle.w>0:
					var pin := Vector3(obstacle.x,obstacle.y,obstacle.z)
					var nearest := Geometry3D.get_closest_point_to_segment(pin,incoming,entry)
					if nearest.distance_to(pin)<obstacle.w: cost += 1000
				if cost>=best_cost: continue
				best_cost = cost
				best_sweep = sweep
				best.clear()
				for index in 25: best.append(center+Basis(axle,sweep*index/24.0)*radial_a*radius)
	result.append_array(best)
	return {"begin":begin,"end":result.size()-1,"center":center,"radius":radius,"axle":axle,"sweep":best_sweep,"incoming":incoming,"outgoing":outgoing}

func length_metres() -> float:
	var result := 0.0
	for index in route.size()-1: result += route[index].distance_to(route[index+1])
	return result
