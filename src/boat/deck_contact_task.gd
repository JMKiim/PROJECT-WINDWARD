extends RefCounted

## One owned worker, detached numeric snapshots only. Scene/mesh access and
## applying a finished result belong to the caller on the main thread.
const BLOCK := preload("res://src/boat/block_mesh_support.gd")
const HINGE := preload("res://src/boat/hinged_block_equilibrium.gd")
const SURFACE := preload("res://src/boat/hull_rope_support.gd")
const HANGING := preload("res://src/boat/rig_hanging_sheet.gd")
const OBSTACLE := preload("res://src/boat/mesh_rope_obstacle.gd")
const GUIDE := preload("res://src/boat/finite_guide_contact.gd")
const SKIN := preload("res://src/boat/rope_tube_geometry.gd")
const CONTROL := preload("res://src/boat/contact_work_control.gd")
const SPATIAL := preload("res://src/boat/mesh_block_support.gd")
const SWIVEL := preload("res://src/boat/swivel_block_equilibrium.gd")
var worker: Thread
var stage := ""
var control: RefCounted
var block_cache_input := {}
var block_cache_result := {}
var pending_block_input := {}
var block_cache_hits := 0
var block_solves := 0

func start_block(input: Dictionary) -> Error:
	return _start(input,"block")

func start_rope(input: Dictionary) -> Error:
	return _start(input,"rope")

func _start(input: Dictionary,label: String) -> Error:
	if worker!=null: return ERR_BUSY
	control=CONTROL.new()
	var snapshot := input.duplicate(true)
	pending_block_input=_block_key(snapshot) if label=="block" else {}
	var reuse := label=="block" and not block_cache_result.is_empty() and pending_block_input==block_cache_input
	# Reuse only an exactly equal detached numeric boundary. No rounded key,
	# live Node, rope material history or successful-looking failure is cached.
	# A tiny owned worker preserves the same cancellation/join protocol.
	var work := _reuse_block.bind(block_cache_result.duplicate(true),control.cancelled) if reuse else (_block.bind(snapshot,control.cancelled) if label=="block" else _rope.bind(snapshot,control.cancelled))
	worker=Thread.new()
	var error := worker.start(work,Thread.PRIORITY_LOW)
	if error!=OK:
		worker=null
		pending_block_input.clear()
		return error
	stage=label
	return OK

static func _block_key(input: Dictionary) -> Dictionary:
	# These four entries belong exclusively to the subsequent rope solve.
	# Preserve every geometric/gravity field exactly, including unknown new
	# fields, so extending the physical boundary invalidates conservatively.
	var result := input.duplicate(true)
	for key in ["path","target","wraps","exit_turn"]: result.erase(key)
	return result

func cancel() -> void:
	if control!=null: control.cancel()

func ready() -> bool:
	return worker!=null and not worker.is_alive()

func take() -> Dictionary:
	if not ready(): return {}
	var result: Variant=worker.wait_to_finish()
	worker=null
	if stage=="block" and result is Dictionary and result.get("valid",false) and not control.cancelled():
		if result.get("reused_snapshot",false): block_cache_hits+=1
		else:
			block_solves+=1
			block_cache_input=pending_block_input
			block_cache_result=result.duplicate(true)
	pending_block_input={}
	return result if result is Dictionary else {"valid":false,"reason":"contact worker did not return a result"}

func finish() -> void:
	# Scene shutdown must join its own worker before the owner disappears.
	# No worker refers to the scene or waits for main-thread callbacks.
	if worker!=null:
		cancel()
		worker.wait_to_finish()
		worker=null
	pending_block_input.clear()
	block_cache_input.clear()
	block_cache_result.clear()
	control=null

static func _reuse_block(result: Dictionary,cancelled: Callable) -> Dictionary:
	if cancelled.call(): return {"valid":false,"cancelled":true,"reason":"cached block work cancelled"}
	result["reused_snapshot"]=true
	result["worker_ms"]=0.0
	return result

static func _block(input: Dictionary,cancelled := Callable()) -> Dictionary:
	var started := Time.get_ticks_usec()
	if cancelled.is_valid() and cancelled.call(): return {"valid":false,"cancelled":true,"reason":"block work cancelled"}
	if input.get("spatial",false):
		var field := OBSTACLE.new()
		if not field.add_records(input.block_obstacles,cancelled): return {"valid":false,"cancelled":cancelled.is_valid() and cancelled.call(),"reason":"invalid or cancelled detached block obstacles"}
		for line: Dictionary in input.block_lines: field.add_capsules(line.path,line.radius,line.label)
		var field_ready := Time.get_ticks_usec()
		var body := SPATIAL.new()
		if not body.setup(input.body,field,cancelled): return {"valid":false,"cancelled":cancelled.is_valid() and cancelled.call(),"reason":"invalid or cancelled detached block body"}
		var body_ready := Time.get_ticks_usec()
		var solved := SWIVEL.solve(input.rest,input.attachment,Vector3.ZERO,.12,input.gravity,[],body.query,body.contact_constraints,12000,cancelled)
		solved["spatial"]=true
		solved["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
		solved["profile"]={"field_ms":(field_ready-started)/1000.0,"body_ms":(body_ready-field_ready)/1000.0,"solve_ms":(Time.get_ticks_usec()-body_ready)/1000.0,"field_entries":field.entries.size(),"body_triangles":input.body.size()/3,"points":body.body.points.size(),"queries":body.queries,"point_queries":body.point_queries,"cache_hits":body.cache_hits,"pairs":body.pairs.exact_pairs}
		return solved
	var support := BLOCK.new()
	support.set_body_faces(input.body)
	if not support.add_surface_faces(input.hull,input.hull_frame,input.gravity,"hull"):
		return {"valid":false,"reason":"invalid detached hull"}
	if not support.add_surface_faces(input.lower,input.lower_frame,input.gravity,"lower block",.004):
		return {"valid":false,"reason":"invalid detached lower block"}
	support.tiller_enabled=true
	support.tiller_inverse=input.tiller_inverse
	var rest: Transform3D=input.rest
	var result := HINGE.solve(rest,input.attachment,rest.basis.x,Vector3.ZERO,.12,input.gravity,[],support.query,1.0,support.interval_clear)
	result["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
	return result

static func _rope(input: Dictionary,cancelled := Callable()) -> Dictionary:
	var started := Time.get_ticks_usec()
	if cancelled.is_valid() and cancelled.call(): return {"valid":false,"cancelled":true,"reason":"rope work cancelled"}
	if input.has("obstacles"):
		var support := SURFACE.new()
		if not support.setup_faces(input.hull,input.hull_frame,input.gravity,.004):
			return {"valid":false,"reason":"invalid detached rope surface"}
		var obstacle := OBSTACLE.new()
		if not obstacle.add_records(input.obstacles,cancelled):
			return {"valid":false,"cancelled":cancelled.is_valid() and cancelled.call(),"reason":"invalid or cancelled detached guide surface"}
		for line: Dictionary in input.contact_lines:
			obstacle.add_capsules(line.path,line.radius,line.label)
		var contact := GUIDE.build(input.path,input.wraps,input.target,input.gravity,support,obstacle,input.exit_turn,cancelled)
		if contact.get("valid",false): contact["surface_arrays"]=SKIN.build(contact.path,.004)
		contact["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
		return contact
	var result := HANGING.build(input.path,input.wraps,input.target,input.gravity,null,[],input.exit_turn)
	if result.valid:
		var support := SURFACE.new()
		if not support.setup_faces(input.hull,input.hull_frame,input.gravity,.004):
			return {"valid":false,"reason":"invalid detached rope surface"}
		if support.clearance(result.path)<0:
			result=HANGING.build(input.path,input.wraps,input.target,input.gravity,support,[],input.exit_turn)
	result["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
	return result
