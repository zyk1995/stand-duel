extends SceneTree
## W1 无头自检。退出码 0 且打印 “W1 checks passed” 才算通过。
## godot --headless --path . --script res://tests/run_w1_checks.gd

const Rules = preload("res://gameplay/combat_rules.gd")
const CombatScript = preload("res://gameplay/combat_stub.gd")
const CardScript = preload("res://stand/stand_card.gd")
const CoverScript = preload("res://gameplay/cover_query.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_formulas()
	_check_fixture_skills()
	_check_rules()
	await _check_covers()
	if _failed == 0:
		print("W1 checks passed")
		quit(0)
	else:
		print("W1 checks failed: %d" % _failed)
		quit(1)


func _check(cond: bool, message: String) -> void:
	if cond:
		return
	_failed += 1
	print("FAIL: ", message)


func _skill(primary: Array, range_value: float, cooldown: float, kind: String = "damage") -> Dictionary:
	return {
		"name": "测试技",
		"effect": "用于结算测试。",
		"kind": kind,
		"primary_stats": primary,
		"condition": "测试",
		"range": range_value,
		"cooldown": cooldown,
		"duration": 2.0,
		"cover_interact": "测试",
	}


func _stats(power: int, speed: int, range_stat: int, stamina: int, precision: int, growth: int) -> Dictionary:
	return {
		"power": power,
		"speed": speed,
		"range": range_stat,
		"stamina": stamina,
		"precision": precision,
		"growth": growth,
	}


func _hit(attacker: Dictionary, skill: Dictionary, context: Dictionary) -> Dictionary:
	return Rules.resolve(attacker, skill, context)


func _check_formulas() -> void:
	_check(is_equal_approx(Rules.damage_factor(1), 0.8), "力量 1 倍率")
	_check(is_equal_approx(Rules.damage_factor(3), 1.0), "力量 3 倍率")
	_check(is_equal_approx(Rules.damage_factor(5), 1.2), "力量 5 倍率")
	_check(is_equal_approx(Rules.cooldown_factor(1), 1.1), "速度 1 冷却系数")
	_check(is_equal_approx(Rules.cooldown_factor(3), 1.0), "速度 3 冷却系数")
	_check(is_equal_approx(Rules.cooldown_factor(5), 0.9), "速度 5 冷却系数")
	_check(is_equal_approx(Rules.max_hp(1), 830.0), "持续力 1 生命")
	_check(is_equal_approx(Rules.max_hp(3), 990.0), "持续力 3 生命")
	_check(is_equal_approx(Rules.max_hp(5), 1150.0), "持续力 5 生命")
	_check(Rules.BASE_HP == 1000.0, "基准生命应为 1000")
	_check(Rules.SMALL_DAMAGE >= 180.0 and Rules.SMALL_DAMAGE <= 220.0, "小技能基准伤应落在 180–220")
	_check(Rules.ULT_DAMAGE >= 350.0 and Rules.ULT_DAMAGE <= 450.0, "大招基准伤应落在 350–450")
	_check(Rules.add_layers(0, "pickup") == 1, "拾取加 1 层")
	_check(Rules.add_layers(0, "knockdown") == 2, "击倒加 2 层")
	_check(Rules.KNOCKDOWN_LAYERS > Rules.PICKUP_LAYERS, "击倒收益应高于拾取")
	_check(Rules.add_layers(2, "knockdown") == 3, "层数不能超过 3")
	_check(Rules.add_layers(3, "pickup") == 3, "满层后再拾取仍是 3")
	_check(is_equal_approx(Rules.growth_factor(5, 0), 1.0), "0 层不加伤")
	var order := Rules.resolve_order()
	_check(order[0] == "range" and order[1] == "precision" and order[2] == "power", "前三步顺序")
	_check(order[3] == "stamina" and order[4] == "speed" and order[5] == "growth", "后三步顺序")


func _check_fixture_skills() -> void:
	var loaded = CardScript.load_file("res://stand/fixtures/valid_mirror_walker.json")
	_check(loaded != null, "应能读到镜步旅人")
	if loaded == null:
		return
	var card: Dictionary = loaded.data
	var stats: Dictionary = card.stats
	var slash: Dictionary = card.skills[0]
	var stab: Dictionary = card.skills[1]
	var ultimate: Dictionary = card.ultimate
	var slash_hit := _hit(stats, slash, {"distance": 3.0, "cover": "none", "defender_stats": stats, "layers": 0})
	_check(bool(slash_hit.hit), "侧闪斩在射程内应命中")
	_check(is_equal_approx(float(slash_hit.damage), 200.0), "未绑力量时伤害不吃力量，保持基础 200")
	_check(is_equal_approx(float(slash_hit.cooldown), 5.0 * (1.15 - 0.05 * 4.0)), "侧闪斩冷却吃速度 4")
	_check(is_equal_approx(float(slash_hit.dash_distance), 4.0 * (0.85 + 0.05 * 4.0)), "位移距离吃速度")
	var stab_hit := _hit(stats, stab, {"distance": 6.0, "cover": "none", "defender_stats": stats, "layers": 0})
	_check(is_equal_approx(float(stab_hit.damage), 200.0 * (0.7 + 0.1 * 4.0)), "破势刺按力量 4 结算")
	_check(is_equal_approx(float(stab_hit.cooldown), 6.0), "破势刺未绑速度，冷却保持标称")
	var far := _hit(stats, stab, {"distance": 6.01, "cover": "none", "defender_stats": stats})
	_check(str(far.code) == "out_of_range" and not bool(far.hit), "超出 authored 射程无效，力量不能越帽")
	_check(far.applied.size() == 1 and str(far.applied[0]) == "range", "超射程应停在射程步")
	var ult := _hit(stats, ultimate, {"distance": 5.0, "cover": "none", "defender_stats": stats, "is_ultimate": true})
	_check(bool(ult.hit), "大招在射程内应命中")
	_check(is_equal_approx(float(ult.damage), 400.0 * (0.7 + 0.1 * 4.0)), "大招基础伤 400 再吃力量")
	_check(is_equal_approx(float(ult.cooldown), 22.0 * (1.15 - 0.05 * 4.0)), "大招冷却吃速度")
	_check(float(ult.window) >= 1.0 and not bool(ult.revealed), "镜域连斩的代价是空窗")
	var combat = CombatScript.new()
	var via_node: Dictionary = combat.resolve_hit(stats, stab, {"distance": 6.0, "cover": "none", "defender_stats": stats})
	_check(is_equal_approx(float(via_node.damage), float(stab_hit.damage)), "场景节点与公式模块一致")
	combat.free()


func _check_rules() -> void:
	var open_low := _hit(_stats(3, 3, 3, 3, 1, 3), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	var open_high := _hit(_stats(3, 3, 3, 3, 5, 3), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(is_equal_approx(float(open_low.damage), float(open_high.damage)), "开阔地精密不加伤害")
	var half_low := _hit(_stats(3, 3, 3, 3, 2, 3), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "half", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	var half_mid := _hit(_stats(3, 3, 3, 3, 3, 3), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "half", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	var half_high := _hit(_stats(3, 3, 3, 3, 5, 3), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "half", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(str(half_low.code) == "half_cover" and not bool(half_low.hit), "精密低于 3 打不中半掩")
	_check(bool(half_mid.hit) and bool(half_high.hit), "精密达到中轴应打中半掩")
	_check(is_equal_approx(float(half_mid.damage), float(open_low.damage) * 0.5), "半掩命中固定折半")
	_check(is_equal_approx(float(half_high.damage), float(half_mid.damage)), "半掩命中后精密不再加伤")
	var blocked := _hit(_stats(5, 5, 5, 5, 5, 5), _skill(["power"], 8.0, 5.0), {"distance": 1.0, "cover": "full", "defender_stats": _stats(1, 1, 1, 1, 1, 1)})
	_check(str(blocked.code) == "full_cover" and float(blocked.damage) == 0.0, "全掩完全阻挡")
	_check(blocked.applied.size() == 2, "全掩应停在精密步")
	var frail := _hit(_stats(4, 1, 1, 1, 3, 1), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(1, 1, 1, 1, 1, 1)})
	var tough := _hit(_stats(4, 1, 1, 1, 3, 1), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(1, 1, 1, 5, 1, 1)})
	_check(is_equal_approx(float(frail.damage), float(tough.damage)), "持续力不改本次伤害")
	_check(is_equal_approx(float(frail.max_hp), 830.0) and is_equal_approx(float(tough.max_hp), 1150.0), "持续力只体现在生命上限")
	var slow := _hit(_stats(5, 1, 1, 3, 3, 1), _skill(["speed"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	var fast := _hit(_stats(1, 5, 1, 3, 3, 1), _skill(["speed"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(is_equal_approx(float(slow.damage), float(fast.damage)), "速度不加伤害")
	_check(is_equal_approx(float(fast.cooldown), 5.0 * 0.9) and is_equal_approx(float(slow.cooldown), 5.0 * 1.1), "速度只改冷却")
	var ranged := _skill(["range"], 10.0, 5.0)
	var long := _hit(_stats(5, 1, 5, 3, 3, 1), ranged, {"distance": 12.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	var longer := _hit(_stats(5, 1, 5, 3, 3, 1), ranged, {"distance": 12.01, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(bool(long.hit) and is_equal_approx(float(long.effective_range), 12.0), "绑射程时按 0.7+0.1×射程放大")
	_check(not bool(longer.hit), "高力量也不能打出射程帽")
	var grown := _hit(_stats(3, 3, 3, 3, 3, 4), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3), "layers": 2})
	_check(is_equal_approx(float(grown.growth_factor), 1.0 + 0.03 * 4.0 * 2.0), "成长层参与最后一步")
	_check(is_equal_approx(float(grown.damage), 200.0 * (1.0 + 0.03 * 4.0 * 2.0)), "有层数才放大伤害")
	var triple := _skill(["power", "speed", "range"], 8.0, 5.0)
	var rejected := _hit(_stats(5, 5, 5, 3, 3, 3), triple, {"distance": 1.0, "cover": "none"})
	_check(not bool(rejected.ok) and str(rejected.code) == "triple_dip" and float(rejected.damage) == 0.0, "战斗侧拒绝三连吃")
	var cheap := _skill(["power"], 8.0, 0.0)
	var clamped := _hit(_stats(3, 3, 3, 3, 3, 3), cheap, {"distance": 1.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(is_equal_approx(float(clamped.cooldown), 4.0), "小技能冷却低于 4 秒时钳到 4")
	var wild := _skill(["power"], 8.0, 5.0)
	wild.base_damage = 999
	var clamped_hit := _hit(_stats(3, 3, 3, 3, 3, 3), wild, {"distance": 1.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(is_equal_approx(float(clamped_hit.damage), 220.0), "小技能基础伤钳在 220")
	var ult := _skill(["power"], 8.0, 1.0)
	ult.cost = "self_damage"
	var paid := _hit(_stats(3, 3, 3, 3, 3, 3), ult, {"distance": 1.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3), "is_ultimate": true})
	_check(float(paid.self_damage) >= 40.0 and is_equal_approx(float(paid.cooldown), 18.0), "大招自伤且冷却钳到 18")
	var naked := _skill(["power"], 8.0, 20.0)
	var no_cost := _hit(_stats(3, 3, 3, 3, 3, 3), naked, {"distance": 1.0, "is_ultimate": true})
	_check(not bool(no_cost.ok) and str(no_cost.code) == "ultimate_cost", "没有代价的大招不能结算")
	var control := _skill(["precision"], 8.0, 5.0, "control")
	var long_cc := _hit(_stats(3, 3, 3, 3, 5, 3), control, {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 5, 3, 3, 3, 3)})
	var short_cc := _hit(_stats(3, 3, 3, 3, 1, 3), control, {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3)})
	_check(float(long_cc.damage) == 0.0 and bool(long_cc.hit), "控制技能不靠伤害倍率")
	_check(is_equal_approx(float(short_cc.control_duration), 2.0 * (1.0 + 0.1 * (1 - 3)) * 1.0), "精密 1、守方速度 3 的控制时长")
	_check(is_equal_approx(float(long_cc.control_duration), 2.0 * (1.0 + 0.1 * (5 - 3)) * (1.15 - 0.05 * 5.0)), "高精密仍会被高速度缩短受控")
	var windowed := _hit(_stats(3, 3, 3, 3, 3, 3), _skill(["power"], 8.0, 5.0), {"distance": 2.0, "cover": "none", "defender_stats": _stats(3, 3, 3, 3, 3, 3), "defender_window": 1.0})
	_check(is_equal_approx(float(windowed.damage), 200.0 * 1.25), "空窗中受到的伤害提高")
	var steps: Array = grown.applied
	_check(steps.size() == 6 and str(steps[0]) == "range" and str(steps[5]) == "growth", "命中时六步都要走到")


func _check_covers() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "主场景应能加载")
	if packed == null:
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	await physics_frame
	var saw_half := false
	var saw_full := false
	for node in get_nodes_in_group("cover"):
		var kind := str(node.get_meta("cover_kind", ""))
		if kind == "half":
			saw_half = true
		if kind == "full":
			saw_full = true
	_check(saw_half and saw_full, "场景应同时有半掩和全掩")
	var half := CoverScript.between(self, Vector3(6, 1, -8), Vector3(6, 1, 0))
	var full := CoverScript.between(self, Vector3(-6, 1, -12), Vector3(-6, 1, -4))
	var open := CoverScript.between(self, Vector3(0, 0.9, 0), Vector3(0, 0.9, -6))
	_check(half == "half", "线段穿过半掩应得到 half，实际 " + half)
	_check(full == "full", "线段穿过全掩应得到 full，实际 " + full)
	_check(open == "none", "出生点到训练桩的中轴不应被掩体挡住，实际 " + open)
	get_root().remove_child(main)
	main.free()
