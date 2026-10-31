extends SceneTree
## W0 无头自检。退出码 0 且打印 “W0 checks passed” 才算通过。
## godot --headless --path . --script res://tests/run_w0_checks.gd

const ValidatorScript = preload("res://stand/stand_validator.gd")
const LibraryScript = preload("res://stand/stand_library.gd")
const CardScript = preload("res://stand/stand_card.gd")
const CombatScript = preload("res://gameplay/combat_stub.gd")
const NetScript = preload("res://net/net_room.gd")
const AiScript = preload("res://ai/stand_generator.gd")

const VALID_PATH := "res://stand/fixtures/valid_mirror_walker.json"
const INVALID_PATH := "res://stand/fixtures/invalid_overpowered.json"

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_files()
	var valid: Dictionary = _load_card(VALID_PATH)
	var invalid: Dictionary = _load_card(INVALID_PATH)
	_check_validator(valid, invalid)
	_check_library(valid, invalid)
	_check_stubs()
	await _check_scene()
	if _failed == 0:
		print("W0 checks passed")
		quit(0)
	else:
		print("W0 checks failed: %d" % _failed)
		quit(1)


func _check(cond: bool, message: String) -> void:
	if cond:
		return
	_failed += 1
	print("FAIL: ", message)


func _codes(result: Dictionary) -> PackedStringArray:
	var codes: PackedStringArray = []
	for entry in result.get("errors", []):
		codes.append(str(entry.get("code", "")))
	return codes


func _has(codes: PackedStringArray, code: String) -> bool:
	return code in codes


func _load_card(path: String) -> Dictionary:
	var card = CardScript.load_file(path)
	_check(card != null, "无法读取卡面 " + path)
	if card == null:
		return {}
	return card.data.duplicate(true)


func _check_files() -> void:
	for path in [
		"res://project.godot",
		"res://scenes/main.tscn",
		"res://docs/GDD.md",
		"res://docs/stand_card.schema.json",
		"res://docs/stand_generator_system_prompt.md",
		"res://docs/REPO_STRUCTURE.md",
		"res://README.md",
		VALID_PATH,
		INVALID_PATH,
	]:
		_check(FileAccess.file_exists(path), "缺少文件 " + path)
	var schema_text := FileAccess.get_file_as_string("res://docs/stand_card.schema.json")
	var schema = JSON.parse_string(schema_text)
	_check(typeof(schema) == TYPE_DICTIONARY and str(schema.get("title", "")) == "StandCard", "schema 标题应为 StandCard")


func _check_validator(valid: Dictionary, invalid: Dictionary) -> void:
	if valid.is_empty() or invalid.is_empty():
		_check(false, "夹具为空，跳过校验断言没有意义")
		return
	var passed: Dictionary = ValidatorScript.validate(valid)
	_check(passed.get("ok", false), "合法夹具应通过：%s" % str(passed.get("errors", [])))
	var rejected: Dictionary = ValidatorScript.validate(invalid)
	_check(not rejected.get("ok", true), "非法夹具应被拒绝")
	var rejected_codes := _codes(rejected)
	for code in ["stats_sum", "short_stat", "blacklist", "humanoid", "height", "triple_dip"]:
		_check(_has(rejected_codes, code), "非法夹具应包含错误码 " + code)
	_check(not _has(rejected_codes, "ultimate_cost"), "非法夹具已填写合法代价，不应误报 ultimate_cost")

	var flat := valid.duplicate(true)
	flat["stats"] = {"power": 3, "speed": 3, "range": 3, "stamina": 3, "precision": 3, "growth": 3}
	var flat_result: Dictionary = ValidatorScript.validate(flat)
	var flat_codes := _codes(flat_result)
	_check(not flat_result.get("ok", true), "全 3 应拒绝")
	_check(_has(flat_codes, "all_threes"), "全 3 应报 all_threes")
	_check(not _has(flat_codes, "stats_sum"), "全 3 总和仍是 18")

	var two_fives := valid.duplicate(true)
	two_fives["stats"] = {"power": 5, "speed": 5, "range": 2, "stamina": 2, "precision": 2, "growth": 2}
	var two_result: Dictionary = ValidatorScript.validate(two_fives)
	var two_codes := _codes(two_result)
	_check(_has(two_codes, "short_stat"), "两个 5 应触发短板规则")
	_check(not _has(two_codes, "stats_sum"), "5+5+2+2+2+2 总和为 18")

	var five_without_low := valid.duplicate(true)
	five_without_low["stats"] = {"power": 5, "speed": 4, "range": 4, "stamina": 4, "precision": 4, "growth": 4}
	var low_codes := _codes(ValidatorScript.validate(five_without_low))
	_check(_has(low_codes, "short_stat"), "有 5 且没有 ≤2 时应触发短板规则")

	var no_cost := valid.duplicate(true)
	no_cost["ultimate"].erase("cost")
	var cost_codes := _codes(ValidatorScript.validate(no_cost))
	_check(_has(cost_codes, "ultimate_cost"), "缺少大招代价应拒绝")

	var triple := valid.duplicate(true)
	triple["skills"][0]["primary_stats"] = ["power", "speed", "range"]
	var triple_codes := _codes(ValidatorScript.validate(triple))
	_check(_has(triple_codes, "triple_dip"), "力量+速度+射程应拒绝")

	for meters in [1.5, 2.0]:
		var edge := valid.duplicate(true)
		edge["appearance"]["height_m"] = meters
		_check(ValidatorScript.validate(edge).get("ok", false), "身高边界 %.1f 应通过" % meters)
	for meters in [1.49, 2.01]:
		var edge_bad := valid.duplicate(true)
		edge_bad["appearance"]["height_m"] = meters
		var height_codes := _codes(ValidatorScript.validate(edge_bad))
		_check(_has(height_codes, "height"), "身高 %.2f 应拒绝" % meters)

	var beast := valid.duplicate(true)
	beast["appearance"]["humanoid"] = false
	_check(_has(_codes(ValidatorScript.validate(beast)), "humanoid"), "非人形应拒绝")

	var negated := valid.duplicate(true)
	negated["ultimate"]["effect"] = "短时间连斩，不能重置大招。"
	var negated_codes := _codes(ValidatorScript.validate(negated))
	_check(ValidatorScript.validate(negated).get("ok", false), "否定句不应误伤黑名单：%s" % str(negated_codes))
	_check(not _has(negated_codes, "blacklist"), "「不能重置大招」不应报 blacklist")

	var blatant := valid.duplicate(true)
	blatant["ultimate"]["effect"] = "可以重置大招"
	_check(_has(_codes(ValidatorScript.validate(blatant)), "blacklist"), "肯定句里的重置大招仍应拒绝")

	var prose := valid.duplicate(true)
	prose["skills"][0]["effect"] = "这一击同时吃满力量、速度、射程。"
	prose["skills"][0]["primary_stats"] = ["power"]
	_check(_has(_codes(ValidatorScript.validate(prose)), "triple_dip"), "文案三连吃应拒绝")

	var bad_kind := valid.duplicate(true)
	bad_kind["skills"][0]["kind"] = "explode"
	_check(_has(_codes(ValidatorScript.validate(bad_kind)), "skill_kind"), "未知 kind 应拒绝")

	var no_summary := valid.duplicate(true)
	no_summary["appearance"]["summary"] = ""
	_check(_has(_codes(ValidatorScript.validate(no_summary)), "appearance"), "空外形简述应拒绝")

	var schema = JSON.parse_string(FileAccess.get_file_as_string("res://docs/stand_card.schema.json"))
	var stat_props: Dictionary = schema["properties"]["stats"]["properties"]
	_check(stat_props.size() == ValidatorScript.STAT_KEYS.size(), "schema 六维数量应与校验器一致")
	for key in ValidatorScript.STAT_KEYS:
		_check(stat_props.has(key), "schema 缺少属性 " + key)
	var cost_enum: Array = schema["$defs"]["ultimate"]["allOf"][1]["properties"]["cost"]["enum"]
	_check(cost_enum.size() == ValidatorScript.ULTIMATE_COSTS.size(), "大招代价枚举数量应一致")
	for cost in ValidatorScript.ULTIMATE_COSTS:
		_check(cost in cost_enum, "schema 缺少代价 " + cost)
	var kind_enum: Array = schema["$defs"]["skill"]["properties"]["kind"]["enum"]
	_check(kind_enum.size() == ValidatorScript.SKILL_KINDS.size(), "技能 kind 枚举数量应一致")
	for kind in ValidatorScript.SKILL_KINDS:
		_check(kind in kind_enum, "schema 缺少 kind " + kind)


func _check_library(valid: Dictionary, invalid: Dictionary) -> void:
	_check(LibraryScript.MAX_KEPT == 3, "保留上限必须是 3")
	var library = LibraryScript.new()
	if not invalid.is_empty():
		var rejected: Dictionary = library.try_keep(invalid)
		_check(not rejected.get("ok", true), "非法卡不能入库")
		_check(str(rejected.get("code", "")) == "invalid_card", "非法卡应返回 invalid_card")
		_check(library.size() == 0, "拒绝入库后库应仍为空")
	if valid.is_empty():
		_check(false, "没有合法卡，无法测试保留库容量")
		return
	for index in 3:
		var copy := valid.duplicate(true)
		copy["name"] = "镜步旅人%d" % index
		var kept: Dictionary = library.try_keep(copy)
		_check(kept.get("ok", false), "第 %d 张合法卡应入库" % (index + 1))
		copy["name"] = "被篡改"
		_check(library.get_card(index).get("name", "") != "被篡改", "入库后应与调用方字典隔离")
	var overflow: Dictionary = library.try_keep(valid.duplicate(true))
	_check(not overflow.get("ok", true) and str(overflow.get("code", "")) == "library_full", "第 4 张应因库满被拒绝")
	_check(library.size() == 3, "库满后数量仍是 3")
	_check(not library.discard(-1).get("ok", true), "非法下标不能弃卡")
	_check(library.discard(0).get("ok", false), "弃掉第 1 张应成功")
	_check(library.try_keep(valid.duplicate(true)).get("ok", false), "弃旧后应能再留")
	_check(library.size() == 3, "补入后数量回到 3")


func _check_stubs() -> void:
	var combat = CombatScript.new()
	var order: PackedStringArray = combat.resolve_order()
	_check(order.size() == 6 and order[0] == "range" and order[5] == "growth", "结算顺序应为射程到成长")
	var empty_hit: Dictionary = combat.resolve_hit({}, {})
	_check(empty_hit.has("ok") and not empty_hit.get("ok", true), "空技能不能结算为命中")
	combat.free()
	var net = NetScript.new()
	_check(net.has_method("host_room") and net.has_method("join_room") and net.has_method("close_room"), "房间应提供主机、加入和关闭")
	net.free()
	var ai = AiScript.new()
	_check(ai.has_method("generate_from_prompt"), "出卡入口应存在")
	var generated: Dictionary = ai.generate_from_prompt("", false)
	_check(not generated.get("ok", true), "空提示词应失败")
	ai.free()


func _check_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main.tscn 无法加载")
	if packed == null:
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	_check(main.get_node_or_null("Player") != null, "主场景缺少 Player")
	_check(main.get_node_or_null("LockOnCamera") != null, "主场景缺少 LockOnCamera")
	_check(main.get_node_or_null("HUD") != null, "主场景缺少 HUD")
	_check(main.get_node_or_null("Net") != null, "主场景缺少 Net")
	_check(main.get_node_or_null("AI") != null, "主场景缺少 AI")
	_check(main.get_node_or_null("Player/Combat") != null, "主场景缺少 Combat")
	await physics_frame
	await physics_frame
	var camera = main.get_node_or_null("LockOnCamera")
	var near = main.get_node_or_null("DummyTarget")
	var far = main.get_node_or_null("FarTarget")
	_check(camera != null and near != null and far != null, "主场景缺少锁定目标")
	if camera != null and camera.has_method("locked_point"):
		var point = camera.locked_point()
		_check(point != null and near != null and point.distance_to(near.global_position) < 0.2, "默认应锁最近的训练桩")
		if far != null:
			far.set_meta("hurt_priority", 5.0)
		await physics_frame
		var hurt_point = camera.locked_point()
		_check(hurt_point != null and far != null and hurt_point.distance_to(far.global_position) < 0.2, "受伤目标应压过距离")
	var label := main.get_node_or_null("HUD/Label") as Label
	_check(label != null and "远桩" in label.text, "HUD 应显示当前锁定名")
	if camera != null and camera.has_method("_unhandled_input"):
		var tab := InputEventKey.new()
		tab.pressed = true
		tab.physical_keycode = KEY_TAB
		camera._unhandled_input(tab)
		await physics_frame
		_check(camera.locked_point() == null, "Tab 应解除锁定")
		_check(label != null and "未锁定" in label.text, "解除锁定后 HUD 应显示未锁定")
		camera._unhandled_input(tab)
		await physics_frame
		var relock = camera.locked_point()
		_check(relock != null and far != null and relock.distance_to(far.global_position) < 0.2, "再次 Tab 应按受伤优先重新锁定")
	get_root().remove_child(main)
	main.free()
