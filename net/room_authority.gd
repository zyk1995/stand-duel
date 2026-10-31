extends RefCounted
class_name RoomAuthority
## 主机权威的一局状态。位置、生命、施法、胜负都先落在这里，再广播给表现层。
## 同进程可以塞进两名战斗员，用来模拟 2 人同房，不必先拉起 ENet。

const Rules = preload("res://gameplay/combat_rules.gd")

var _peers: Dictionary = {}
var _order: Array = []
var _winner_id := 0
var _finished := false
var _log: Array = []


func reset() -> void:
	_peers = {}
	_order = []
	_winner_id = 0
	_finished = false
	_log = []


func add_combatant(id: int, card: Dictionary, position: Vector3) -> Dictionary:
	if _peers.has(id):
		return {"ok": false, "code": "duplicate", "message": "房间里已有该编号"}
	var stats = card.get("stats", {})
	if typeof(stats) != TYPE_DICTIONARY:
		stats = {}
	var hp := Rules.max_hp(Rules.stat_value(stats, "stamina", 3))
	_peers[id] = {
		"id": id,
		"card": card.duplicate(true),
		"px": position.x,
		"py": position.y,
		"pz": position.z,
		"hp": hp,
		"max_hp": hp,
		"alive": true,
		"layers": 0,
		"cooldowns": [0.0, 0.0, 0.0],
		"stun": 0.0,
		"window": 0.0,
		"revealed": 0.0,
	}
	_order.append(id)
	return {"ok": true, "hp": hp, "max_hp": hp}


func set_position(id: int, position: Vector3) -> Dictionary:
	if not _peers.has(id):
		return {"ok": false, "code": "missing"}
	_peers[id].px = position.x
	_peers[id].py = position.y
	_peers[id].pz = position.z
	return {"ok": true}


func grant_pickup(id: int) -> Dictionary:
	if not _peers.has(id):
		return {"ok": false, "code": "missing"}
	if not bool(_peers[id].alive):
		return {"ok": false, "code": "dead"}
	_peers[id].layers = Rules.add_layers(int(_peers[id].layers), "pickup")
	return {"ok": true, "layers": int(_peers[id].layers)}


func tick(delta: float) -> void:
	for id in _order:
		var peer: Dictionary = _peers[id]
		var cds: Array = peer.cooldowns
		for i in cds.size():
			cds[i] = maxf(0.0, float(cds[i]) - delta)
		peer.stun = maxf(0.0, float(peer.stun) - delta)
		peer.window = maxf(0.0, float(peer.window) - delta)
		peer.revealed = maxf(0.0, float(peer.revealed) - delta)


func cast(attacker_id: int, skill_index: int, target_id: int, context: Dictionary = {}) -> Dictionary:
	if _finished:
		return {"ok": false, "code": "finished", "message": "对局已结束"}
	if not _peers.has(attacker_id) or not _peers.has(target_id):
		return {"ok": false, "code": "missing", "message": "战斗员不在房间里"}
	if attacker_id == target_id:
		return {"ok": false, "code": "bad_target", "message": "不能锁定自己"}
	var attacker: Dictionary = _peers[attacker_id]
	var defender: Dictionary = _peers[target_id]
	if not bool(attacker.alive) or not bool(defender.alive):
		return {"ok": false, "code": "dead", "message": "有一方已经倒下"}
	if float(attacker.stun) > 0.0:
		return {"ok": false, "code": "stun", "message": "硬直中"}
	if skill_index < 0 or skill_index > 2:
		return {"ok": false, "code": "bad_skill", "message": "技能槽无效"}
	var skill := _skill(attacker.card, skill_index)
	if skill.is_empty():
		return {"ok": false, "code": "bad_skill", "message": "该槽没有技能"}
	var cds: Array = attacker.cooldowns
	if float(cds[skill_index]) > 0.0:
		return {
			"ok": false,
			"code": "cooldown",
			"message": "技能冷却中",
			"cooldown": float(cds[skill_index]),
		}
	var ctx := {}
	if typeof(context) == TYPE_DICTIONARY:
		ctx = context.duplicate(true)
	if not ctx.has("distance"):
		ctx.distance = _distance(attacker, defender)
	if not ctx.has("cover"):
		ctx.cover = "none"
	ctx.is_ultimate = skill_index == 2
	ctx.layers = int(attacker.layers)
	ctx.defender_stats = defender.card.get("stats", {})
	ctx.defender_window = float(defender.window)
	var resolved: Dictionary = Rules.resolve(attacker.card.get("stats", {}), skill, ctx)
	if not bool(resolved.get("ok", false)):
		return resolved
	if bool(resolved.get("hit", false)):
		defender.hp = float(defender.hp) - float(resolved.get("damage", 0.0))
		if float(defender.hp) <= 0.0:
			defender.hp = 0.0
			defender.alive = false
			attacker.layers = Rules.add_layers(int(attacker.layers), "knockdown")
		_apply_knockback(attacker, defender, float(resolved.get("knockback", 0.0)))
		_apply_dash(attacker, defender, float(resolved.get("dash_distance", 0.0)))
		var control := float(resolved.get("control_duration", 0.0))
		if control > 0.0:
			defender.stun = maxf(float(defender.stun), control)
	var self_damage := float(resolved.get("self_damage", 0.0))
	if self_damage > 0.0:
		attacker.hp = float(attacker.hp) - self_damage
		if float(attacker.hp) <= 0.0:
			attacker.hp = 0.0
			attacker.alive = false
	attacker.stun = maxf(float(attacker.stun), float(resolved.get("self_stun", 0.0)))
	attacker.window = maxf(float(attacker.window), float(resolved.get("window", 0.0)))
	if bool(resolved.get("revealed", false)):
		attacker.revealed = maxf(float(attacker.revealed), float(resolved.get("reveal_time", 3.0)))
	cds[skill_index] = float(resolved.get("cooldown", 0.0))
	_log.append({
		"caster": attacker_id,
		"skill": skill_index,
		"code": str(resolved.get("code", "")),
	})
	_check_finish()
	var out := resolved.duplicate(true)
	out.snapshot = snapshot()
	return out


func snapshot() -> Dictionary:
	var peers: Array = []
	for id in _order:
		var peer: Dictionary = _peers[id]
		peers.append({
			"id": int(peer.id),
			"name": str(peer.card.get("name", "")),
			"px": float(peer.px),
			"py": float(peer.py),
			"pz": float(peer.pz),
			"hp": float(peer.hp),
			"max_hp": float(peer.max_hp),
			"alive": bool(peer.alive),
			"layers": int(peer.layers),
			"cooldowns": [float(peer.cooldowns[0]), float(peer.cooldowns[1]), float(peer.cooldowns[2])],
			"stun": float(peer.stun),
			"window": float(peer.window),
			"revealed": float(peer.revealed),
		})
	return {
		"peers": peers,
		"finished": _finished,
		"winner_id": _winner_id,
		"log_size": _log.size(),
	}


func winner_card() -> Dictionary:
	if _winner_id == 0 or not _peers.has(_winner_id):
		return {}
	return (_peers[_winner_id].card as Dictionary).duplicate(true)


func settle(library) -> Dictionary:
	if not _finished:
		return {"ok": false, "code": "ongoing", "message": "对局未结束"}
	if _winner_id == 0:
		return {"ok": false, "code": "double_ko", "message": "无人存活，双方都不入库"}
	var kept: Dictionary = library.keep_winner_replacing_oldest(winner_card())
	var destroyed: Array = []
	for id in _order:
		if int(id) == _winner_id:
			continue
		destroyed.append(library.destroy_loser(_peers[id].card))
	return {
		"ok": bool(kept.get("ok", false)),
		"winner_id": _winner_id,
		"kept": kept,
		"destroyed": destroyed,
		"code": str(kept.get("code", "kept")),
	}


func _check_finish() -> void:
	var alive: Array = []
	for id in _order:
		if bool(_peers[id].alive):
			alive.append(int(id))
	if _order.size() >= 2 and alive.size() <= 1:
		_finished = true
		_winner_id = int(alive[0]) if alive.size() == 1 else 0


func _skill(card: Dictionary, index: int) -> Dictionary:
	if index == 2:
		var ultimate = card.get("ultimate", {})
		if typeof(ultimate) != TYPE_DICTIONARY:
			return {}
		return ultimate
	var skills = card.get("skills", [])
	if typeof(skills) != TYPE_ARRAY or index < 0 or index >= skills.size():
		return {}
	if typeof(skills[index]) != TYPE_DICTIONARY:
		return {}
	return skills[index]


func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx := float(a.px) - float(b.px)
	var dy := float(a.py) - float(b.py)
	var dz := float(a.pz) - float(b.pz)
	return sqrt(dx * dx + dy * dy + dz * dz)


func _apply_knockback(attacker: Dictionary, defender: Dictionary, distance: float) -> void:
	if distance <= 0.0:
		return
	var dx := float(defender.px) - float(attacker.px)
	var dz := float(defender.pz) - float(attacker.pz)
	var length := sqrt(dx * dx + dz * dz)
	if length <= 0.001:
		return
	defender.px = float(defender.px) + dx / length * distance
	defender.pz = float(defender.pz) + dz / length * distance


func _apply_dash(attacker: Dictionary, defender: Dictionary, distance: float) -> void:
	if distance <= 0.0:
		return
	var dx := float(defender.px) - float(attacker.px)
	var dz := float(defender.pz) - float(attacker.pz)
	var length := sqrt(dx * dx + dz * dz)
	if length <= 0.001:
		return
	var step := minf(distance, maxf(0.0, length - 0.8))
	attacker.px = float(attacker.px) + dx / length * step
	attacker.pz = float(attacker.pz) + dz / length * step
