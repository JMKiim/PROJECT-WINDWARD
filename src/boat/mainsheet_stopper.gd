extends RefCounted

## Dressed four-crossing stopper, stored as an authored finite centreline.
## Contact-constrained shaping happens offline, never during rope playback.
const RADIUS := .004

static func _core() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0.00106091,0.01454481,0.00745624),
		Vector3(0.00002809,0.01509498,0.00658821),
		Vector3(-0.00111671,0.01467257,0.00594666),
		Vector3(-0.00226460,0.01446723,0.00520841),
		Vector3(-0.00317409,0.01351053,0.00483052),
		Vector3(-0.00424110,0.01295025,0.00418226),
		Vector3(-0.00502376,0.01189562,0.00382761),
		Vector3(-0.00601156,0.01126515,0.00316171),
		Vector3(-0.00669919,0.01024244,0.00266307),
		Vector3(-0.00748288,0.00952068,0.00190511),
		Vector3(-0.00779480,0.00854597,0.00114465),
		Vector3(-0.00808588,0.00773173,0.00025721),
		Vector3(-0.00800141,0.00699586,-0.00068028),
		Vector3(-0.00780810,0.00642259,-0.00165108),
		Vector3(-0.00776723,0.00590806,-0.00262950),
		Vector3(-0.00779570,0.00511697,-0.00332402),
		Vector3(-0.00757704,0.00431904,-0.00388064),
		Vector3(-0.00722774,0.00351624,-0.00424342),
		Vector3(-0.00679267,0.00274653,-0.00444857),
		Vector3(-0.00631701,0.00201583,-0.00454379),
		Vector3(-0.00582567,0.00132003,-0.00456868),
		Vector3(-0.00532735,0.00065174,-0.00454477),
		Vector3(-0.00482304,0.00000241,-0.00448455),
		Vector3(-0.00430896,-0.00063831,-0.00439521),
		Vector3(-0.00378085,-0.00124595,-0.00424012),
		Vector3(-0.00322443,-0.00183452,-0.00401571),
		Vector3(-0.00264881,-0.00241672,-0.00375350),
		Vector3(-0.00206064,-0.00298703,-0.00343819),
		Vector3(-0.00149214,-0.00353771,-0.00302455),
		Vector3(-0.00093348,-0.00402454,-0.00250529),
		Vector3(-0.00038916,-0.00441332,-0.00188130),
		Vector3(0.00014621,-0.00467721,-0.00118164),
		Vector3(0.00066150,-0.00480842,-0.00042779),
		Vector3(0.00116065,-0.00479384,0.00034844),
		Vector3(0.00166615,-0.00462941,0.00110180),
		Vector3(0.00224695,-0.00437216,0.00175609),
		Vector3(0.00285071,-0.00400222,0.00232296),
		Vector3(0.00344519,-0.00352964,0.00281102),
		Vector3(0.00401985,-0.00297780,0.00321772),
		Vector3(0.00456702,-0.00238003,0.00355401),
		Vector3(0.00508673,-0.00176471,0.00383844),
		Vector3(0.00558883,-0.00113662,0.00406859),
		Vector3(0.00607299,-0.00049524,0.00424404),
		Vector3(0.00653336,0.00016220,0.00438150),
		Vector3(0.00698707,0.00082994,0.00450072),
		Vector3(0.00743312,0.00151923,0.00459390),
		Vector3(0.00787203,0.00224091,0.00465588),
		Vector3(0.00829083,0.00300536,0.00466468),
		Vector3(0.00865694,0.00382601,0.00457820),
		Vector3(0.00890673,0.00470698,0.00434355),
		Vector3(0.00897472,0.00562286,0.00395366),
		Vector3(0.00882746,0.00653437,0.00344897),
		Vector3(0.00857034,0.00747649,0.00292650),
		Vector3(0.00828533,0.00848278,0.00241960),
		Vector3(0.00785851,0.00947036,0.00186329),
		Vector3(0.00726401,0.01038833,0.00125034),
		Vector3(0.00650890,0.01121320,0.00060792),
		Vector3(0.00559796,0.01190076,-0.00005318),
		Vector3(0.00455337,0.01241997,-0.00071605),
		Vector3(0.00340388,0.01274513,-0.00136217),
		Vector3(0.00220318,0.01296537,-0.00198308),
		Vector3(0.00098683,0.01320391,-0.00258397),
		Vector3(-0.00025625,0.01340423,-0.00315543),
		Vector3(-0.00152489,0.01357501,-0.00368869),
		Vector3(-0.00282656,0.01370859,-0.00415990),
		Vector3(-0.00415698,0.01380740,-0.00457253),
		Vector3(-0.00551141,0.01388294,-0.00493796),
		Vector3(-0.00689556,0.01391192,-0.00524092),
		Vector3(-0.00830758,0.01383417,-0.00548017),
		Vector3(-0.00972913,0.01354108,-0.00558467),
		Vector3(-0.01111863,0.01303252,-0.00554809),
		Vector3(-0.01243108,0.01231220,-0.00536388),
		Vector3(-0.01361793,0.01139042,-0.00503077),
		Vector3(-0.01462788,0.01028363,-0.00455747),
		Vector3(-0.01540899,0.00901234,-0.00397093),
		Vector3(-0.01591986,0.00759980,-0.00332842),
		Vector3(-0.01611734,0.00609412,-0.00265660),
		Vector3(-0.01617585,0.00455548,-0.00197509),
		Vector3(-0.01626949,0.00300065,-0.00128712),
		Vector3(-0.01632578,0.00143344,-0.00059025),
		Vector3(-0.01637277,-0.00013707,0.00011697),
		Vector3(-0.01640888,-0.00170256,0.00083662),
		Vector3(-0.01644092,-0.00325466,0.00157025),
		Vector3(-0.01645633,-0.00478667,0.00231711),
		Vector3(-0.01639424,-0.00629512,0.00306911),
		Vector3(-0.01604838,-0.00775696,0.00378335),
		Vector3(-0.01540144,-0.00912379,0.00440579),
		Vector3(-0.01449585,-0.01034489,0.00491786),
		Vector3(-0.01338055,-0.01138051,0.00530921),
		Vector3(-0.01210954,-0.01220510,0.00557801),
		Vector3(-0.01073517,-0.01280947,0.00571043),
		Vector3(-0.00930902,-0.01319695,0.00570237),
		Vector3(-0.00788695,-0.01346140,0.00557173),
		Vector3(-0.00648071,-0.01360475,0.00534764),
		Vector3(-0.00509862,-0.01365083,0.00504986),
		Vector3(-0.00373083,-0.01364574,0.00473917),
		Vector3(-0.00240052,-0.01357567,0.00432705),
		Vector3(-0.00112720,-0.01346502,0.00378354),
		Vector3(0.00008890,-0.01333018,0.00313484),
		Vector3(0.00131303,-0.01316560,0.00251670),
		Vector3(0.00251353,-0.01297559,0.00187098),
		Vector3(0.00368968,-0.01273323,0.00121368),
		Vector3(0.00480387,-0.01235148,0.00053813),
		Vector3(0.00580864,-0.01177661,-0.00013889),
		Vector3(0.00667600,-0.01103679,-0.00080085),
		Vector3(0.00738532,-0.01016449,-0.00143138),
		Vector3(0.00792584,-0.00919754,-0.00201711),
		Vector3(0.00830491,-0.00817846,-0.00254893),
		Vector3(0.00863413,-0.00721419,-0.00310724),
		Vector3(0.00889046,-0.00630084,-0.00368131),
		Vector3(0.00896149,-0.00537809,-0.00418417),
		Vector3(0.00883454,-0.00445935,-0.00455073),
		Vector3(0.00854815,-0.00358206,-0.00475274),
		Vector3(0.00815707,-0.00276974,-0.00479999),
		Vector3(0.00771892,-0.00201721,-0.00474861),
		Vector3(0.00726379,-0.00131081,-0.00464192),
		Vector3(0.00680348,-0.00063949,-0.00450251),
		Vector3(0.00633543,0.00000769,-0.00433243),
		Vector3(0.00586282,0.00064156,-0.00414425),
		Vector3(0.00537633,0.00126909,-0.00393520),
		Vector3(0.00487077,0.00188278,-0.00368279),
		Vector3(0.00435073,0.00248128,-0.00336577),
		Vector3(0.00381432,0.00305939,-0.00298631),
		Vector3(0.00325375,0.00359191,-0.00254146),
		Vector3(0.00267819,0.00404730,-0.00202179),
		Vector3(0.00209641,0.00439772,-0.00142394),
		Vector3(0.00154592,0.00463284,-0.00073391),
		Vector3(0.00104775,0.00477074,0.00003051),
		Vector3(0.00053535,0.00474555,0.00080189),
		Vector3(0.00000848,0.00456894,0.00154188),
		Vector3(-0.00052704,0.00425556,0.00222708),
		Vector3(-0.00108663,0.00383347,0.00282175),
		Vector3(-0.00165623,0.00331782,0.00331206),
		Vector3(-0.00226558,0.00276088,0.00366497),
		Vector3(-0.00287182,0.00217567,0.00392695),
		Vector3(-0.00345542,0.00157573,0.00413569),
		Vector3(-0.00401538,0.00096827,0.00429403),
		Vector3(-0.00454753,0.00032252,0.00434382),
		Vector3(-0.00506211,-0.00031773,0.00436879),
		Vector3(-0.00556697,-0.00096466,0.00436454),
		Vector3(-0.00606480,-0.00162639,0.00432277),
		Vector3(-0.00655493,-0.00231062,0.00423096),
		Vector3(-0.00702851,-0.00302290,0.00406601),
		Vector3(-0.00746494,-0.00376566,0.00379228),
		Vector3(-0.00781866,-0.00452307,0.00335145),
		Vector3(-0.00804540,-0.00525057,0.00271058),
		Vector3(-0.00813575,-0.00587099,0.00186899),
		Vector3(-0.00831717,-0.00638043,0.00092531),
		Vector3(-0.00843930,-0.00710761,0.00004560),
		Vector3(-0.00818277,-0.00798176,-0.00072810),
		Vector3(-0.00770981,-0.00888248,-0.00143259),
		Vector3(-0.00701132,-0.00973268,-0.00207521),
		Vector3(-0.00651336,-0.01078112,-0.00266921),
		Vector3(-0.00619673,-0.01200566,-0.00307466),
		Vector3(-0.00552515,-0.01312527,-0.00340648),
		Vector3(-0.00448823,-0.01387940,-0.00384855),
		Vector3(-0.00339883,-0.01443395,-0.00445168),
		Vector3(-0.00245901,-0.01502698,-0.00526275),
		Vector3(-0.00133651,-0.01481650,-0.00602453),
		Vector3(-0.00030148,-0.01452067,-0.00687827),
		Vector3(0.00106091,-0.01454481,-0.00745624),
	])

static func points(tail_length: float = .060,standing_length: float = .035) -> PackedVector3Array:
	var core := _core()
	var direction := (core[1]-core[0]).normalized()
	var first := core[0]-direction*standing_length
	var result := PackedVector3Array([first])
	result.append_array(core)
	result.append(core[-1]+(core[-1]-core[-2]).normalized()*tail_length)
	# Standing-leg origin and axis make orientation/attachment independent of
	# the knot's decorative bounding box.
	var frame := Basis(Quaternion(direction,Vector3.FORWARD))
	for index in result.size(): result[index] = frame*(result[index]-first)
	return result

static func length_of(path: PackedVector3Array) -> float:
	var result := 0.0
	for index in path.size()-1: result += path[index].distance_to(path[index+1])
	return result

static func grounded_points(standing_length: float = .065,tail_length: float = .060) -> PackedVector3Array:
	# The same open knot laid on its side. Its standing end is on the floor,
	# and the crossings retain the rope's thickness rather than flattening.
	var core := _core()
	var bottom := INF
	for index in core.size():
		core[index] = Basis(Vector3.UP,PI*.5)*core[index]
		core[index] = Vector3(core[index].x,core[index].z,core[index].y)
		bottom = minf(bottom,core[index].y)
	var entry := (core[1]-core[0]).normalized()
	var exit_direction := (core[-1]-core[-2]).normalized()
	var result := PackedVector3Array()
	# Preserve the clear tangent tails in plan view. A straight inlet through
	# the centre would intersect the knot even though its core is valid.
	for index in 13:
		var fraction := float(index)/12
		var point := core[0]-entry*standing_length*(1-fraction)
		point.y = (point.y-bottom)*smoothstep(0,1,fraction)
		result.append(point)
	for point in core.slice(1): result.append(point-Vector3.UP*bottom)
	for index in range(1,21):
		var fraction := float(index)/20
		var point := core[-1]+exit_direction*tail_length*fraction
		point.y = (core[-1].y-bottom)*pow(1-fraction,2)
		result.append(point)
	var first := result[0]
	for index in result.size(): result[index] -= first
	return result

static func placed(path: PackedVector3Array, origin: Vector3, direction: Vector3, roll: float = 0.0) -> PackedVector3Array:
	var basis := Basis(Quaternion(Vector3.FORWARD,direction.normalized()))*Basis(Vector3.FORWARD,roll)
	var result := PackedVector3Array()
	for point in path: result.append(origin+basis*point)
	return result
