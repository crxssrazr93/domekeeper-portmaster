class_name PlayFabPartyMultiplayerPeer
extends MultiplayerPeerExtension
## Offline stand-in for the PlayFab Party multiplayer peer. Creating or joining a lobby
## always fails, which the game reports as a normal network error.

signal logged(message)
signal create_network_failed(error: String)
signal connect_to_network_failed(error: String)
signal create_endpoint_failed(error: String)

func create_with_lobby(_name, _version, _policy) -> void:
	create_network_failed.emit.call_deferred("offline")

func join_lobby(_connection_string) -> void:
	connect_to_network_failed.emit.call_deferred("offline")

func set_lobby_crossplay_status(_enabled) -> void: pass

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return MultiplayerPeer.CONNECTION_DISCONNECTED
func _get_unique_id() -> int: return 1
func _is_server() -> bool: return true
func _poll() -> void: pass
func _close() -> void: pass
func _get_available_packet_count() -> int: return 0
func _get_max_packet_size() -> int: return 1 << 16
