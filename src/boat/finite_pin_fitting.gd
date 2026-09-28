extends RefCounted

## A configurable clevis/eye coupon, not an identified traveller product.
## All dimensions are metres. Build on the main thread; numeric faces can
## then be passed to detached contact work. The revolute centre is ideal:
## diametral play is visible, but bearing clearance dynamics are not solved.
const EYE := preload("res://src/boat/finite_pin_eye.gd")
const JOINT := preload("res://src/boat/revolute_pin_joint.gd")

static func validate(size: Dictionary) -> Dictionary:
	var names := ["bore", "outer", "eye_depth", "ear_depth", "side_gap", "pin_radius", "head_radius", "head_depth", "head_gap", "neck_length"]
	for name in names:
		if not size.has(name) or not (size[name] is float or size[name] is int) or not is_finite(size[name]) or size[name]<=0:
			return {"valid":false,"reason":"invalid fitting dimension: "+name}
	if size.pin_radius>=size.bore or size.head_radius<=size.bore or size.head_radius>=size.outer or size.outer<=size.bore:
		return {"valid":false,"reason":"pin must fit the bore and retaining heads must not pass through it"}
	return {"valid":true}

static func build(size: Dictionary,segments := 48) -> Dictionary:
	var accepted := validate(size)
	if not accepted.valid: return accepted
	if not EYE.valid(size.bore,size.outer,size.eye_depth,segments): return {"valid":false,"reason":"invalid eye tessellation"}
	var fixed := []
	var moving := []
	var centre: float=size.eye_depth*.5+size.side_gap+size.ear_depth*.5
	var pin_half: float=centre+size.ear_depth*.5+size.head_gap
	var stem_end: float=size.outer+size.neck_length
	var stem_width: float=size.outer*1.2
	for sign_value in [-1.0,1.0]:
		var x: float=centre*sign_value
		fixed.append(_part("ForkEyeLeft" if sign_value<0 else "ForkEyeRight",EYE.stemmed_arrays(size.bore,size.outer,size.ear_depth,stem_end,stem_width,segments),Transform3D(Basis(Vector3.RIGHT,PI),Vector3(x,0,0))))
		fixed.append(_part("PinHeadLeft" if sign_value<0 else "PinHeadRight",_cylinder(size.head_radius,size.head_depth,segments),Transform3D(Basis.IDENTITY,Vector3(sign_value*(pin_half+size.head_depth*.5),0,0))))
	fixed.append(_part("ForkBridge",_box(Vector3(centre*2+size.ear_depth,size.ear_depth,stem_width)),Transform3D(Basis.IDENTITY,Vector3(0,-stem_end-size.ear_depth*.5,0))))
	fixed.append(_part("PinShaft",_cylinder(size.pin_radius,pin_half*2,segments),Transform3D.IDENTITY))
	moving.append(_part("MovingEye",EYE.stemmed_arrays(size.bore,size.outer,size.eye_depth,stem_end,stem_width,segments),Transform3D.IDENTITY))
	for part: Dictionary in fixed+moving:
		if part.faces.is_empty(): return {"valid":false,"reason":"empty finite fitting surface: "+part.label}
	return {"valid":true,"fixed":fixed,"moving":moving,"ear_centre":centre,"pin_half_length":pin_half,"radial_clearance":size.bore-size.pin_radius,"axial_clearance":size.side_gap,"head_overlap":size.head_radius-size.bore,"size":size.duplicate(true),"scope":"provisional clevis coupon; ideal centred pin, not a product identification or bearing-load contact solution"}

static func _part(label: String,arrays: Array,frame: Transform3D) -> Dictionary:
	return {"label":label,"arrays":arrays,"transform":frame,"faces":EYE.faces(arrays)}

static func _box(size: Vector3) -> Array:
	var box := BoxMesh.new()
	box.size=size
	return box.surface_get_arrays(0)

static func _cylinder(radius: float,length: float,segments: int) -> Array:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius=radius
	cylinder.bottom_radius=radius
	cylinder.height=length
	cylinder.radial_segments=segments
	var data := cylinder.surface_get_arrays(0)
	var turn := Basis(Vector3.BACK,PI*.5)
	data[Mesh.ARRAY_VERTEX]=Transform3D(turn,Vector3.ZERO)*data[Mesh.ARRAY_VERTEX]
	data[Mesh.ARRAY_NORMAL]=Transform3D(turn,Vector3.ZERO)*data[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array=data[Mesh.ARRAY_TANGENT]
	for index in range(0,tangents.size(),4):
		var rotated := turn*Vector3(tangents[index],tangents[index+1],tangents[index+2])
		tangents[index]=rotated.x
		tangents[index+1]=rotated.y
		tangents[index+2]=rotated.z
	data[Mesh.ARRAY_TANGENT]=tangents
	return data

static func pose(fitting: Dictionary,pin: Transform3D,angle: float,minimum: float,maximum: float) -> Dictionary:
	if fitting.get("valid")!=true: return {"valid":false,"reason":"invalid fitting"}
	var state := JOINT.compose(pin,Transform3D.IDENTITY,angle,minimum,maximum)
	if not state.valid: return state
	var records := []
	for key in ["fixed","moving"]:
		for part: Dictionary in fitting[key]:
			records.append({"label":part.label,"faces":part.faces.duplicate(),"transform":(pin if key=="fixed" else state.eye)*part.transform,"moving":key=="moving"})
	return {"valid":true,"records":records,"joint":state}
