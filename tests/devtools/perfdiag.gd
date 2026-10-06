extends Node
# Test-only autoload (added to override.cfg by hand): finds what the GPU spends a frame on.
# Every 2 s it appends fps, draw calls and the active Light2D / shader counts to $PERF_LOG
# (default /tmp/perf.log). Writing a command to /tmp/dk_cmd applies it to the whole tree:
#   lights off|on   shadows off|on   shaders off [path part]|on   dump (lists lights and shaders in use)
#   code <res:// shader> <file>   (replaces that shader's code everywhere it is used)
#   noisetex <shader path part>   (sets uniform port_noise to the noise lattice tile)
#   hide <node name>   show <node name>
#   params <shader path part>   (logs that material's uniforms; textures as their size)
#   vp <SubViewport name> update <0-4>   vp <name> scale <factor>   (render at size/factor)

const CMD := "/tmp/dk_cmd"
var log_path := OS.get_environment("PERF_LOG") if OS.has_environment("PERF_LOG") else "/tmp/perf.log"
var saved_materials := {}
var kept := []

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)

func _tick() -> void:
	var lights := 0
	var shadows := 0
	var shaders := 0
	for n in _all(get_tree().root):
		if n is Light2D and n.enabled and n.is_visible_in_tree():
			lights += 1
			if n.shadow_enabled:
				shadows += 1
		elif n is CanvasItem and n.is_visible_in_tree() and n.material is ShaderMaterial:
			shaders += 1
	var scene := get_tree().current_scene
	_log("fps=%d draws=%d objects=%d process=%.1fms lights=%d shadows=%d shaders=%d scene=%s" % [
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		lights, shadows, shaders, scene.name if scene else "-"])
	if FileAccess.file_exists(CMD):
		var cmd := FileAccess.get_file_as_string(CMD).strip_edges()
		DirAccess.remove_absolute(CMD)
		_run(cmd)

func _run(cmd: String) -> void:
	_log("CMD " + cmd)
	if cmd.begins_with("hide ") or cmd.begins_with("show "):
		var target := cmd.substr(5).strip_edges()
		for n in _all(get_tree().root):
			if n is CanvasItem and n.name == target:
				n.visible = cmd.begins_with("show ")
				_log("VIS %s %s" % [n.get_path(), n.visible])
		return
	if cmd.begins_with("noisetex "):
		var part := cmd.trim_prefix("noisetex ").strip_edges()
		var tex := _noise_texture(256)
		for n in _all(get_tree().root):
			if n is CanvasItem and n.material is ShaderMaterial and n.material.shader and part in n.material.shader.resource_path:
				n.material.set_shader_parameter("port_noise", tex)
		return
	if cmd.begins_with("params "):
		var part := cmd.trim_prefix("params ").strip_edges()
		for n in _all(get_tree().root):
			if n is CanvasItem and n.material is ShaderMaterial and n.material.shader and part in n.material.shader.resource_path:
				var line := "PARAMS %s rect=%s scale=%s tex=%s" % [n.get_path(), n.get_global_transform(), n.get("scale"), n.get("texture").get_size() if n.get("texture") else null]
				for u in n.material.shader.get_shader_uniform_list():
					var val = n.material.get_shader_parameter(u.name)
					line += " %s=%s" % [u.name, val.get_size() if val is Texture2D else val]
				_log(line)
		return
	if cmd.begins_with("vp "):
		var a := cmd.split(" ", false)
		for n in _all(get_tree().root):
			if n is SubViewport and n.name == a[1]:
				if a[2] == "update":
					n.render_target_update_mode = int(a[3])
				elif a[2] == "scale":
					var full: Vector2i = n.get_meta("full_size", n.size)
					n.set_meta("full_size", full)
					n.size = Vector2i(Vector2(full) / float(a[3]))
					n.size_2d_override = full if float(a[3]) != 1.0 else Vector2i.ZERO
					n.size_2d_override_stretch = true
				_log("VP %s size=%s update=%d" % [n.get_path(), n.size, n.render_target_update_mode])
		return
	if cmd.begins_with("code "):
		var args := cmd.split(" ", false)
		var shader := load(args[1]) as Shader
		shader.code = FileAccess.get_file_as_string(args[2])
		kept.append(shader)
		return
	var part := cmd.trim_prefix("shaders off").strip_edges() if cmd.begins_with("shaders off") else ""
	if cmd.begins_with("shaders off"):
		cmd = "shaders off"
	for n in _all(get_tree().root):
		match cmd:
			"lights off", "lights on":
				if n is Light2D:
					n.enabled = cmd == "lights on"
			"shadows off", "shadows on":
				if n is Light2D:
					n.shadow_enabled = cmd == "shadows on"
			"shaders off":
				if n is CanvasItem and n.material is ShaderMaterial and (part == "" or part in str(n.material.shader.resource_path)):
					saved_materials[n] = n.material
					n.material = null
			"shaders on":
				if saved_materials.has(n):
					n.material = saved_materials[n]
			"dump":
				if n is SubViewport:
					_log("VIEWPORT %s size=%s update=%s 2d_scale=%s" % [n.get_path(), n.size, n.render_target_update_mode, n.size_2d_override])
				elif n is SubViewportContainer and n.is_visible_in_tree():
					_log("CONTAINER %s size=%s stretch=%s shrink=%d" % [n.get_path(), n.size, n.stretch, n.stretch_shrink])
				if n is Light2D and n.enabled and n.is_visible_in_tree():
					_log("LIGHT %s shadow=%s range=%s" % [n.get_path(), n.shadow_enabled, n.get("texture_scale")])
				elif n is CanvasItem and n.is_visible_in_tree() and n.material is ShaderMaterial and n.material.shader:
					_log("SHADER %s %s" % [n.get_path(), n.material.shader.resource_path])
	if cmd == "dump":
		_log("WINDOW size=%s content_scale=%s" % [get_window().size, get_window().content_scale_size])
	if cmd == "shaders on":
		saved_materials.clear()

## The lattice values of the map shaders' noise(): h(n) = mean of fract(753.5453123 * sin(n)) and
## the same at n + 113, at n = x + 157 y + 113, wrapped to a size x size tile.
func _noise_texture(size: int) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(size * size)
	for y in size:
		for x in size:
			var n := float(x + 157 * y + 113)
			var a := 753.5453123 * sin(n)
			var b := 753.5453123 * sin(n + 113.0)
			data[y * size + x] = int(round(((a - floor(a)) + (b - floor(b))) * 0.5 * 255.0))
	return ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_L8, data))

func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out

func _log(line: String) -> void:
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
