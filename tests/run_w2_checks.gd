extends SceneTree
## W2 无头自检。退出码 0 且打印 “W2 checks passed” 才算通过。
## godot --headless --path . --script res://tests/run_w2_checks.gd

const AuthorityScript = preload("res://net/room_authority.gd")
const LibraryScript = preload("res://stand/stand_library.gd")
const CardScript = preload("res://stand/stand_card.gd")
const NetScript = preload("res://net/net_room.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mirror := _load("res://stand/fixtures/valid_mirror_walker.json")
	var pillar := _load("res://stand/fixtures/valid_pillar_guard.json")
	_check_sync(mirror, pillar)
	_check_library(mirror, pillar)
	_check_enet()
	await _check_room_scene(mirror, pillar)
	if _failed == 0:
		print("W2 checks passed")
		quit(0)
	else:
		print("W2 checks failed: %d" % _failed)
		quit(1)


func _check(cond: bool, message: String) -> void:
	if cond:
		return
	_failed += 1
	print("FAIL: ", message)


func _load(path: String) -> Dictionary:
	var card = CardScript.load_file(path)
	_check(card != null, "无法读取 " + path)
	if card == null:
		return {}
	return card.data.duplicate(true)


func _hp(snapshot: Dictionary, id: int) -> float:
	for peer in snapshot.get("peers", []):
		if int(peer.get("id", 0)) == id:
			return float(peer.get("hp", -1))
	return -1.0


func _layers(snapshot: Dictionary, id: int) -> int:
	for peer in snapshot.get("peers", []):
		if int(peer.get("id", 0)) == id:
			return int(peer.get("layers", -1))
	return -1


func _pos(snapshot: Dictionary, id: int) -> float:
	for peer in snapshot.get("peers", []):
		if int(peer.get("id", 0)) == id:
			return float(peer.get("px", 0))
	return 0.0


func _check_sync(mirror: Dictionary, pillar: Dictionary) -> void:
	if mirror.is_empty() or pillar.is_empty():
		return
	var room = AuthorityScript.new()
	_check(bool(room.add_combatant(1, mirror, Vector3(0, 0, 0)).get("ok", false)), "主机应能加入 1")
	_check(bool(room.add_combatant(2, pillar, Vector3(0, 0, -6)).get("ok", false)), "主机应能加入 2")
	room.set_position(1, Vector3(3, 1, 2))
	var moved: Dictionary = room.snapshot()
	_check(is_equal_approx(_pos(moved, 1), 3.0), "快照应同步位置")
	var before := _hp(moved, 2)
	var missed: Dictionary = room.cast(1, 1, 2, {"distance": 30.0, "cover": "none"})
	_check(str(missed.get("code", "")) == "out_of_range", "超射程的同步施法应无效")
	_check(is_equal_approx(_hp(room.snapshot(), 2), before), "无效施法不应掉血")
	room.tick(30.0)
	var hit: Dictionary = room.cast(1, 1, 2, {"distance": 3.0, "cover": "none"})
	_check(bool(hit.get("hit", false)), "射程内应命中")
	_check(_hp(room.snapshot(), 2) < before, "命中后对方生命应下降")
	var blocked: Dictionary = room.cast(1, 1, 2, {"distance": 3.0, "cover": "none"})
	_check(str(blocked.get("code", "")) == "cooldown", "冷却未好不能再放")
	room.tick(30.0)
	var again: Dictionary = room.cast(1, 1, 2, {"distance": 3.0, "cover": "none"})
	_check(bool(again.get("ok", false)), "跳过冷却后应能再放")
	var guard := 0
	while not bool(room.snapshot().get("finished", false)) and guard < 16:
		room.tick(30.0)
		room.cast(1, 1, 2, {"distance": 3.0, "cover": "none"})
		guard += 1
	var done: Dictionary = room.snapshot()
	_check(bool(done.get("finished", false)) and int(done.get("winner_id", 0)) == 1, "只剩一人时 1 应获胜")
	_check(_layers(done, 1) == 2, "击倒应叠 2 层而不是写进卡面")
	_check(not room.winner_card().has("layers"), "胜者卡本体不含成长层")
	var picked: Dictionary = room.grant_pickup(1)
	_check(bool(picked.get("ok", false)) and int(picked.get("layers", 0)) == 3, "击倒后再拾取仍顶在 3 层")
	var library = LibraryScript.new()
	var settled: Dictionary = room.settle(library)
	_check(bool(settled.get("ok", false)), "结算应成功")
	_check(library.size() == 1, "胜者卡应入库")
	_check(str(library.get_card(0).get("name", "")) == "镜步旅人", "入库的是胜者")
	_check(not library.get_card(0).has("layers"), "库里的卡不含成长层")
	var destroyed: Array = settled.get("destroyed", [])
	_check(destroyed.size() == 1 and bool(destroyed[0].get("destroyed", false)), "败者应标记销毁")
	_check(str(library.get_card(0).get("name", "")) != "柱卫", "败者卡名不应留在库里")
	room.grant_pickup(1)


func _check_library(mirror: Dictionary, pillar: Dictionary) -> void:
	if mirror.is_empty():
		return
	var library = LibraryScript.new()
	for index in 3:
		var copy := mirror.duplicate(true)
		copy.name = "旧%d" % index
		_check(bool(library.try_keep(copy).get("ok", false)), "预填保留库")
	var layered := mirror.duplicate(true)
	layered.layers = 3
	layered.name = "新胜者"
	var room = AuthorityScript.new()
	room.add_combatant(1, layered, Vector3.ZERO)
	room.add_combatant(2, pillar, Vector3(0, 0, -2))
	var guard := 0
	while not bool(room.snapshot().get("finished", false)) and guard < 16:
		room.tick(30.0)
		room.cast(1, 1, 2, {"distance": 2.0, "cover": "none"})
		guard += 1
	var settled: Dictionary = room.settle(library)
	_check(bool(settled.get("ok", false)), "满库结算应先弃旧再留")
	_check(bool(settled.get("kept", {}).get("discarded_oldest", false)), "应丢掉最旧的一张")
	_check(str(settled.get("kept", {}).get("dropped_name", "")) == "旧0", "丢掉的应是第一张")
	_check(library.size() == 3, "库大小仍是 3")
	var names := ""
	for index in library.size():
		names += str(library.get_card(index).get("name", "")) + ","
	_check(not ("旧0" in names) and ("新胜者" in names), "新卡在库里，最旧的不在：%s" % names)
	_check(not library.get_card(library.size() - 1).has("layers"), "替换入库也不带层数")
	var before := library.size()
	var rejected: Dictionary = library.keep_winner_replacing_oldest({"name": "坏卡"})
	_check(not bool(rejected.get("ok", true)), "非法卡不能借结算入库")
	_check(not bool(rejected.get("discarded_oldest", true)), "校验失败时不能先弃旧")
	_check(library.size() == before, "失败结算不改库大小")
	var loser_size := library.size()
	var destroyed: Dictionary = library.destroy_loser(pillar)
	_check(bool(destroyed.get("destroyed", false)) and not bool(destroyed.get("kept", true)), "销毁败者")
	_check(library.size() == loser_size, "销毁败者不应改库")


func _check_enet() -> void:
	var server: ENetMultiplayerPeer = null
	var client: ENetMultiplayerPeer = null
	var port_used := 0
	for port in range(27990, 28010):
		var candidate := ENetMultiplayerPeer.new()
		var err := candidate.create_server(port, 2)
		if err == OK:
			server = candidate
			port_used = port
			break
		candidate.close()
	_check(server != null, "ENet 应能监听本地端口")
	if server == null:
		return
	client = ENetMultiplayerPeer.new()
	var client_error := client.create_client("127.0.0.1", port_used)
	_check(client_error == OK, "ENet 客户端应能发起连接")
	var connected := false
	if client_error == OK:
		for _step in 50:
			server.poll()
			client.poll()
			if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				connected = true
				break
			OS.delay_msec(20)
	_check(connected, "回环上客户端应连上主机")
	client.close()
	server.close()
	var net = NetScript.new()
	get_root().add_child(net)
	var hosted: Dictionary = net.host_room(28021)
	_check(bool(hosted.get("ok", false)), "NetRoom.host_room 应成功：%s" % str(hosted.get("message", hosted.get("code", ""))))
	net.close_room()
	_check(net.mode == "offline", "关闭房间后应回到离线")
	get_root().remove_child(net)
	net.free()


func _check_room_scene(mirror: Dictionary, pillar: Dictionary) -> void:
	if mirror.is_empty() or pillar.is_empty():
		return
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "主场景应能加载")
	if packed == null:
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	await physics_frame
	var net = main.get_node("Net")
	net.mode = "host"
	var duel = main.get_node("Match")
	var guest := pillar.duplicate(true)
	guest.name = "客方柱卫"
	var began: Dictionary = duel.begin(mirror)
	_check(str(began.get("code", "")) == "waiting", "主机应等待第二张卡")
	var joined: Dictionary = duel.register_remote_card(2, guest)
	_check(bool(joined.get("ok", false)) and duel.started, "第二张合法卡进房后开局")
	var rejected: Dictionary = duel.register_remote_card(2, {"name": "坏"})
	_check(not bool(rejected.get("ok", true)), "第二张非法卡不能覆盖对局")
	var player: Node3D = main.get_node("Player")
	player.global_position = Vector3(0, 0.9, 0)
	duel.authority.set_position(2, Vector3(0, 0.9, -3))
	var before := _hp(duel.authority.snapshot(), 2)
	var hit: Dictionary = duel.cast_as(1, 1)
	_check(bool(hit.get("hit", false)), "同房施法应打中近处对手")
	_check(_hp(duel.authority.snapshot(), 2) < before, "场景房间里的生命应一起变")
	var dummy: Node3D = main.get_node("DummyTarget")
	_check(dummy.has_meta("hp"), "对手模型应带上同步后的生命")
	get_root().remove_child(main)
	main.free()
