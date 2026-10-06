extends MainLoop
## One-time PortMaster setup for Dome Keeper on stock Godot 4.3. Run from the game folder:
##   godot --main-pack domekeeper.pck --headless --script res://setup/port_setup.gd -- \
##     --out="$PWD" --encoder="$PWD/tools/godot_adpcm.<arch>"
## res:// is read-only in pack mode, so files go to the absolute folder given by --out; the
## game later finds them through res:// because missing pack files resolve from that folder.
##
## Steps (each skips work already done, so an interrupted run can simply be restarted):
##   project data   godot/ gets the pack's project data, the stub classes added to the class
##                  cache and the GDExtensions dropped; Godot reads it from there once
##                  use_hidden_project_data_directory is false
##   override.cfg   port autoloads (PortTweaks, Steam, PlayFabServices) added to the project's; as new
##                  keys Godot starts them after the game's own autoloads
##   samples        every 16-bit sound effect re-encoded as IMA ADPCM (4x smaller in RAM) into
##                  cache/samples/, its .import remap in the pack repointed there; above
##                  22050 Hz resampled down, and stereo that is really mono folded to one channel
##   music          every track under res://content/music/ replaced by a LazyAudioStream that
##                  loads the real stream only while it plays (the game preloads its soundtrack)
##   title scene    the title screen's hidden patch notes and credits panels hold ~200 labels
##                  that Godot shapes on entering the tree, with every character on its own
##                  wrapped line since hidden panels are 0 px wide: a ~140 MB heap spike. The
##                  scene is saved again with that text moved into metadata, which PortTweaks
##                  puts back while a panel is open
##   fonts          the CJK fonts (36 MB of font data the game preloads for every language) are
##                  repointed to small stand-ins that remember the real file; PortTweaks loads
##                  the real data into them when a Chinese, Japanese or Korean language is chosen
##   textures       textures with a side >= 512 px stored at the screen's scale of the 1920x1080
##                  design (--texture-factor: 3 at 640x480, at least 2, and 4 for sides >= 8192 px,
##                  the texture size limit of GLES3 class Mali GPUs) as ScaledTexture, which still
##                  reports the original size so regions, frame grids and tile atlases are
##                  unchanged. Sprites are palette index art (their colour values are coordinates
##                  into a palette texture), so images with few distinct colours are resized
##                  nearest neighbour; blending would produce wrong palette entries, and so would
##                  lossy compression. Colour art (backgrounds, title images, effects) is drawn
##                  more magnified and visibly loses detail at a third, so with --astcenc=<astcenc
##                  binary> (ARM GPUs, which all decode ASTC) it is kept at half size and
##                  compressed to ASTC 4x4: a quarter of the memory of RGBA, and less than a third
##                  would take uncompressed
## The pack is patched in place (small .import texts appended); game data never leaves it.

const PckPatcher := preload("res://setup/pck_patcher.gd")

const STUB_AUTOLOADS := {
	"PortTweaks": "res://stubs/PortTweaks.gd",
	"Steam": "res://stubs/Steam.gd",
	"PlayFabServices": "res://stubs/PlayFabServices.gd",
}
const STUB_CLASSES := [
	{"class": &"PlayFabPartyMultiplayerPeer", "base": &"MultiplayerPeerExtension", "path": "res://stubs/PlayFabPartyMultiplayerPeer.gd"},
	{"class": &"PlayFabLobby", "base": &"RefCounted", "path": "res://stubs/PlayFabLobby.gd"},
]
const SAMPLE_MAX_RATE := 22050
const SAMPLE_MONO_DB := 30.0  # fold to mono when L-R is this far below L+R
const MUSIC_PREFIX := "res://content/music/"
const TEXTURE_HALVE_FROM := 512
const TEXTURE_FACTOR_FILE := "cache/textures/.factor"  # the factor the cached textures were made with
const TEXTURE_QUARTER_FROM := 8192
const TEXTURE_INDEX_MAX_COLORS := 64  # at most this many distinct colours: palette index art
const TEXTURE_SKIP_PREFIX := "res://test/"  # developer test art, never loaded in play

var out_dir := ""
var encoder := ""
var texture_factor := 2
var astcenc := ""  # astcenc binary for colour art, or "" for none
var pck := PckPatcher.new()

# A plain MainLoop, not a SceneTree: Godot adds the project's autoloads to a SceneTree main loop
# after _init, and the game's autoloads load so much of the game that the process passed 1 GB
# (and was killed on 1 GB devices) after the setup itself had finished. A MainLoop script cannot
# set a success exit code (Godot 4 defaults to failure), so success is reported by the marker
# file DONE_MARKER, which the launcher checks.
const DONE_MARKER := "cache/.setup_ok"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--encoder="):
			encoder = arg.trim_prefix("--encoder=")
		elif arg.begins_with("--astcenc="):
			astcenc = arg.trim_prefix("--astcenc=")
		elif arg.begins_with("--texture-factor="):
			texture_factor = clampi(int(arg.trim_prefix("--texture-factor=")), 2, 4)
	if out_dir == "" or encoder == "":
		push_error("usage: -- --out=<game folder> --encoder=<godot_adpcm binary>")
		return
	DirAccess.remove_absolute(out_dir.path_join(DONE_MARKER))
	var err := pck.open(out_dir.path_join("domekeeper.pck"))
	if err != OK:
		push_error("cannot open domekeeper.pck for patching: %s" % error_string(err))
		return
	var ok := copy_project_data() and write_class_cache() and write_override() and convert_samples() and lazy_music() and lazy_fonts() and defer_panel_text() and scale_textures()
	pck.close()
	if ok:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("cache"))
		FileAccess.open(out_dir.path_join(DONE_MARKER), FileAccess.WRITE).store_string("ok\n")
	printerr("PORT_SETUP: ", "OK" if ok else "FAILED")

func _process(_delta: float) -> bool:
	return true  # all work happens in _initialize; end the main loop on the first frame

func copy_project_data() -> bool:
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("godot"))
	for file in DirAccess.get_files_at("res://.godot"):
		if file in ["global_script_class_cache.cfg", "extension_list.cfg"]:
			continue
		var data := FileAccess.get_file_as_bytes("res://.godot/" + file)
		var out := FileAccess.open(out_dir.path_join("godot/" + file), FileAccess.WRITE)
		if out == null:
			push_error("cannot write godot/%s" % file)
			return false
		out.store_buffer(data)
	# No extensions: sentry and the GIF compressor have no aarch64 builds and are optional.
	FileAccess.open(out_dir.path_join("godot/extension_list.cfg"), FileAccess.WRITE).store_string("")
	printerr("PORT_SETUP: project data copied")
	return true

func write_class_cache() -> bool:
	var cache := ConfigFile.new()
	if cache.load("res://.godot/global_script_class_cache.cfg") != OK:
		push_error("cannot read the game's global class cache")
		return false
	var classes: Array = cache.get_value("", "list", [])
	var template: Dictionary = classes[0] if classes.size() > 0 else {}
	for stub in STUB_CLASSES:
		var entry := template.duplicate()
		for key in entry.keys():
			if typeof(entry[key]) == TYPE_BOOL:
				entry[key] = false
		entry.merge({"class": stub["class"], "base": stub["base"], "path": stub["path"], "icon": "", "language": &"GDScript"}, true)
		classes.append(entry)
	cache.set_value("", "list", classes)
	return cache.save(out_dir.path_join("godot/global_script_class_cache.cfg")) == OK

func write_override() -> bool:
	ProjectSettings.set_setting("application/config/use_hidden_project_data_directory", false)
	# Stub autoloads must exist before any game script that names them is compiled, so
	# re-add every autoload with the stubs first (new settings are ordered by insertion).
	var autoloads := {}
	for prop in ProjectSettings.get_property_list():
		if prop.name.begins_with("autoload/"):
			autoloads[prop.name] = ProjectSettings.get_setting(prop.name)
	for key in autoloads:
		ProjectSettings.set_setting(key, null)
	for name in STUB_AUTOLOADS:
		ProjectSettings.set_setting("autoload/" + name, "*" + STUB_AUTOLOADS[name])
	for key in autoloads:
		ProjectSettings.set_setting(key, autoloads[key])
	return ProjectSettings.save_custom(out_dir.path_join("override.cfg")) == OK

## Returns [import text, imported path] for an .import file in the pack.
func read_import(path: String) -> Array:
	var text := pck.read(path).get_string_from_utf8()
	var re := RegEx.create_from_string('(?m)^path="([^"]+)"')
	var m := re.search(text)
	return [text, m.get_string(1) if m else ""]

func convert_samples() -> bool:
	var cache := "cache/samples"
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(cache))
	var tmp_in := out_dir.path_join(cache + "/.in.pcm")
	var tmp_out := out_dir.path_join(cache + "/.out.adpcm")
	var done := 0
	var skipped := 0
	var saved := 0
	for path in pck.entries:
		if not path.ends_with(".wav.import"):
			continue
		var imp := read_import(path)
		var imported: String = imp[1]
		if not imported.ends_with(".sample"):
			skipped += 1  # already converted (points into res://cache) or unusual
			continue
		var wav := load(path.trim_suffix(".import")) as AudioStreamWAV
		if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
			skipped += 1
			continue
		var pcm := FileAccess.open(tmp_in, FileAccess.WRITE)
		pcm.store_buffer(wav.data)
		pcm.close()
		var channels := 2 if wav.stereo else 1
		var output := []
		var args := [tmp_in, tmp_out, str(channels), str(wav.mix_rate), str(SAMPLE_MAX_RATE), str(SAMPLE_MONO_DB)]
		if OS.execute(encoder, args, output) != 0:
			push_error("encoder failed on " + path)
			return false
		# encoder reports what it produced: "rate=<hz> channels=<n> frames=<n>"
		var info := {}
		for field in str(output[0] if output.size() else "").strip_edges().split(" "):
			info[field.get_slice("=", 0)] = field.get_slice("=", 1).to_int()
		if not info.has("rate") or info["rate"] <= 0:
			push_error("encoder gave no format for " + path)
			return false
		var ratio := float(info["rate"]) / wav.mix_rate
		var adpcm := AudioStreamWAV.new()
		adpcm.data = FileAccess.get_file_as_bytes(tmp_out)
		adpcm.format = AudioStreamWAV.FORMAT_IMA_ADPCM
		adpcm.mix_rate = info["rate"]
		adpcm.stereo = info["channels"] == 2
		adpcm.loop_mode = wav.loop_mode
		adpcm.loop_begin = int(round(wav.loop_begin * ratio))
		adpcm.loop_end = mini(int(round(wav.loop_end * ratio)), info["frames"])
		var name: String = imported.get_file().get_basename() + ".res"
		if ResourceSaver.save(adpcm, out_dir.path_join(cache + "/" + name)) != OK:
			push_error("cannot save " + name)
			return false
		var new_text: String = imp[0].replace('path="%s"' % imported, 'path="res://%s/%s"' % [cache, name])
		pck.replace(path, new_text.to_utf8_buffer())
		saved += wav.data.size() - adpcm.data.size()
		done += 1
		if done % 100 == 0:
			printerr("PORT_SETUP: samples %d converted" % done)
	DirAccess.remove_absolute(tmp_in)
	DirAccess.remove_absolute(tmp_out)
	printerr("PORT_SETUP: samples converted=%d skipped=%d saved=%d MB" % [done, skipped, saved / 1048576])
	return true

func lazy_music() -> bool:
	var cache := "cache/music"
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(cache))
	var done := 0
	for path in pck.entries:
		if not (path.begins_with(MUSIC_PREFIX) and path.ends_with(".ogg.import")):
			continue
		var imp := read_import(path)
		var imported: String = imp[1]
		if not imported.ends_with(".oggvorbisstr"):
			continue  # already lazy
		var name: String = imported.get_file().get_basename() + ".tres"
		var tres := FileAccess.open(out_dir.path_join(cache + "/" + name), FileAccess.WRITE)
		tres.store_string('[gd_resource type="AudioStream" load_steps=2 format=3]\n\n'
			+ '[ext_resource type="Script" path="res://stubs/LazyAudioStream.gd" id="1"]\n\n'
			+ '[resource]\nscript = ExtResource("1")\nreal_path = "%s"\n' % imported)
		tres.close()
		var new_text: String = imp[0].replace('path="%s"' % imported, 'path="res://%s/%s"' % [cache, name])
		new_text = new_text.replace('type="AudioStreamOggVorbis"', 'type="AudioStream"')
		pck.replace(path, new_text.to_utf8_buffer())
		done += 1
	printerr("PORT_SETUP: lazy music tracks=%d" % done)
	return true

const CJK_FONT_DIRS := ["res://gui/fonts/ja/", "res://gui/fonts/korean/", "res://gui/fonts/simplified chinese/",
	"res://gui/fonts/traditional chinese/", "res://gui/fonts/noto/NotoSansTC"]
const FONT_STANDIN_DONOR := "res://gui/fonts/NotoSans-Regular.ttf"

func lazy_fonts() -> bool:
	var cache := "cache/fonts"
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(cache))
	var donor: FontFile = load(FONT_STANDIN_DONOR)
	var done := 0
	for path in pck.entries:
		if not (path.ends_with(".otf.import") or path.ends_with(".ttf.import")):
			continue
		if not CJK_FONT_DIRS.any(func(d): return path.begins_with(d)):
			continue
		var imp := read_import(path)
		var imported: String = imp[1]
		if not imported.ends_with(".fontdata"):
			continue  # already a stand-in
		var standin := FontFile.new()
		standin.data = donor.data
		standin.set_meta("port_real_path", imported)
		var name: String = imported.get_file().get_basename() + ".res"
		if ResourceSaver.save(standin, out_dir.path_join(cache + "/" + name)) != OK:
			push_error("cannot save font stand-in " + name)
			return false
		var new_text: String = imp[0].replace('path="%s"' % imported, 'path="res://%s/%s"' % [cache, name])
		pck.replace(path, new_text.to_utf8_buffer())
		done += 1
	printerr("PORT_SETUP: CJK font stand-ins=%d" % done)
	return true

const DEFERRED_TEXT_SCENES := {"res://stages/title/TitleStage.tscn": ["PatchNotesPanel", "CreditsPanel"]}

func defer_panel_text() -> bool:
	var cache := "cache/scenes"
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(cache))
	for scene_path in DEFERRED_TEXT_SCENES:
		var remap_path: String = scene_path + ".remap"
		var imp := read_import(remap_path)
		var imported: String = imp[1]
		if imported.begins_with("res://cache/"):
			continue  # done before
		var root: Node = (load(scene_path) as PackedScene).instantiate()
		var moved := 0
		for panel_name in DEFERRED_TEXT_SCENES[scene_path]:
			var panel := root.find_child(panel_name, true, false)
			if panel == null:
				push_error("%s has no %s" % [scene_path, panel_name])
				return false
			for label in panel.find_children("*", "Label", true, false):
				if label.owner == root and label.text != "":
					label.set_meta("port_text", label.text)
					label.text = ""
					moved += 1
		var packed := PackedScene.new()
		if packed.pack(root) != OK:
			push_error("cannot pack " + scene_path)
			return false
		root.free()
		var name: String = imported.get_file().get_basename() + ".scn"
		if ResourceSaver.save(packed, out_dir.path_join(cache + "/" + name)) != OK:
			push_error("cannot save " + name)
			return false
		var new_text: String = imp[0].replace('path="%s"' % imported, 'path="res://%s/%s"' % [cache, name])
		pck.replace(remap_path, new_text.to_utf8_buffer())
		printerr("PORT_SETUP: %s labels deferred=%d" % [scene_path.get_file(), moved])
	return true

## True when a sample of the opaque pixels has few distinct colours (palette index sprites).
func is_index_art(img: Image) -> bool:
	var rgba := img
	if img.get_format() != Image.FORMAT_RGBA8:
		rgba = img.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var colors := {}
	var w := rgba.get_width()
	var total := w * rgba.get_height()
	var stride := maxi(1, total / 4096)
	for i in range(0, total, stride):
		var c := rgba.get_pixel(i % w, i / w)
		if c.a > 0.0:
			colors[c.to_rgba32()] = true
			if colors.size() > TEXTURE_INDEX_MAX_COLORS:
				return false
	return true

## The image as ASTC 4x4 (linear LDR, as Godot samples 2D textures), or null if astcenc failed.
## A .astc file is a 16 byte header (magic, block size, image size) and the blocks, which are
## exactly what Image.FORMAT_ASTC_4x4 holds.
func compress_astc(img: Image) -> Image:
	var src := out_dir.path_join("cache/textures/.astc_in.png")
	var dst := out_dir.path_join("cache/textures/.astc_out.astc")
	var rgba := img.duplicate() as Image
	rgba.convert(Image.FORMAT_RGBA8)
	if rgba.save_png(src) != OK:
		return null
	DirAccess.remove_absolute(dst)
	var out := []
	if OS.execute(astcenc, ["-cl", src, dst, "4x4", "-medium", "-silent"], out, true) != 0:
		push_error("astcenc failed: %s" % out)
		return null
	var data := FileAccess.get_file_as_bytes(dst)
	if data.size() <= 16 or data.decode_u32(0) != 0x5CA1AB13:
		return null
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_ASTC_4x4, data.slice(16))

## Header of a .ctex file: {size, data_format, mipmaps, image_at}, or {} if it is not one.
func read_ctex(ctex_path: String) -> Dictionary:
	var f := FileAccess.open(ctex_path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "GST2":
		return {}
	f.get_32()  # format version
	var size := Vector2i(f.get_32(), f.get_32())
	f.seek(36)  # data format, mipmap limit and 3 reserved fields of the texture header
	var data_format := f.get_32()
	f.get_16()
	f.get_16()
	var mipmaps := f.get_32()
	f.get_32()  # image format
	return {"size": size, "data_format": data_format, "mipmaps": mipmaps, "image_at": f.get_position()}

## Decodes the full size image of a lossless (PNG or WebP) .ctex straight from the pack. Loading
## it as a texture instead keeps several copies alive (the texture's, the headless renderer's and
## get_image()'s), which took the setup past 1 GB on the largest images (107 MB decoded) and got it
## killed on 1 GB devices. Returns null for other formats. Only the base image is decoded; the
## caller rebuilds mipmaps when the header says there were any.
func decode_ctex(ctex_path: String, ctex: Dictionary) -> Image:
	if ctex["data_format"] != 1 and ctex["data_format"] != 2:
		return null
	var f := FileAccess.open(ctex_path, FileAccess.READ)
	f.seek(ctex["image_at"])
	var data := f.get_buffer(f.get_32())
	var img := Image.new()
	var err := img.load_png_from_buffer(data) if ctex["data_format"] == 1 else img.load_webp_from_buffer(data)
	if err != OK or img.is_empty():
		return null
	return img

func scale_textures() -> bool:
	var cache := "cache/textures"
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(cache))
	var scaled_script := load("res://stubs/ScaledTexture.gd")
	var done := 0
	var saved := 0
	var astc_done := 0
	# A different factor (another screen size) redoes the textures already scaled, from the
	# original .ctex files, which stay in the pack under their old names.
	var factor_path := out_dir.path_join(TEXTURE_FACTOR_FILE)
	var settings := "%d %s" % [texture_factor, "astc" if astcenc != "" else "rgba"]
	var rescale := FileAccess.get_file_as_string(factor_path).strip_edges() != settings
	for path in pck.entries:
		if not (path.ends_with(".png.import") or path.ends_with(".jpg.import") or path.ends_with(".svg.import")) or path.begins_with(TEXTURE_SKIP_PREFIX):
			continue
		var imp := read_import(path)
		var imported: String = imp[1]
		var cached_path := ""
		if imported.begins_with("res://%s/" % cache) and imported.ends_with(".res"):
			if not rescale:
				continue  # already scaled with this factor
			cached_path = imported
			imported = "res://.godot/imported/" + imported.get_file().trim_suffix(".res") + ".ctex"
		if not imported.ends_with(".ctex"):
			continue  # a VRAM-compressed variant
		var ctex := read_ctex(imported)
		if ctex.is_empty():
			continue
		var size: Vector2i = ctex["size"]
		var longest := maxi(size.x, size.y)
		if longest < TEXTURE_HALVE_FROM:
			continue
		var img := decode_ctex(imported, ctex)
		if img == null:
			var tex := load(path.trim_suffix(".import")) as Texture2D
			img = tex.get_image() if tex else null
		if img == null or img.is_compressed():
			continue
		var index_art := is_index_art(img)
		var had_mips: bool = img.has_mipmaps() or ctex["mipmaps"] > 0
		var use_astc := astcenc != "" and not index_art and not had_mips
		var factor := maxi(2 if use_astc else texture_factor, 4 if longest >= TEXTURE_QUARTER_FROM else 2)
		if had_mips:
			img.clear_mipmaps()
		var filter := Image.INTERPOLATE_NEAREST if index_art else Image.INTERPOLATE_BILINEAR
		img.resize(maxi(1, size.x / factor), maxi(1, size.y / factor), filter)
		if had_mips:
			img.generate_mipmaps()
		if use_astc:
			var astc := compress_astc(img)
			if astc != null:
				img = astc
				astc_done += 1
		var scaled = scaled_script.new()
		scaled.set_image(img)
		scaled.display_size = size
		var name: String = imported.get_file().get_basename() + ".res"
		if ResourceSaver.save(scaled, out_dir.path_join(cache + "/" + name)) != OK:
			push_error("cannot save " + name)
			return false
		if cached_path == "":
			var new_text: String = imp[0].replace('path="%s"' % imported, 'path="res://%s/%s"' % [cache, name])
			new_text = new_text.replace('type="CompressedTexture2D"', 'type="ImageTexture"')
			pck.replace(path, new_text.to_utf8_buffer())
		saved += size.x * size.y * 4 - img.get_data().size()
		done += 1
		if done % 50 == 0:
			printerr("PORT_SETUP: textures %d scaled" % done)
	DirAccess.remove_absolute(out_dir.path_join("cache/textures/.astc_in.png"))
	DirAccess.remove_absolute(out_dir.path_join("cache/textures/.astc_out.astc"))
	var ff := FileAccess.open(factor_path, FileAccess.WRITE)
	ff.store_string(settings)
	ff.close()
	printerr("PORT_SETUP: textures scaled=%d (factor %d, %d as ASTC) saved=%d MB" % [done, texture_factor, astc_done, saved / 1048576])
	return true
