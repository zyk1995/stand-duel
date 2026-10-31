extends Node
class_name NetRoom
## ENet 主机 / 客户端。无头验收以 RoomAuthority 的同进程模拟为准。
## 双开：godot --path . -- --host 7777  与  godot --path . -- --join 127.0.0.1 7777
## 快照用 JSON 字符串走 RPC，避免字典在不同版本上的打包差异。密钥不会出现在这里。

signal snapshot_received(snapshot: Dictionary)

var mode := "offline"
var port := 0
var _peer: MultiplayerPeer = null
var _snapshot_wait := 0.0


func _ready() -> void:
	_read_args()


func host_room(listen_port: int = 7777) -> Dictionary:
	close_room()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(listen_port, 1)
	if err != OK:
		return {
			"ok": false,
			"code": "host_failed",
			"message": "无法监听端口 %d" % listen_port,
			"error": err,
		}
	_peer = peer
	port = listen_port
	mode = "host"
	multiplayer.multiplayer_peer = peer
	return {"ok": true, "code": "hosted", "port": listen_port, "peer_id": 1}


func join_room(address: String = "127.0.0.1", listen_port: int = 7777) -> Dictionary:
	close_room()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, listen_port)
	if err != OK:
		return {
			"ok": false,
			"code": "join_failed",
			"message": "无法连接 %s:%d" % [address, listen_port],
			"error": err,
		}
	_peer = peer
	port = listen_port
	mode = "client"
	multiplayer.multiplayer_peer = peer
	return {"ok": true, "code": "joining", "address": address, "port": listen_port}


func close_room() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	port = 0


func linked() -> bool:
	if _peer == null:
		return false
	if _peer is OfflineMultiplayerPeer:
		return false
	return _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func send_card(payload: String) -> void:
	if mode != "client" or not linked():
		return
	rpc_id(1, "rpc_submit_card", payload)


func send_cast(skill_index: int) -> void:
	if mode != "client" or not linked():
		return
	rpc_id(1, "rpc_cast", skill_index)


func send_position(position: Vector3) -> void:
	if mode != "client" or not linked():
		return
	rpc_id(1, "rpc_position", position.x, position.y, position.z)


func send_snapshot(data: Dictionary) -> void:
	if mode != "host" or not linked():
		return
	if multiplayer.get_peers().is_empty():
		return
	rpc("rpc_snapshot", JSON.stringify(data))


func poll_link() -> void:
	if _peer != null:
		_peer.poll()


@rpc("any_peer", "reliable")
func rpc_submit_card(payload: String) -> void:
	if not multiplayer.is_server():
		return
	var parsed = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var duel = get_parent().get_node_or_null("Match")
	if duel != null and duel.has_method("register_remote_card"):
		duel.register_remote_card(multiplayer.get_remote_sender_id(), parsed)


@rpc("any_peer", "reliable")
func rpc_cast(skill_index: int) -> void:
	if not multiplayer.is_server():
		return
	var duel = get_parent().get_node_or_null("Match")
	if duel != null and duel.has_method("cast_as"):
		duel.cast_as(multiplayer.get_remote_sender_id(), skill_index)


@rpc("any_peer", "unreliable")
func rpc_position(x: float, y: float, z: float) -> void:
	if not multiplayer.is_server():
		return
	var duel = get_parent().get_node_or_null("Match")
	if duel != null and duel.has_method("remote_position"):
		duel.remote_position(multiplayer.get_remote_sender_id(), Vector3(x, y, z))


@rpc("authority", "reliable")
func rpc_snapshot(payload: String) -> void:
	var parsed = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	snapshot_received.emit(parsed)
	var duel = get_parent().get_node_or_null("Match")
	if duel != null and duel.has_method("apply_network_snapshot"):
		duel.apply_network_snapshot(parsed)


func _read_args() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg := str(args[index])
		if arg == "--host" and index + 1 < args.size():
			host_room(int(args[index + 1]))
			index += 2
			continue
		if arg == "--join" and index + 2 < args.size():
			join_room(str(args[index + 1]), int(args[index + 2]))
			index += 3
			continue
		index += 1
