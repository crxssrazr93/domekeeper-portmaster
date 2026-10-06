extends SceneTree
# Rates, channels and sizes of the converted samples in cache/samples.
func _init():
	var dir := OS.get_executable_path().get_base_dir()
	var base := ProjectSettings.globalize_path("res://cache/samples")
	var stats := {}
	var total := 0
	for f in DirAccess.get_files_at(base):
		if not f.ends_with(".res"): continue
		var w = load("res://cache/samples/" + f)
		var k = "%d %s" % [w.mix_rate, "st" if w.stereo else "mono"]
		if not stats.has(k): stats[k] = [0, 0]
		stats[k][0] += 1; stats[k][1] += w.data.size()
		total += w.data.size()
	for k in stats: print("SAMPLES %s n=%d %dMB" % [k, stats[k][0], stats[k][1] / 1048576])
	print("SAMPLES total %dMB" % (total / 1048576))
	quit()
