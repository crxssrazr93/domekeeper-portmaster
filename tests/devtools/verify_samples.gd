extends SceneTree
# Test-only: for a spread of converted sound effects, dump original PCM and converted ADPCM
# and print their parameters, so godot_adpcm --verify can compare them.
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var files := DirAccess.get_files_at(OS.get_cmdline_user_args()[1] + "/cache/samples")
	var picks := [files[0], files[files.size() / 3], files[files.size() / 2], files[-1]]
	for f in files:
		var r := load("res://cache/samples/" + f) as AudioStreamWAV
		if r.stereo and not (f in picks):
			picks.append(f); break
	for f in files:
		var r := load("res://cache/samples/" + f) as AudioStreamWAV
		if r.loop_mode != AudioStreamWAV.LOOP_DISABLED and not (f in picks):
			picks.append(f); break
	for f in picks:
		var conv := load("res://cache/samples/" + f) as AudioStreamWAV
		var orig := load("res://.godot/imported/" + f.get_basename() + ".sample") as AudioStreamWAV
		FileAccess.open(out + "/" + f + ".pcm", FileAccess.WRITE).store_buffer(orig.data)
		FileAccess.open(out + "/" + f + ".adpcm", FileAccess.WRITE).store_buffer(conv.data)
		print("VS %s|%d|%s|%d|%d|%d|%d|%d|%d" % [f, 2 if orig.stereo else 1, conv.format == AudioStreamWAV.FORMAT_IMA_ADPCM,
			orig.mix_rate, conv.mix_rate, orig.loop_mode, conv.loop_mode, orig.loop_end, conv.loop_end])
	quit()
