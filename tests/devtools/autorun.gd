extends Node
# Test-only autoload: with --autorun=<regular-small|regular-medium|regular-large|regular-huge>,
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
