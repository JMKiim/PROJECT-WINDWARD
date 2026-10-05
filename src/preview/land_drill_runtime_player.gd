extends "res://src/preview/land_drill/support/land_drill_unloaded_pose_cache_player.gd"
const DELIVERY := preload("res://src/preview/land_drill_runtime_config.gd")
var prepared := false
func prepare() -> void:
	if prepared: return
	if authored_bank==null: authored_bank=load(DELIVERY.BANK)
	track_sampler.configure(actor.skeleton)
	var clip: Animation=authored_bank.get_animation(CONFIG.relay_name("cycle",32))
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if path.get_subname_count()==0: continue
		var bone: int=actor.skeleton.find_bone(path.get_subname(0))
		if bone>=0 and bone not in bones: bones.append(bone)
	prepared=true
