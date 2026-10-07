extends Node
# Test-only autoload: with --autorun=<regular-small|regular-medium|regular-large|regular-huge|lobby>,
# start a run from the loadout stage as soon as it is up.
var size := ""
var done := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autorun="):
			size = arg.trim_prefix("--autorun=")

var title_done := false

func _process(_d: float) -> void:
	if size == "" or done or Engine.get_process_frames() % 60 != 0:
		return
	if not title_done and not "--autorun-notitle" in OS.get_cmdline_user_args():
		for t in get_tree().root.find_children("TitleStage", "", true, false):
			if t.has_method("_on_singleplayer_button_pressed") and t.is_node_ready():
				title_done = true
				if size == "options":
					done = true
					_options_shots(t)
					return
				if size == "popups":
					done = true
					_popup_shots()
					return
				await get_tree().create_timer(3.0).timeout
				if t.has_method("disableOnlineServices") and not Options.onlineMultiplayerDecided:
					Options.onlineMultiplayerDecided = true
					Options.allowOnlineMultiplayer = false
				t._on_singleplayer_button_pressed()
				return
	var stage = null
	for n in get_tree().root.find_children("MultiplayerLoadoutStage", "", true, false):
		if n.has_method("startRun") and n.is_node_ready():
			stage = n
	if stage == null:
		return
	done = true
	if size == "lobby":
		return  # --autorun=lobby: walk into the singleplayer lobby and stay there
	await get_tree().create_timer(6.0).timeout
	stage.gameModeSelected("relichunt")
	await get_tree().create_timer(2.0).timeout
	var dome = Data.loadoutDomes[0]
	var gadget = Data.loadoutGadgets[0]
	stage.domeSelected(dome, "team1")
	stage.primaryGadgetSelected(gadget, "team1")
	stage.mapSizeSelected(size)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(stage._startRunChoice):
		stage._startRunChoice.set_enabled(true)
	_log("autorun: mode=relichunt dome=%s gadget=%s map=%s" % [dome, gadget, size])
	stage.startRun()

func _log(msg: String) -> void:
	var f := FileAccess.open(OS.get_environment("AUTORUN_LOG") if OS.has_environment("AUTORUN_LOG") else "user://autorun.log", FileAccess.WRITE)
	if f: f.store_line(msg)


# --autorun=options: open Options from the title, save a screenshot of every category and of the
# input popups into $SHOT_DIR (opt_<name>.png), then quit.
func _shot(name: String) -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_DIR") if OS.has_environment("SHOT_DIR") else "/tmp"
	get_viewport().get_texture().get_image().save_png("%s/opt_%s.png" % [dir, name])
	_log("shot " + name)

func _options_shots(t: Node) -> void:
	await get_tree().create_timer(4.0).timeout
	if t.has_method("disableOnlineServices") and not Options.onlineMultiplayerDecided:
		Options.onlineMultiplayerDecided = true
		Options.allowOnlineMultiplayer = false
	await _shot("title")
	t._on_OptionsButton_pressed()
	await get_tree().create_timer(1.0).timeout
	var panels := get_tree().root.find_children("*", "", true, false).filter(func(n): return n.has_method("showCategory") and "categories" in n)
	if panels.is_empty():
		_log("no options panel")
		OS.kill(OS.get_process_id())  # Godot segfaults while shutting down this game; SIGKILL leaves no core dump
		return
	var panel = panels[0]
	for cat in panel.categories:
		panel.showCategory(cat)
		await _shot(cat)
	for popup in [["gamepadkeeper", false], ["mousekeeper", true]]:
		panel.showCategory("Gamepad")
		panel._on_open_keeper_input_settings_button_pressed(popup[1])
		await _shot(popup[0])
		for p in panel.get_parent().get_children():
			if p.has_method("showCategory") and p != panel:
				for c in p.get("categories") if "categories" in p else []:
					p.showCategory(c)
					await _shot(popup[0] + "_" + str(c))
				p.queue_free()
	panel._on_KeybindingsButton_pressed()
	await _shot("keybindings")
	for pc in get_tree().root.find_children("*", "PanelContainer", true, false):
		if pc.get_parent() is CenterContainer and pc.is_visible_in_tree():
			_log2("panel %s parent %s size %s scale %s pivot %s view %s pos %s" % [pc.get_path(), pc.get_parent().size, pc.size, pc.scale, pc.pivot_offset, pc.get_viewport_rect().size, pc.global_position])
	OS.kill(OS.get_process_id())  # Godot segfaults while shutting down this game; SIGKILL leaves no core dump


# --autorun=popups: show every scene listed in $POPUPS_LIST (one res:// path per line) on its own
# CanvasLayer over the title, save opt_popup_<name>.png into $SHOT_DIR, free it, then quit.
func _popup_shots() -> void:
	await get_tree().create_timer(4.0).timeout
	Options.onlineMultiplayerDecided = true
	for path in FileAccess.get_file_as_string(OS.get_environment("POPUPS_LIST")).split("\n", false):
		var packed = load(path)
		if not packed:
			_log("cannot load " + path)
			continue
		var layer := CanvasLayer.new()
		layer.layer = 90
		get_tree().root.add_child(layer)
		var node = packed.instantiate()
		layer.add_child(node)
		if node is CanvasItem:
			node.visible = true
		await _shot("popup_" + path.get_file().get_basename())
		# $POPUP_CALL=<method>: call it on the scene (e.g. open Options from the pause menu), shoot again
		var method := OS.get_environment("POPUP_CALL")
		if method != "" and node.has_method(method):
			node.call(method)
			await _shot("popup_" + path.get_file().get_basename() + "_" + method)
		layer.queue_free()
	OS.kill(OS.get_process_id())  # Godot segfaults while shutting down this game; SIGKILL leaves no core dump

func _log2(msg: String) -> void:
	var f := FileAccess.open(OS.get_environment("SHOT_DIR") + "/panels.txt", FileAccess.READ_WRITE if FileAccess.file_exists(OS.get_environment("SHOT_DIR") + "/panels.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(msg)
