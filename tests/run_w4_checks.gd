extends SceneTree
## W4 无头自检：进场 UI → 出卡校验 → 进房对轰 → 胜负 → 保留库。
## godot --headless --path . --script res://tests/run_w4_checks.gd

const CostumeScript = preload("res://ai/costume.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_docs()
	await _check_match()
	if _failed == 0:
		print("W4 checks passed")
		quit(0)
	else:
		print("W4 checks failed: %d" % _failed)
		quit(1)


func _check(cond: bool, message: String) -> void:
	if cond:
		return
	_failed += 1
	print("FAIL: ", message)


func _check_docs() -> void:
	var readme := FileAccess.get_file_as_string("res://README.md")
	for token in ["run_w0_checks.gd", "run_w1_checks.gd", "run_w2_checks.gd", "run_w3_checks.gd", "run_w4_checks.gd", "W4 checks passed"]:
		_check(token in readme, "README 应写明 " + token)
	var project := FileAccess.get_file_as_string("res://project.godot")
	_check("\"4.3\"" in project, "project.godot 功能标签应保持 4.3")
	var gdd := FileAccess.get_file_as_string("res://docs/GDD.md")
	_check("W4" in gdd and "竖切" in gdd, "策划书应标出竖切状态")


func _check_match() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "主场景应能加载")
	if packed == null:
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	await physics_frame
	var entry = main.get_node_or_null("Entry")
	var duel = main.get_node_or_null("Match")
	var player: Node3D = main.get_node_or_null("Player")
	var dummy: Node3D = main.get_node_or_null("DummyTarget")
	_check(entry != null and duel != null and player != null and dummy != null, "进场、对局、双方模型应在场景里")
	if entry == null or duel == null:
		return
	var generated: Dictionary = entry.generate_prompt("冷静的镜步剑客", false)
	_check(bool(generated.get("ok", false)), "进场生成应通过校验")
	var shown := _find_label_text(entry)
	_check("校验通过" in shown, "进场界面应展示校验通过")
	var began: Dictionary = entry.confirm()
	_check(bool(began.get("ok", false)) and duel.started, "确认后应进入对局")
	_check(not entry.visible, "进局后面板应收起")
	var card: Dictionary = generated.get("card", {})
	var body := player.get_node_or_null("Body") as MeshInstance3D
	var material: StandardMaterial3D = null
	if body != null:
		material = body.material_override as StandardMaterial3D
	var expected := CostumeScript.color_from_card(card)
	_check(material != null and is_equal_approx(material.albedo_color.r, expected.r), "模板人形应按卡面换色")
	var picked: Dictionary = duel.grant_local_pickup()
	_check(bool(picked.get("ok", false)) and int(picked.get("layers", 0)) == 1, "拾取应叠 1 层")
	var guard := 0
	while not bool(duel.authority.snapshot().get("finished", false)) and guard < 16:
		player.global_position = Vector3(0, 0.9, 0)
		dummy.global_position = Vector3(0, 0.9, -3)
		duel.authority.tick(30.0)
		duel.cast_as(1, 1)
		guard += 1
	var snap: Dictionary = duel.authority.snapshot()
	_check(bool(snap.get("finished", false)) and int(snap.get("winner_id", 0)) == 1, "玩家应击倒训练桩")
	_check(int(player.get_meta("layers", 0)) == 3, "击倒把层数顶到 3，且不继承到下一局卡面")
	_check(duel.library.size() == 1, "胜者卡应写入保留库")
	var kept: Dictionary = duel.library.get_card(0)
	_check(str(kept.get("name", "")) == str(card.get("name", "")), "库里是本局这张卡")
	_check(not kept.has("layers"), "保留卡不含成长层")
	_check(str(kept.get("name", "")) != "柱卫", "败者训练桩不应入库")
	for index in duel.library.size():
		_check(str(duel.library.get_card(index).get("name", "")) != "柱卫", "库中不应出现败者")
	var hud_root = main.get_node_or_null("HUD")
	if hud_root != null and hud_root.has_method("_refresh"):
		hud_root._refresh()
	var hud := main.get_node_or_null("HUD/Label") as Label
	_check(hud != null and "生命" in hud.text and "成长 3/3" in hud.text, "HUD 应显示生命和本局成长层，实际：%s" % (hud.text if hud != null else "无"))
	_check("胜者" in str(duel.result_text), "结算文案应说明胜者入库")
	get_root().remove_child(main)
	main.free()


func _find_label_text(root: Node) -> String:
	var chunks := ""
	if root is Label:
		chunks = (root as Label).text
	for child in root.get_children():
		chunks += "\n" + _find_label_text(child)
	return chunks
