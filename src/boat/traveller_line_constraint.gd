extends RefCounted

## Locked traveller material, including finite wraps, return knot and free tail.
## Button-time geometry: no authored body pose or mainsheet ledger is changed.
# Conservative inspection travel, not a measured mechanical end stop.
const MAX_X := .455
const LENGTH_TOLERANCE := .0000001
const CONTACT := preload("res://src/boat/rope_contact_geometry.gd")
var rig: Node3D
var rest_length := 0.0
var origin := Vector3.ZERO
var last := {}
var block_surfaces := []

func _init(value: Node3D) -> void:
	rig=value
	rest_length=rig.STOPPER.length_of(rig.traveller_path)
	var a: Vector3=rig._anchor(rig.get_node("PortTravellerEye"))
	var b: Vector3=rig._anchor(rig.get_node("StarboardTravellerEye"))
	origin=(a+b)*.5+Vector3(0,0,.021)
	_cache_faces(rig.traveller_lower)
	_cache_faces(rig.traveller)

func _cache_faces(node: Node3D) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		block_surfaces.append({"node":node,"faces":node.mesh.get_faces()})
	for child in node.get_children():
		if child is Node3D: _cache_faces(child)

func contact_check() -> Dictionary:
	# Button-time finite support guard. Actual guide meshes are independently
	# covered by the inspection tests; this is not general rigid-body contact.
	var path: PackedVector3Array=rig.traveller_path
	var material := PackedFloat32Array([0.0])
	var deck_gap := INF
	var self_gap := INF
	var main_gap := INF
	for index in path.size()-1:
		material.append(material[-1]+path[index].distance_to(path[index+1]))
		var count := maxi(1,ceili(path[index].distance_to(path[index+1])/.003))
		for sample in count+1:
			var point := path[index].lerp(path[index+1],sample/float(count))
			deck_gap=minf(deck_gap,point.y-.003-rig.hull.deck_y_at(point.x,point.z))
		for other in rig.route.size()-1:
			var pair := CONTACT.closest_segments(path[index],path[index+1],rig.route[other],rig.route[other+1])
			main_gap=minf(main_gap,pair[0].distance_to(pair[1])-.007)
	for a in path.size()-1:
		for b in range(a+2,path.size()-1):
			if material[b]-material[a+1]<.024: continue
			var pair := CONTACT.closest_segments(path[a],path[a+1],path[b],path[b+1])
			self_gap=minf(self_gap,pair[0].distance_to(pair[1])-.006)
	var inverse: Transform3D=rig.traveller_tiller_frame().affine_inverse()
	var block_gap := INF
	for entry in block_surfaces:
		var frame: Transform3D=rig.global_transform.affine_inverse()*entry.node.global_transform
		var faces: PackedVector3Array=entry.faces
		for index in range(0,faces.size(),3):
			for edge in 3:
				var a: Vector3=frame*faces[index+edge]
				var b: Vector3=frame*faces[index+(edge+1)%3]
				block_gap=minf(block_gap,a.y-rig.hull.deck_y_at(a.x,a.z))
				var pair := CONTACT.closest_segments(inverse*a,inverse*b,Vector3(0,0,-.490),Vector3(0,0,.490))
				block_gap=minf(block_gap,pair[0].distance_to(pair[1])-.0128)
	return {"valid":minf(minf(deck_gap,self_gap),minf(main_gap,block_gap))>=-.0005,"deck_m":deck_gap,"self_m":self_gap,"main_m":main_gap,"block_m":block_gap,"reason":"traveller support or finite-line contact"}

func _angles() -> Vector2:
	var axis: Vector3=rig.boom_pivot.basis.z
	return Vector2(atan2(axis.x,axis.z),atan2(-axis.y,Vector2(axis.x,axis.z).length()))

func _place(point: Vector3,_q: Vector2) -> float:
	rig.traveller_override=point
	rig.traveller_lower.position=point
	rig.traveller.position=point+Vector3.UP*.055
	rig._update_traveller(false)
	return rig.STOPPER.length_of(rig.traveller_path)

func fit(x: float,azimuth: float,display := false) -> Dictionary:
	if not is_finite(x) or not is_finite(azimuth) or absf(x)>MAX_X or absf(azimuth)>deg_to_rad(75):
		return {"valid":false,"reason":"outside loaded traveller domain"}
	var previous: Vector3=rig.traveller_override
	var q := _angles()
	var axis := Vector3(0,cos(azimuth),sin(azimuth))
	var base := origin+Vector3(x,0,0)
	var low := .008
	var high := .35
	var b := _place(base+axis*high,q)
	var a := INF
	# Approach from the stretched branch. A probe below the tiller can cross
	# its contact topology and is not a valid lower bracket for a loaded line.
	for sample in range(1,33):
		low=lerpf(.35,.008,sample/32.0)
		a=_place(base+axis*low,q)
		if a<=rest_length: break
		high=low
	if a>rest_length or b<rest_length:
		rig.traveller_override=previous
		rig.set_angles(q.x,q.y,display)
		return {"valid":false,"reason":"traveller length cannot support this position","minimum":a,"maximum":b,"target":rest_length}
	var radius := .0
	var length := .0
	var best_error := INF
	var best_radius := high
	for iteration in 24:
		radius=(low+high)*.5
		length=_place(base+axis*radius,q)
		if absf(length-rest_length)<best_error:
			best_error=absf(length-rest_length)
			best_radius=radius
		if absf(length-rest_length)<LENGTH_TOLERANCE*.5: break
		if length<rest_length: low=radius
		else: high=radius
	# Keep the best representable float pose, not the final quantized midpoint.
	radius=best_radius
	length=_place(base+axis*radius,q)
	var point: Vector3=rig.traveller_lower.position
	last={"valid":absf(length-rest_length)<=LENGTH_TOLERANCE,"position":point,"radius":radius,"azimuth":azimuth,"length":length,"error":length-rest_length}
	if not last.valid:
		rig.traveller_override=previous
		rig.set_angles(q.x,q.y,display)
	else: rig.set_angles(q.x,q.y,display)
	return last

func frame_at(x: float,azimuth: float) -> Dictionary:
	# Tangents belong to the measured surface, including contact with the tiller.
	var q := _angles()
	var previous: Vector3=rig.traveller_override
	var lo := maxf(-MAX_X,x-.002)
	var hi := minf(MAX_X,x+.002)
	var left := fit(lo,azimuth)
	var right := fit(hi,azimuth)
	var angular := angular_tangent(x,azimuth)
	var h := .01
	var back := fit(x,azimuth-h)
	var front := fit(x,azimuth+h)
	var back_far := fit(x,azimuth-2*h)
	var front_far := fit(x,azimuth+2*h)
	var valid: bool=left.valid and right.valid and back.valid and front.valid and back_far.valid and front_far.valid
	var result := {"valid":valid}
	if valid:
		var dx: Vector3=(right.position-left.position)/(hi-lo)
		var dp: Vector3=(8*(front.position-back.position)-(front_far.position-back_far.position))/(12*h)
		# A wide stencil must not average across a tiller contact transition.
		# Keep the local derivative when the two sampled directions disagree.
		var disagreement: float=dp.normalized().distance_to(angular.dp.normalized()) if angular.valid else INF
		result["wide_tangent_disagreement"]=disagreement
		result["wide_tangent_used"]=angular.valid and disagreement<.002
		if result.wide_tangent_used: dp=angular.dp
		result["dx"]=dx
		result["dp"]=dp
		result["normal"]=dp.cross(dx).normalized()
		if result.normal.y<0: result.normal=-result.normal
		result["slide"]=dp.normalized().cross(result.normal).normalized()
		if result.slide.dot(dx)<0: result.slide=-result.slide
	rig.traveller_override=previous
	rig.set_angles(q.x,q.y,false)
	return result

func angular_tangent(x: float,azimuth: float,h := .02) -> Dictionary:
	# Nine-point cubic least-squares derivative (fourth-order truncation).
	# Several nearby exact material fits suppress float node quantization;
	# the central material constraint and force acceptance are unchanged.
	if not is_finite(h) or h<=0: return {"valid":false,"dp":Vector3.ZERO}
	var previous: Vector3=rig.traveller_override
	var q := _angles()
	var dp := Vector3.ZERO
	var valid := true
	var weights := [126.0,193.0,142.0,-86.0]
	for index in 4:
		var distance: float=(index+1)*h
		var back := fit(x,azimuth-distance)
		var front := fit(x,azimuth+distance)
		if not back.valid or not front.valid:
			valid=false
			break
		dp+=(front.position-back.position)*weights[index]
	rig.traveller_override=previous
	rig.set_angles(q.x,q.y,false)
	return {"valid":valid,"dp":dp/(1188*h)}

func sheet_force(tension: float) -> Vector3:
	var wrap: Dictionary=rig.wraps.traveller
	var incoming: Vector3=(wrap.incoming-rig.route[wrap.begin]).normalized()
	var outgoing: Vector3=(wrap.outgoing-rig.route[wrap.end]).normalized()
	return (incoming+outgoing)*tension
