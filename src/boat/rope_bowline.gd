extends RefCounted

## Finite 6 mm line: one nipping turn, two returning strands and a collar
## around the standing part. The large eye may be a handle or the traveller.
static func nipping() -> PackedVector3Array:
	var points := PackedVector3Array([Vector3(-.012,-.004,-.050),Vector3(-.012,-.004,-.018)])
	for index in 65:
		var t := index/64.0
		var angle := PI-TAU*t
		points.append(Vector3(.012*cos(angle),lerpf(-.004,.004,t),.012*sin(angle)))
	points.append(Vector3(-.012,.004,.022))
	return points

static func returning() -> PackedVector3Array:
	return smooth(PackedVector3Array([
		Vector3(.016,.010,.022),Vector3(.0035,.010,.006),
		Vector3(.0035,-.009,-.002),Vector3(.0035,-.010,-.016),
		Vector3(-.012,-.011,-.025),Vector3(-.025,0,-.025),
		Vector3(-.012,.011,-.025),Vector3(-.0035,.010,-.015),
		Vector3(-.0035,.010,.001),Vector3(-.0035,-.010,.007),
		Vector3(-.004,-.012,.025),Vector3(-.008,-.009,.046),
	]))

static func handle() -> PackedVector3Array:
	var result := nipping()
	var eye := smooth(PackedVector3Array([
		result[-1],Vector3(-.027,.002,.055),Vector3(-.025,-.002,.091),
		Vector3(-.008,-.005,.112),Vector3(.016,-.003,.109),
		Vector3(.032,.001,.086),Vector3(.029,.007,.053),
		Vector3(.016,.010,.022),
	]))
	for index in range(1,eye.size()): result.append(eye[index])
	var end := returning()
	for index in range(1,end.size()): result.append(end[index])
	return result

static func smooth(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array([points[0]])
	for index in points.size()-1:
		var a := points[maxi(0,index-1)]
		var b := points[index]
		var c := points[index+1]
		var d := points[mini(points.size()-1,index+2)]
		var steps := maxi(4,ceili(b.distance_to(c)/.0015))
		for step in range(1,steps+1):
			var t := step/float(steps)
			result.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
	return result

static func placed(points: PackedVector3Array,origin: Vector3,frame: Basis) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in points: result.append(origin+frame*point)
	return result
