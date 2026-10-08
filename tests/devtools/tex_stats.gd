extends SceneTree
## Lists every texture the setup would store smaller (a side >= 512 px), with what decides whether
## halving it loses visible detail. Run on an untouched pck:
##   godot --headless --main-pack domekeeper.pck --script <this> -- --out=<file.tsv>
## Columns: path, w, h, mips, colours (sampled, capped at 4096), index art, share of 2x2 blocks
## that are one colour (1.0 = already drawn at double size, halving loses nothing), share of
## neighbouring pixel pairs that differ (hard edged pixel art is high, noise too, gradients low).

func _initialize() -> void:
	var out := "tex_stats.tsv"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_line("path\tw\th\tmips\tcolors\tindex\tblock2\tdiff\tlossless")
	var paths: Array = []
	for p in _list("res://"):
		if p.ends_with(".png.import") or p.ends_with(".jpg.import"):
			paths.append(p)
	for p in paths:
		var text := FileAccess.get_file_as_string(p)
		var m := RegEx.create_from_string('(?m)^path="([^"]+\\.ctex)"').search(text)
		if m == null:
			continue
		var ctex := _read_ctex(m.get_string(1))
		if ctex.is_empty():
			continue
		var size: Vector2i = ctex["size"]
		if maxi(size.x, size.y) < 512:
			continue
		var img := _decode(m.get_string(1), ctex)
		if img == null:
			f.store_line("%s\t%d\t%d\t%d\t?\t?\t?\t?" % [p.trim_suffix(".import"), size.x, size.y, ctex["mipmaps"]])
			continue
		img.convert(Image.FORMAT_RGBA8)
		f.store_line("%s\t%d\t%d\t%d\t%s\t%d" % [p.trim_suffix(".import"), size.x, size.y, ctex["mipmaps"], _stats(img), lossless_factor(img)])
	f.close()
	print("TEXSTATS done ", paths.size())
	quit()

## The largest factor (4, 2 or 1) the image can be stored smaller by without losing a pixel: every
## factor x factor block (from the top left) is one colour, so nearest neighbour scaling back up
## gives the original.
static func lossless_factor(img: Image) -> int:
	for f in [4, 2]:
		var w: int = img.get_width() / f * f
		var h: int = img.get_height() / f * f
		if w == 0 or h == 0:
			continue
		var ref := img.get_region(Rect2i(0, 0, w, h))
		var small := ref.duplicate()
		small.resize(w / f, h / f, Image.INTERPOLATE_NEAREST)
		small.resize(w, h, Image.INTERPOLATE_NEAREST)
		if small.get_data() == ref.get_data():
			return f
	return 1

func _list(dir: String) -> Array:
	var res := []
	for d in DirAccess.get_directories_at(dir):
		if d == ".godot":
			continue
		res.append_array(_list(dir.path_join(d)))
	for file in DirAccess.get_files_at(dir):
		res.append(dir.path_join(file))
	return res

func _stats(img: Image) -> String:
	var w := img.get_width()
	var h := img.get_height()
	var colors := {}
	var opaque := 0
	var blocks := 0
	var uniform := 0
	var pairs := 0
	var differ := 0
	var step := maxi(2, int(sqrt(float(w * h) / 20000.0)) * 2)
	for y in range(0, h - 1, step):
		for x in range(0, w - 1, step):
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			opaque += 1
			if colors.size() < 4096:
				colors[c.to_rgba32()] = true
			var r := img.get_pixel(x + 1, y)
			var d := img.get_pixel(x, y + 1)
			var rd := img.get_pixel(x + 1, y + 1)
			blocks += 1
			if c.is_equal_approx(r) and c.is_equal_approx(d) and c.is_equal_approx(rd):
				uniform += 1
			pairs += 1
			if not c.is_equal_approx(r):
				differ += 1
	var index := colors.size() <= 64
	return "%d\t%s\t%.2f\t%.2f" % [colors.size(), "yes" if index else "no",
		float(uniform) / maxi(1, blocks), float(differ) / maxi(1, pairs)]

func _read_ctex(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "GST2":
		return {}
	f.get_32()
	var size := Vector2i(f.get_32(), f.get_32())
	f.seek(36)
	var data_format := f.get_32()
	f.get_16()
	f.get_16()
	var mipmaps := f.get_32()
	f.get_32()
	return {"size": size, "data_format": data_format, "mipmaps": mipmaps, "image_at": f.get_position()}

func _decode(path: String, ctex: Dictionary) -> Image:
	if ctex["data_format"] != 1 and ctex["data_format"] != 2:
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(ctex["image_at"])
	var data := f.get_buffer(f.get_32())
	var img := Image.new()
	var err := img.load_png_from_buffer(data) if ctex["data_format"] == 1 else img.load_webp_from_buffer(data)
	return img if err == OK and not img.is_empty() else null
