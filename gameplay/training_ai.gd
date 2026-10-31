extends Node
## 离线训练桩。开局后按自身冷却向玩家放第一下小技能。主机等待真人或客户端时不行动。

var _timer := 1.4


func _physics_process(delta: float) -> void:
	var duel = _match()
	if duel == null or not duel.started or not duel.ai_enabled():
		return
	if not bool(get_parent().get_meta("alive", true)):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var result: Dictionary = duel.cast_as(2, 0)
	var cooldown := float(result.get("cooldown", 5.0))
	if str(result.get("code", "")) == "cooldown":
		cooldown = float(result.get("cooldown", 0.4))
	_timer = maxf(cooldown, 0.4)


func _match():
	var host := get_parent()
	if host == null:
		return null
	var root := host.get_parent()
	if root == null:
		return null
	return root.get_node_or_null("Match")
