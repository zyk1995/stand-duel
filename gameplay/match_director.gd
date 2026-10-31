extends Node
## 把进场卡、主机权威房间和场景里的两具模板人形接在一起。
## 离线时对手是柱卫训练桩。--host 时第二张卡来自客户端，--join 时只提交本地卡并跟快照。

const AuthorityScript = preload("res://net/room_authority.gd")
const LibraryScript = preload("res://stand/stand_library.gd")
const CardScript = preload("res://stand/stand_card.gd")
const CostumeScript = preload("res://ai/costume.gd")
const CoverScript = preload("res://gameplay/cover_query.gd")
const OPPONENT_PATH := "res://stand/fixtures/valid_pillar_guard.json"

var authority = null
var library = null
var started := false
var local_id := 1
var result_text := ""
var _settled := false
var _local_card: Dictionary = {}
var _remote_card: Dictionary = {}
var _opponent_card: Dictionary = {}
var _remote_peer_id := 2
var _broadcast_wait := 0.0


func _ready() -> void:
	authority = AuthorityScript.new()
	library = LibraryScript.new()
	var loaded = CardScript.load_file(OPPONENT_PATH)
	if loaded != null:
		_opponent_card = loaded.data.duplicate(true)


func ai_enabled() -> bool:
	return started and _net_mode() == "offline"


func begin(player_card: Dictionary) -> Dictionary:
	var verdict: Dictionary = _validate(player_card)
	if not bool(verdict.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_card",
			"message": "校验未通过，不能进局",
			"errors": verdict.get("errors", []),
		}
	_local_card = player_card.duplicate(true)
	_settled = false
	result_text = ""
	var player := _player()
	if player != null:
		CostumeScript.apply_to_body(player, _local_card)
	var mode := _net_mode()
	if mode == "client":
		var net = _net()
		if net != null and net.has_method("send_card"):
			net.send_card(JSON.stringify(_local_card))
		result_text = "已提交替身，等待主机开局"
		local_id = 2
		return {"ok": true, "code": "submitted"}
	authority.reset()
	if player == null:
		return {"ok": false, "code": "no_player", "message": "场景里没有玩家"}
	var added: Dictionary = authority.add_combatant(1, _local_card, player.global_position)
	if not bool(added.get("ok", false)):
		return added
	local_id = 1
	if mode == "host":
		if not _remote_card.is_empty():
			return _start_versus_remote()
		result_text = "等待第二名玩家"
		_apply_meta()
		return {"ok": true, "code": "waiting"}
	if _opponent_card.is_empty() or not bool(_validate(_opponent_card).get("ok", false)):
		return {"ok": false, "code": "no_opponent", "message": "训练桩卡无效"}
	var dummy := _dummy()
	var dummy_pos := dummy.global_position if dummy != null else player.global_position + Vector3(0, 0, -4)
	var foe: Dictionary = authority.add_combatant(2, _opponent_card, dummy_pos)
	if not bool(foe.get("ok", false)):
		return foe
	if dummy != null:
		CostumeScript.apply_to_body(dummy, _opponent_card)
	started = true
	result_text = "对局开始"
	_push_offline_positions()
	_apply_meta()
	return {"ok": true, "code": "started"}


func register_remote_card(peer_id: int, card: Dictionary) -> Dictionary:
	var verdict: Dictionary = _validate(card)
	if not bool(verdict.get("ok", false)):
		return {
			"ok": false,
			"code": "invalid_card",
			"message": "对方卡未通过校验",
			"errors": verdict.get("errors", []),
		}
	if started:
		return {"ok": false, "code": "already_started", "message": "对局已经开始"}
	_remote_card = card.duplicate(true)
	_remote_peer_id = peer_id if peer_id > 1 else 2
	if _local_card.is_empty():
		return {"ok": true, "code": "queued", "peer_id": peer_id}
	return _start_versus_remote()


func remote_position(peer_id: int, position: Vector3) -> void:
	if authority == null or not _peers_ready():
		return
	authority.set_position(peer_id, position)
	var avatar := _avatar(peer_id)
	if avatar != null and peer_id != local_id:
		avatar.global_position = position


func local_cast(skill_index: int) -> Dictionary:
	var net = _net()
	if net != null and str(net.mode) == "client":
		if net.has_method("send_cast"):
			net.send_cast(skill_index)
		return {"ok": true, "code": "sent"}
	return cast_as(local_id, skill_index)


func cast_as(attacker_id: int, skill_index: int) -> Dictionary:
	if authority == null or not started:
		return {"ok": false, "code": "not_started", "message": "还没进局"}
	if str(_net_mode()) != "client":
		_push_offline_positions()
	var target_id := _other_id(attacker_id)
	var context := {"cover": _cover_between(attacker_id, target_id)}
	var result: Dictionary = authority.cast(attacker_id, skill_index, target_id, context)
	_pull_bodies()
	_apply_meta()
	if bool(authority.snapshot().get("finished", false)):
		_settle()
	_broadcast_now()
	return result


func grant_local_pickup() -> Dictionary:
	if authority == null or not started:
		return {"ok": false, "code": "not_started"}
	var granted: Dictionary = authority.grant_pickup(local_id)
	_apply_meta()
	_broadcast_now()
	return granted


func apply_network_snapshot(data: Dictionary) -> void:
	if str(_net_mode()) != "client":
		return
	for peer in data.get("peers", []):
		if typeof(peer) != TYPE_DICTIONARY:
			continue
		var peer_id := int(peer.get("id", 0))
		var avatar := _avatar(peer_id)
		if avatar == null:
			continue
		if peer_id != local_id:
			avatar.global_position = Vector3(float(peer.get("px", 0.0)), float(peer.get("py", 0.0)), float(peer.get("pz", 0.0)))
		_write_meta(avatar, peer)
	result_text = str(data.get("result_text", result_text))
	if bool(data.get("finished", false)) and not _settled:
		_settled = true
		started = false
		if int(data.get("winner_id", 0)) == local_id and typeof(data.get("winner_card", null)) == TYPE_DICTIONARY:
			library.keep_winner_replacing_oldest(data.get("winner_card"))
		elif int(data.get("winner_id", 0)) != 0 and int(data.get("winner_id", 0)) != local_id:
			library.destroy_loser(_local_card)


func _physics_process(delta: float) -> void:
	var mode := _net_mode()
	if mode == "client":
		var uid := multiplayer.get_unique_id()
		if uid > 1:
			local_id = uid
		var player := _player()
		var net = _net()
		if player != null and net != null and started and net.has_method("send_position"):
			net.send_position(player.global_position)
		return
	if authority == null or not started:
		return
	authority.tick(delta)
	_push_offline_positions()
	_apply_meta()
	if mode == "host":
		_broadcast_wait -= delta
		if _broadcast_wait <= 0.0:
			_broadcast_wait = 0.1
			_broadcast_now()


func _start_versus_remote() -> Dictionary:
	var dummy := _dummy()
	var player := _player()
	var origin := player.global_position if player != null else Vector3.ZERO
	var dummy_pos := dummy.global_position if dummy != null else origin + Vector3(0, 0, -4)
	var foe: Dictionary = authority.add_combatant(_remote_peer_id, _remote_card, dummy_pos)
	if not bool(foe.get("ok", false)):
		return foe
	if dummy != null:
		CostumeScript.apply_to_body(dummy, _remote_card)
	started = true
	result_text = "对局开始"
	_apply_meta()
	_broadcast_now()
	return {"ok": true, "code": "started"}


func _settle() -> void:
	if _settled:
		return
	_settled = true
	started = false
	var settled: Dictionary = authority.settle(library)
	if bool(settled.get("ok", false)):
		var winner_name := str(authority.winner_card().get("name", ""))
		result_text = "胜者 %s 已写入保留库（%d/3）" % [winner_name, library.size()]
	else:
		result_text = "无人保留：%s" % str(settled.get("message", settled.get("code", "")))


func _broadcast_now() -> void:
	var net = _net()
	if net == null or str(net.mode) != "host" or not net.has_method("send_snapshot"):
		return
	var data: Dictionary = authority.snapshot()
	data.result_text = result_text
	if bool(data.get("finished", false)):
		data.winner_card = authority.winner_card()
	net.send_snapshot(data)


func _push_offline_positions() -> void:
	if authority == null:
		return
	var player := _player()
	if player != null:
		authority.set_position(local_id, player.global_position)
	if _net_mode() == "host":
		return
	var dummy := _dummy()
	if dummy != null:
		authority.set_position(2, dummy.global_position)


func _pull_bodies() -> void:
	var data: Dictionary = authority.snapshot()
	for peer in data.get("peers", []):
		if typeof(peer) != TYPE_DICTIONARY:
			continue
		var avatar := _avatar(int(peer.get("id", 0)))
		if avatar == null:
			continue
		if int(peer.get("id", 0)) != local_id or float(peer.get("hp", 1.0)) >= 0.0:
			avatar.global_position = Vector3(float(peer.px), float(peer.py), float(peer.pz))


func _apply_meta() -> void:
	if authority == null:
		return
	var data: Dictionary = authority.snapshot()
	for peer in data.get("peers", []):
		if typeof(peer) != TYPE_DICTIONARY:
			continue
		var avatar := _avatar(int(peer.get("id", 0)))
		if avatar == null:
			continue
		_write_meta(avatar, peer)


func _write_meta(avatar: Node, peer: Dictionary) -> void:
	avatar.set_meta("hp", float(peer.get("hp", 0.0)))
	avatar.set_meta("max_hp", float(peer.get("max_hp", 0.0)))
	avatar.set_meta("layers", int(peer.get("layers", 0)))
	avatar.set_meta("cooldowns", peer.get("cooldowns", [0.0, 0.0, 0.0]))
	avatar.set_meta("alive", bool(peer.get("alive", false)))
	if float(peer.get("hp", 0.0)) < float(peer.get("max_hp", 1.0)):
		avatar.set_meta("hurt_priority", 5.0)
	if int(peer.get("id", 0)) != local_id:
		avatar.visible = bool(peer.get("alive", true))


func _cover_between(attacker_id: int, target_id: int) -> String:
	var from := _position_of(attacker_id)
	var to := _position_of(target_id)
	return CoverScript.between(get_tree(), from + Vector3(0, 0.2, 0), to + Vector3(0, 0.2, 0))


func _position_of(id: int) -> Vector3:
	var data: Dictionary = authority.snapshot()
	for peer in data.get("peers", []):
		if typeof(peer) == TYPE_DICTIONARY and int(peer.get("id", 0)) == id:
			return Vector3(float(peer.px), float(peer.py), float(peer.pz))
	return Vector3.ZERO


func _other_id(attacker_id: int) -> int:
	var data: Dictionary = authority.snapshot()
	for peer in data.get("peers", []):
		if typeof(peer) != TYPE_DICTIONARY:
			continue
		var peer_id := int(peer.get("id", 0))
		if peer_id != attacker_id and bool(peer.get("alive", false)):
			return peer_id
	return 2 if attacker_id == 1 else 1


func _avatar(id: int) -> Node3D:
	if id == local_id:
		return _player()
	return _dummy()


func _peers_ready() -> bool:
	return authority != null and started


func _player() -> Node3D:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("Player") as Node3D


func _dummy() -> Node3D:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("DummyTarget") as Node3D


func _net():
	var parent_node := get_parent()
	if parent_node == null:
		return null
	return parent_node.get_node_or_null("Net")


func _net_mode() -> String:
	var net = _net()
	if net == null:
		return "offline"
	return str(net.mode)


func _validate(card: Dictionary) -> Dictionary:
	return load("res://stand/stand_validator.gd").validate(card)
