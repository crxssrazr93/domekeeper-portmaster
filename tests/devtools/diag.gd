extends Node
# Test-only autoload (added to override.cfg by hand): appends Godot memory monitors every 3 s
# to diag.log in the game folder (the game reroutes print()).

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 3.0
	t.autostart = true
	t.timeout.connect(_log)
	add_child(t)

func _log() -> void:
	var mb := func(v): return int(v / 1048576.0)
	var path := _log_path()
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line("DIAG static=%dMB texture=%dMB buffer=%dMB video=%dMB objects=%d nodes=%d resources=%d" % [
		mb.call(Performance.get_monitor(Performance.MEMORY_STATIC)),
		mb.call(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		mb.call(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		mb.call(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])

func _log_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--diag="):
			return arg.trim_prefix("--diag=")
	return "user://diag.log"

# On --texdump=<file>: after 40 s write every live texture (path, size, format, bytes), largest first.
func _enter_tree() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--texdump="):
			get_tree().create_timer(float(OS.get_environment("TEXDUMP_AFTER") if OS.has_environment("TEXDUMP_AFTER") else "40")).timeout.connect(_texdump.bind(arg.trim_prefix("--texdump=")))

func _texdump(path: String) -> void:
	# Release builds hide RenderingServer.texture_debug_usage, so walk the tree and collect
	# every texture reachable from node properties (SpriteFrames, TileSet, materials too).
	var seen := {}
	for n in get_tree().root.find_children("*", "", true, false):
		_collect(n, seen, 0)
	var rows := seen.values()
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var f := FileAccess.open(path, FileAccess.WRITE)
	var total := 0
	for r in rows:
		total += r[0]
	f.store_line("TOTAL %d MB in %d textures (uncompressed estimate)" % [total / 1048576, rows.size()])
	for r in rows:
		f.store_line("%7d KB %s" % [r[0] / 1024, r[1]])
	# every texture in the resource cache (loaded, whether on screen or only preloaded)
	var cached := []
	for tp in FileAccess.get_file_as_string("res://devtools/textures.lst").split("\n"):
		if tp != "" and ResourceLoader.has_cached(tp):
			var t: Texture2D = load(tp)
			var sc: bool = t.get_script() != null and "display_size" in t
			cached.append([t.get_width() * t.get_height() * 4 / (4 if sc else 1), tp, t.get_width(), t.get_height(), sc])
	cached.sort_custom(func(a, b): return a[0] > b[0])
	var ctotal := 0
	for c in cached:
		ctotal += c[0]
	f.store_line("CACHED %d MB in %d textures" % [ctotal / 1048576, cached.size()])
	for c in cached:
		f.store_line("CACHED %7d KB %dx%d %s %s" % [c[0] / 1024, c[2], c[3], "S" if c[4] else "-", c[1]])
	var font_tex_total := 0
	for fp in FileAccess.get_file_as_string("res://devtools/fonts.lst").split("\n"):
		if fp != "" and ResourceLoader.has_cached(fp):
			var ff: FontFile = load(fp)
			var tex_bytes := 0; var sizes := 0
			for ci in ff.get_cache_count():
				for sz in ff.get_size_cache_list(ci):
					sizes += 1
					for ti in ff.get_texture_count(ci, sz):
						var im := ff.get_texture_image(ci, sz, ti)
						if im: tex_bytes += im.get_data().size()
			font_tex_total += tex_bytes
			f.store_line("FONT %dKB data, %d sizes, glyph textures %dKB %s" % [ff.data.size() / 1024, sizes, tex_bytes / 1024, fp])
	f.store_line("FONT glyph textures total %d MB" % (font_tex_total / 1048576))
	var labels := get_tree().root.find_children("*", "Label", true, false) + get_tree().root.find_children("*", "RichTextLabel", true, false)
	labels.sort_custom(func(a, b): return a.text.length() > b.text.length())
	var nlab := 0; var nchars := 0
	for n in labels:
		nlab += 1; nchars += n.text.length()
	f.store_line("LABELS count=%d chars=%d" % [nlab, nchars])
	for n in labels.slice(0, 25):
		f.store_line("LABEL %s len=%d lines=%d visible=%s %s" % [n.get_class(), n.text.length(), n.get_line_count(), n.is_visible_in_tree(), n.get_path()])
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		f.store_line("VIEWPORT %s size=%s hdr=%s msaa=%d transparent=%s update=%d" % [n.get_path(), n.size, n.use_hdr_2d, n.msaa_2d, n.transparent_bg, n.render_target_update_mode])

func _collect(o: Object, seen: Dictionary, depth: int) -> void:
	if o == null or depth > 4:
		return
	if o is Texture2D:
		var rid = o.get_rid()
		if rid.is_valid() and not seen.has(rid):
			var w = o.get_width(); var h = o.get_height()
			var scaled: bool = o.get_script() != null and "display_size" in o
			var bytes: int = w * h * 4 / (4 if scaled else 1)  # ScaledTexture stores half-size pixels
			seen[rid] = [bytes, "%dx%d %s %s" % [w, h, "Scaled" if scaled else o.get_class(), o.resource_path]]
		if o is AtlasTexture:
			_collect(o.atlas, seen, depth + 1)
		return
	if o is SpriteFrames:
		for anim in o.get_animation_names():
			for i in o.get_frame_count(anim):
				_collect(o.get_frame_texture(anim, i), seen, depth + 1)
		return
	if o is TileSet:
		for i in o.get_source_count():
			var src = o.get_source(o.get_source_id(i))
			if src is TileSetAtlasSource:
				_collect(src.texture, seen, depth + 1)
		return
	if o is ShaderMaterial:
		for u in o.shader.get_shader_uniform_list() if o.shader else []:
			_collect(o.get_shader_parameter(u.name) if o.get_shader_parameter(u.name) is Object else null, seen, depth + 1)
		return
	for prop in o.get_property_list():
		if prop.type == TYPE_OBJECT and prop.usage & PROPERTY_USAGE_STORAGE:
			var v = o.get(prop.name)
			if v is Resource:
				_collect(v, seen, depth + 1)
