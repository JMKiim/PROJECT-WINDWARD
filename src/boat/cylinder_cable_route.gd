extends RefCounted

## Taut, frictionless centreline around a rigid circular support, axle local X.
## Planar grooves reject fleet angle: their axle is never rotated to fit a rope.
## The cylindrical mode permits a helix, but not unmodelled end-cap contact.
const PLANE_TOLERANCE := .000002
const CHORD_ERROR := .000001

static func route(frame: Transform3D, radius: float, start: Vector3, finish: Vector3, planar := true, required_wrap := true, preferred := Vector3.ZERO, half_span := INF, minimum_leg_separation := 0.0, winding := 0.0) -> Dictionary:
	if not frame.is_finite() or not start.is_finite() or not finish.is_finite() or not preferred.is_finite() or not is_finite(radius) or radius<=0 or is_nan(half_span) or half_span<=0 or not is_finite(minimum_leg_separation) or minimum_leg_separation<0 or winding not in [-1.0,0.0,1.0]:
		return {"valid":false,"reason":"invalid circular support boundary"}
	if not frame.basis.is_equal_approx(frame.basis.orthonormalized()) or frame.basis.determinant()<.99999:
		return {"valid":false,"reason":"support frame must be rigid and right handed"}
	var a := frame.affine_inverse()*start
	var b := frame.affine_inverse()*finish
	var pa := Vector2(a.y,a.z)
	var pb := Vector2(b.y,b.z)
	var ra := pa.length()
	var rb := pb.length()
	if ra<=radius or rb<=radius:
		return {"valid":false,"reason":"endpoint on or inside support"}
	if planar and maxf(absf(a.x),absf(b.x))>PLANE_TOLERANCE:
		return {"valid":false,"reason":"rope endpoints outside actual groove plane","fleet_offset_m":maxf(absf(a.x),absf(b.x))}
	# Negligible roundoff is the only axial displacement removed in groove mode.
	if planar:
		a.x=0
		b.x=0
	var delta := pb-pa
	var t := clampf(-pa.dot(delta)/maxf(delta.length_squared(),1e-30),0,1)
	if not required_wrap and (pa+delta*t).length()>=radius:
		return {"valid":true,"wrapped":false,"path":PackedVector3Array([start,finish]),"arc_path":PackedVector3Array(),"length":start.distance_to(finish),"arc_length":0.0,"entry":start,"exit":finish,"support_force_per_n":Vector3.ZERO}
	var lead := sqrt(ra*ra-radius*radius)
	var tail := sqrt(rb*rb-radius*radius)
	var offset_a := acos(radius/ra)
	var offset_b := acos(radius/rb)
	var local_preferred := frame.basis.transposed()*preferred
	var preference := Vector2(local_preferred.y,local_preferred.z).normalized()
	var best := {}
	for side_a: float in [-1.0,1.0]:
		var first := atan2(pa.y,pa.x)+side_a*offset_a
		var radial_a := Vector2(cos(first),sin(first))
		for side_b: float in [-1.0,1.0]:
			var last := atan2(pb.y,pb.x)+side_b*offset_b
			var radial_b := Vector2(cos(last),sin(last))
			for direction: float in [-1.0,1.0]:
				if winding!=0 and direction!=winding: continue
				var tangent_a := Vector2(-radial_a.y,radial_a.x)*direction
				var tangent_b := Vector2(-radial_b.y,radial_b.x)*direction
				if tangent_a.dot((radial_a*radius-pa).normalized())<.99999 or tangent_b.dot((pb-radial_b*radius).normalized())<.99999: continue
				var sweep := fposmod((last-first)*direction,TAU)*direction
				var middle := first+sweep*.5
				if preference.length_squared()>.5 and Vector2(cos(middle),sin(middle)).dot(preference)<0: continue
				var arc := absf(sweep)*radius
				var developed := lead+arc+tail
				var entry_x := lerpf(a.x,b.x,lead/developed)
				var exit_x := lerpf(a.x,b.x,(lead+arc)/developed)
				if maxf(absf(entry_x),absf(exit_x))>half_span: continue
				var length := sqrt(developed*developed+(b.x-a.x)*(b.x-a.x))
				# A fixed-winding wrap can cross its two loaded legs.
				# Reject that topology when the caller supplies a finite tube
				# separation; never thin the rope or project its actual axle.
				if minimum_leg_separation>0:
					var entry_local := Vector3(entry_x,radial_a.x*radius,radial_a.y*radius)
					var exit_local := Vector3(exit_x,radial_b.x*radius,radial_b.y*radius)
					var pair := Geometry3D.get_closest_points_between_segments(a,entry_local,exit_local,b)
					var material_gap := pair[0].distance_to(entry_local)+arc*length/developed+pair[1].distance_to(exit_local)
					if material_gap>PI*minimum_leg_separation and pair[0].distance_to(pair[1])<minimum_leg_separation: continue
				if not best.is_empty() and length>=best.length: continue
				var steps := maxi(2,ceili(absf(sweep)/(2*acos(clampf(1-CHORD_ERROR/radius,-1,1)))))
				var arc_path := PackedVector3Array()
				for index in steps+1:
					var fraction := index/float(steps)
					var angle := first+sweep*fraction
					arc_path.append(frame*Vector3(lerpf(entry_x,exit_x,fraction),cos(angle)*radius,sin(angle)*radius))
				var entry := arc_path[0]
				var exit_point := arc_path[-1]
				var path := PackedVector3Array([start])
				path.append_array(arc_path)
				path.append(finish)
				var force_a := (start-entry).normalized()
				var force_b := (finish-exit_point).normalized()
				best={"valid":true,"wrapped":true,"path":path,"arc_path":arc_path,"entry":entry,"exit":exit_point,"length":length,"arc_length":arc*length/developed,"sweep":sweep,"entry_tangent":-force_a,"exit_tangent":force_b,"support_force_per_n":force_a+force_b,"entry_force_per_n":force_a,"exit_force_per_n":force_b,"moment_per_n":(entry-frame.origin).cross(force_a)+(exit_point-frame.origin).cross(force_b)}
	if best.is_empty(): return {"valid":false,"reason":"no tangent wrap within chosen topology and finite axial span"}
	return best
