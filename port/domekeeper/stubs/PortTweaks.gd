extends Node
## PortMaster tweaks for small handheld screens and 1 GB devices. Added as an autoload by
## setup/port_setup.gd. Environment overrides: DK_UI_SCALE (number, 0 = automatic).

## The title screen keeps hidden patch notes and credits panels whose labels hold the full
## changelog and credits. Hidden, the panels are ~0 px wide, so every character wraps onto its
## own line and Godot keeps shaping data for each one. setup/port_setup.gd moves that text into
## "port_text" metadata in the saved scene; it is put back only while a panel is shown. Labels
## the setup could not reach are emptied here as they enter the tree.
const DEFERRED_TEXT_PANELS := ["PatchNotesPanel", "CreditsPanel"]

## CJK fonts (about 36 MB of font data) are preloaded by the game's scripts for every language.
## setup/port_setup.gd points them at small stand-ins that remember the real file; when the
## language needs them, the real data is loaded into the same objects, so every reference the
## game already holds picks it up.
const CJK_FONTS := [
	"res://gui/fonts/ja/Noto Sans Mono CJK JP Regular.otf",
	"res://gui/fonts/simplified chinese/NotoSansSC-Regular.otf",
	"res://gui/fonts/traditional chinese/NotoSansTC-Regular.otf",
	"res://gui/fonts/noto/NotoSansTC-Regular.otf",
	"res://gui/fonts/korean/NotoSansKR-Regular.otf",
	"res://gui/fonts/ja/Makinas-4-Flat.otf",
	"res://gui/fonts/ja/Makinas-4-Square.otf",
	"res://gui/fonts/ja/Senobi-Gothic-Regular.ttf",
	"res://gui/fonts/ja/Senobi-Gothic-Medium.ttf",
	"res://gui/fonts/ja/Senobi-Gothic-Bold.ttf",
]
const CJK_LOCALES := ["ja", "ko", "zh"]
var _cjk_loaded := false

## Every map carries a map-sized render target (7 MB on a small map, ~22 MB on a huge one) for
## the Assessor's bundle effect. It stays 2x2 unless an Assessor (keeper2) is playing.
const BUNDLE_TRACKER := "BundleResourceTracker"
const BUNDLE_KEEPER := "keeper2"
var _bundle_trackers: Array[Node] = []

## The map's rock and cave background layers are drawn by two big per-pixel shaders, and the
## single core Mali G31 of h700 devices spends most of a frame on them (mine at 640x480: about
## 20 fps). Their code is patched here as it is loaded; the game files are not changed, and a
## patch whose expected code is missing (another game version) is skipped. Measured on an
## RG35XX H in the mine of a small map: 19-22 fps before, 28-30 after while mining (33 standing).
##
## map_main_stones_new (rock):
## * noise() builds two value noises per pixel from eight sin() hashes each. The lattice values
##   never change, so they are computed once into a 256x256 tile (_noise_tile), and noise()
##   reads it at the smoothstep-shifted position, where the hardware bilinear filter does the
##   same smoothstep interpolation. The tile repeats every 256 lattice cells (about 1900 world
##   units), invisible in the edge jitter it drives.
## * Unrevealed rock (rock falloff at or below the game's own 0.01 threshold) only shows the depth
##   gradient: no stone paint, and outlines and damage only occur next to tunnels, which are
##   always revealed. The falloff, cutout and gradient are computed first and the outline and
##   damage work (about 20 texture reads) is skipped there.
## map_background_edges (cave background): visible only where the tunnel mask is open, so its
## alpha is computed first and the rest skipped where it is 0 (exact: such pixels are not blended).
const STONES_SHADER := "res://content/map/shaders/map_main_stones_new.gdshader"
const EDGES_SHADER := "res://content/map/shaders/map_background_edges.gdshader"
const NOISE_TILE := 256
const NOISE_ORIGINAL := "753.5453123*sin(n + vec4(0., 1., 157., 158.))"
const NOISE_PATCHED := """uniform sampler2D port_noise : repeat_enable, filter_linear;
float noise(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	f = f*f*(3.-2.*f);
	return texture(port_noise, (p + f + 0.5) / 256.0).r;
}"""
const STONES_FALLOFF := ["\t// Main big noise", "\t// The color of the Lightedge"]
const STONES_CUTOUT := ["\t// Tunnel cutout is used", "\t// Generate the \"shadow\" fadeout"]
const STONES_GRADIENT := ["\t// Background Gradient", "\tCOLOR.rgb = mix(grad_color"]
const STONES_OUTLINES := "\t// Light Catcher outline"
const STONES_EARLY_OUT := """	if (mixed_falloff <= 0.01) {
		COLOR = vec4(grad_color, tunnel_cutout);
	} else {
"""
const EDGES_ALPHA := "COLOR.a = max(abs(1.0-step(texture(mask_map, UV).r, alpha_edge_pos)) - step(0.99, alpha_px), 0.0);"
const EDGES_ALPHA_PX := "float alpha_px = texture(bg_alpha_map, UV).r;"
const EDGES_EARLY_OUT := """	float port_alpha = max(abs(1.0-step(texture(mask_map, UV).r, alpha_edge_pos)) - step(0.99, texture(bg_alpha_map, UV).r), 0.0);
	if (port_alpha <= 0.0) {
		COLOR = vec4(0.0);
	} else {
"""
const FRAGMENT_HEAD := "void fragment() {\n"
var _patched_shaders: Array[Shader] = []  # held so the patched shaders stay in the resource cache

func _patch_map_shaders() -> void:
	for path in [STONES_SHADER, EDGES_SHADER]:
		if not ResourceLoader.exists(path):
			continue
		var shader: Shader = load(path)
		var code := patch_stones_code(shader.code) if path == STONES_SHADER else patch_edges_code(shader.code)
		if code == "":
			continue
		shader.code = code
		if path == STONES_SHADER:
			shader.set_default_texture_parameter("port_noise", _noise_tile())
		_patched_shaders.append(shader)

## The patched rock shader, or "" when the code is not the one these patches were written for.
static func patch_stones_code(code: String) -> String:
	var start := code.find("float noise(vec2 x) {")
	var end := code.find("\n}\n", start)
	if start < 0 or end < 0 or not NOISE_ORIGINAL in code.substr(start, end - start):
		return ""
	code = code.substr(0, start) + NOISE_PATCHED + code.substr(end + 2)
	# early-out: needs every block exactly once, in the original order
	var blocks := []
	for markers in [STONES_FALLOFF, STONES_CUTOUT, STONES_GRADIENT]:
		var from := code.find(markers[0])
		var to := code.find(markers[1], from)
		if from < 0 or to < 0 or code.count(markers[0]) != 1:
			return code
		blocks.append([from, to])
	var outlines := code.find(STONES_OUTLINES)
	if outlines < 0 or not (outlines < blocks[0][0] and blocks[0][1] <= blocks[1][0] and blocks[1][1] <= blocks[2][0]):
		return code
	var moved := ""
	for i in range(blocks.size() - 1, -1, -1):  # cut from the back so earlier offsets stay valid
		moved = code.substr(blocks[i][0], blocks[i][1] - blocks[i][0]) + moved
		code = code.substr(0, blocks[i][0]) + code.substr(blocks[i][1])
	code = code.insert(outlines, moved + STONES_EARLY_OUT)
	var last := code.rfind("}")
	return code.substr(0, last) + "\t}\n" + code.substr(last)

## The patched cave background shader, or "" when the code is not the expected one.
static func patch_edges_code(code: String) -> String:
	var start := code.find(FRAGMENT_HEAD)
	if start < 0 or code.count(FRAGMENT_HEAD) != 1 or not EDGES_ALPHA in code or not EDGES_ALPHA_PX in code:
		return ""
	start += FRAGMENT_HEAD.length()
	var end := code.rfind("}")
	return code.substr(0, start) + EDGES_EARLY_OUT + code.substr(start, end - start) + "\t}\n" + code.substr(end)

## Lattice value of the original noise() at n = x + 157 y + 113: the mean of
## fract(753.5453123 sin(n)) and the same at n + 113.
func _noise_tile() -> ImageTexture:
	var data := PackedByteArray()
	data.resize(NOISE_TILE * NOISE_TILE)
	for y in NOISE_TILE:
		for x in NOISE_TILE:
			var n := float(x + 157 * y + 113)
			var a := 753.5453123 * sin(n)
			var b := 753.5453123 * sin(n + 113.0)
			data[y * NOISE_TILE + x] = int(round(((a - floor(a)) + (b - floor(b))) * 127.5))
	return ImageTexture.create_from_image(Image.create_from_data(NOISE_TILE, NOISE_TILE, false, Image.FORMAT_L8, data))

func _needs_cjk(locale: String) -> bool:
	return locale.get_slice("_", 0) in CJK_LOCALES

func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	if not _cjk_loaded and _needs_cjk(TranslationServer.get_locale()):
		_load_cjk_fonts()
	_update_bundle_trackers()

func _update_bundle_trackers() -> void:
	_bundle_trackers = _bundle_trackers.filter(func(t): return is_instance_valid(t))
	if _bundle_trackers.is_empty():
		return
	var needed := _assessor_playing()
	for tracker in _bundle_trackers:
		var viewport: SubViewport = tracker.get_node_or_null("SubViewport")
		var map = tracker.owner
		if viewport == null or map == null or not ("tilemap_size" in map) or not map.isMapReady():
			continue
		var full := Vector2i(map.tilemap_size * 24)  # GameWorld.TILE_SIZE
		if full.x < 8:
			continue
		var target := full if needed else Vector2i(2, 2)
		if viewport.size != target and (viewport.size == full or viewport.size == Vector2i(2, 2)):
			viewport.size = target

func _assessor_playing() -> bool:
	var level := get_node_or_null("/root/Level")
	if level == null or not ("loadout" in level) or level.loadout == null:
		return true  # unknown: keep the effect
	for keeper in level.loadout.keepers:
		if keeper != null and "keeperId" in keeper and keeper.keeperId == BUNDLE_KEEPER:
			return true
	return false

func _load_cjk_fonts() -> void:
	_cjk_loaded = true
	for path in CJK_FONTS:
		if not ResourceLoader.exists(path):
			continue
		var font: FontFile = load(path)
		if not font.has_meta("port_real_path"):
			continue
		var real: FontFile = ResourceLoader.load(font.get_meta("port_real_path"), "", ResourceLoader.CACHE_MODE_IGNORE)
		if real == null:
			continue
		for prop in real.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and not prop.name.begins_with("resource_"):
				font.set(prop.name, real.get(prop.name))
		font.remove_meta("port_real_path")

func _enter_tree() -> void:
	_patch_map_shaders()
	get_tree().node_added.connect(_on_node_added)
	_apply_ui_scale()
	get_tree().root.size_changed.connect(_apply_ui_scale)

## The game lays out its UI for 1920x1080 and canvas_items stretch shrinks it to fit, so on a
## 640x480 screen text is drawn at a third of its design size. Grow the UI so text is drawn at
## least at half its design size, as long as the screen still shows 1280x1080 design units (the
## options panel with its Cancel and Apply row is about 1040 units tall), and never below the
## game's own scale. Examples: 640x480 1.33, 480x320 1.19, 720x720 1.33, 16:9 screens 1.0.
## The level is drawn in its own SubViewport sized to the window, so the camera view is unchanged.
const DESIGN_SIZE := Vector2(1920, 1080)
const MIN_VISIBLE := Vector2(1280, 1080)
const TARGET_TEXT_SCALE := 0.5

func _apply_ui_scale() -> void:
	var win := get_tree().root
	var size := Vector2(win.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var base := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var wanted := minf(TARGET_TEXT_SCALE, minf(size.x / MIN_VISIBLE.x, size.y / MIN_VISIBLE.y))
	var s := maxf(1.0, wanted / base)
	var env := OS.get_environment("DK_UI_SCALE")
	if env.is_valid_float() and env.to_float() > 0.0:
		s = env.to_float()
	if not is_equal_approx(win.content_scale_factor, s):
		win.content_scale_factor = s

func _on_node_added(node: Node) -> void:
	if node.name == BUNDLE_TRACKER:
		_bundle_trackers.append(node)
	if node is Label and not node.has_meta("port_text") and node.text != "" and _in_deferred_panel(node):
		node.set_meta("port_text", node.text)
		node.text = ""
	elif node.name in DEFERRED_TEXT_PANELS and node is CanvasItem:
		node.visibility_changed.connect(_on_deferred_panel_visibility.bind(node))

func _in_deferred_panel(node: Node) -> bool:
	var p := node.get_parent()
	while p:
		if p.name in DEFERRED_TEXT_PANELS:
			return true
		p = p.get_parent()
	return false

func _on_deferred_panel_visibility(panel: CanvasItem) -> void:
	var shown := panel.is_visible_in_tree()
	for label in panel.find_children("*", "Label", true, false):
		if not label.has_meta("port_text"):
			continue
		if shown and label.text == "":
			label.text = label.get_meta("port_text")
		elif not shown:
			# keep whatever the game set meanwhile, then release the shaped text
			if label.text != "":
				label.set_meta("port_text", label.text)
			label.text = ""
