extends Node
## Offline stand-in for the PlayFabServices engine singleton compiled into Dome Keeper's
## custom Godot build. Registered as an autoload by the port's override.cfg so the game's
## scripts compile on stock Godot. Nothing ever logs in; every request reports failure.

signal logged(message)
signal logged_in
signal login_failed(message: String)
signal lobby_created(lobby)
signal lobbies_found(lobby_count: int)
signal find_lobbies_failed(error: String)
signal join_lobby_failed(error: String)
signal cloud_script_response(function_name: String, result: Dictionary)
signal local_endpoint_disconnected
signal leaderboard_loaded(result)
signal load_leaderboard_failed(error)
signal leaderboard_around_entity_loaded(result)
signal score_submitted(result)
signal score_submission_failed()

enum AccessPolicy { LOBBY_PUBLIC, LOBBY_FRIENDS, LOBBY_PRIVATE }

const OFFLINE := "offline"

func is_initialized() -> bool: return false
func is_initializing() -> bool: return false
func get_entity_id() -> String: return ""
func get_entity_type() -> String: return ""
func get_entity_token() -> String: return ""
func get_platform_user_token() -> String: return ""
func set_port(_port: int) -> void: pass
func update_recent_player(_platform_user_id) -> void: pass

func login_with_custom_id(_id, _title_id, _name) -> void: login_failed.emit.call_deferred(OFFLINE)
func login_with_steam(_ticket, _title_id, _name) -> void: login_failed.emit.call_deferred(OFFLINE)

func find_lobbies() -> void: find_lobbies_failed.emit.call_deferred(OFFLINE)
func get_lobby_search_results(_index: int) -> Dictionary: return {}

func get_leaderboard(_name, _start, _count, _version = -1) -> void: load_leaderboard_failed.emit.call_deferred(OFFLINE)
func get_leaderboard_around(_name, _count, _version = -1) -> void: load_leaderboard_failed.emit.call_deferred(OFFLINE)
func submit_score(_name, _scores, _metadata) -> void: score_submission_failed.emit.call_deferred()

func execute_cloud_script(function_name: String, _args = {}) -> void:
	cloud_script_response.emit.call_deferred(function_name, {"error": OFFLINE})
